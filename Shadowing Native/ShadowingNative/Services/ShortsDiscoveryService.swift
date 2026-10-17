import Foundation
import OSLog

actor ShortsDiscoveryService {
    static let shared = ShortsDiscoveryService()
    private static let logger = Logger(subsystem: "com.edromero.shadowing.next", category: "YouTubeSearch")

    private let session: URLSession
    private let apiKey: String?
    private let defaults: UserDefaults
    private let transcriptLoader: @Sendable (String) async throws -> YouTubeTranscript
    private var discoverySessions: [String: DiscoverySession] = [:]
    private var videoRequests: [String: (id: UUID, task: Task<[VideoSuggestion], Error>)] = [:]
    private var shortSearchCache: [String: (savedAt: Date, results: ShortsSearchResults)] = [:]
    private var shortSearchSessions: [String: ShortSearchSession] = [:]

    init(
        apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "YouTubeDataAPIKey") as? String,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        transcriptLoader: @escaping @Sendable (String) async throws -> YouTubeTranscript = {
            try await YouTubeTranscriptService.shared.fetchTranscript(videoID: $0)
        }
    ) {
        self.apiKey = apiKey
        self.session = session
        self.defaults = defaults
        self.transcriptLoader = transcriptLoader
    }

    var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty && !key.contains("$(")
    }

    func discover(
        for profile: LearningProfile,
        feedback: [String: ShortFeedback],
        channels: [ShortChannelPreference] = [],
        searches: [ShortSearchPreference] = [],
        excluding excludedIDs: Set<String> = [],
        limit: Int = 3
    ) async throws -> [YouTubeShortItem] {
        try await discoverBatch(for: profile, feedback: feedback, channels: channels, searches: searches, excluding: excludedIDs, limit: limit).items
    }

    func discoverBatch(
        for profile: LearningProfile,
        feedback: [String: ShortFeedback],
        channels preferredChannels: [ShortChannelPreference] = [],
        searches recentSearches: [ShortSearchPreference] = [],
        excluding excludedIDs: Set<String> = [],
        limit: Int = 3
    ) async throws -> ShortsDiscoveryBatch {
        guard limit > 0 else { return ShortsDiscoveryBatch(items: [], hasMoreCandidates: false) }
        guard let key = apiKey,
              !key.isEmpty, !key.contains("$(") else {
            throw DiscoveryError.missingAPIKey
        }

        let interests = Array(profile.interests)
            .sorted { $0.rawValue < $1.rawValue }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let rotated = interests.isEmpty ? [] : (0..<interests.count).map { interests[(day + $0) % interests.count] }
        let affinity = feedback.values.reduce(into: [LearningInterest: Int]()) { scores, item in
            let weight: Int
            switch item.reaction {
            case .liked: weight = 3
            case .hidden: weight = -1
            case .neutral: weight = 0
            }
            for interest in item.interests.intersection(profile.interests) {
                scores[interest, default: 0] += weight
            }
        }
        let selected = rotated.enumerated().sorted {
            let firstScore = affinity[$0.element, default: 0]
            let secondScore = affinity[$1.element, default: 0]
            return firstScore == secondScore ? $0.offset < $1.offset : firstScore > secondScore
        }.map(\.element)
        let followed = preferredChannels.filter(\.isFollowed).prefix(8)
        let searchTerms = recentSearches.sorted {
            $0.count == $1.count ? $0.updatedAt > $1.updatedAt : $0.count > $1.count
        }.prefix(5)
        let preferredIDs = Set(followed.map(\.id))
        let preferredQueries = Set(searchTerms.map { $0.query.lowercased() })
        let today = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let cacheKey = "shadowing.shorts.discovery.v15.\(today).\(profile.level.rawValue).\(selected.map(\.rawValue).joined(separator: ".")).\(followed.map(\.id).joined(separator: ".")).\(searchTerms.map { $0.query.lowercased() }.joined(separator: "."))"
        let rollingCacheKey = "shadowing.shorts.verified.v2.\(profile.level.rawValue).\(selected.map(\.rawValue).joined(separator: ".")).\(followed.map(\.id).joined(separator: ".")).\(searchTerms.map { $0.query.lowercased() }.joined(separator: "."))"
        let channelGroups = selected.map { interest in
            let curated = interest.curatedChannelIDs.map { DiscoverySource(id: $0, interest: interest) }
            let query = [DiscoverySource(id: "query:\(interest.rawValue)", interest: interest)]
            return profile.level == .beginner ? query + curated : curated + query
        }
        let personalSources = followed.map { DiscoverySource(id: $0.id, interest: nil) }
            + searchTerms.map { DiscoverySource(id: "search:\($0.query.lowercased())", interest: nil, searchQuery: $0.query) }
        let channels = personalSources + (0..<(channelGroups.map(\.count).max() ?? 0)).flatMap { index in
            channelGroups.compactMap { group in group.indices.contains(index) ? group[index] : nil }
        }
        let dailyCached = cachedItems(for: cacheKey)
        var state = discoverySessions[cacheKey] ?? DiscoverySession(
            verified: dailyCached.isEmpty ? cachedItems(for: rollingCacheKey, maxAge: 3 * 24 * 3600) : dailyCached,
            channels: channels
        )
        let rejectedIDs = Set(feedback.values.filter { $0.reaction == .hidden || $0.difficulty == .tooHard }.map(\.videoID))
        let unavailableIDs = excludedIDs.union(rejectedIDs)
        var available = state.verified.filter { !unavailableIDs.contains($0.videoID) }
        if available.count >= limit {
            return ShortsDiscoveryBatch(items: diversified(available, interests: selected, preferredIDs: preferredIDs, preferredQueries: preferredQueries, limit: limit), hasMoreCandidates: state.hasMoreCandidates || available.count > limit)
        }

        var searchRequests = 0
        let budgetKey = "shadowing.shorts.discovery-budget.\(today)"
        var remainingDailySearches = max(0, 8 - defaults.integer(forKey: budgetKey))
        var inspectedCount = 0
        var lastSearchError: Error?
        var failedChannels = Set<String>()
        let searchBudget = min(4, max(2, selected.count))
        while available.count < limit, inspectedCount < 12 {
            try Task.checkCancellation()
            guard let channel = state.nextChannel(canSearch: searchRequests < searchBudget && remainingDailySearches > 0, skipping: failedChannels) else { break }
            if state.pendingByChannel[channel.id, default: []].isEmpty {
                searchRequests += 1
                remainingDailySearches -= 1
                defaults.set(8 - remainingDailySearches, forKey: budgetKey)
                let results: SearchResponse
                do {
                    results = try await search(
                        channelID: channel.id,
                        queryOverride: channel.searchQuery,
                        pageToken: state.pageTokens[channel.id],
                        level: profile.level,
                        key: key
                    )
                } catch {
                    try Task.checkCancellation()
                    if let failure = error as? YouTubeSearchAPIError, failure.blocksFurtherSearches { throw failure }
                    lastSearchError = error
                    failedChannels.insert(channel.id)
                    continue
                }
                state.pageTokens[channel.id] = results.nextPageToken
                if results.nextPageToken == nil { state.exhaustedChannels.insert(channel.id) }
                let inspectedIDs = state.inspectedIDs
                state.pendingByChannel[channel.id] = results.items.compactMap { result in
                    guard let id = result.id.videoId, !id.isEmpty,
                          (channel.id.hasPrefix("query:") || result.snippet.channelId == channel.id),
                          !inspectedIDs.contains(id) else { return nil }
                    return YouTubeShortItem(
                        videoID: id,
                        title: result.snippet.title,
                        topic: channel.interest?.title ?? (channel.searchQuery == nil ? "Canal escolhido" : "Sua busca"),
                        hook: channel.interest.map { "Treine com inglês real sobre \($0.title.lowercased())." } ?? "Treine com um Short escolhido por você.",
                        level: .intermediate,
                        interests: channel.interest.map { [$0] } ?? [],
                        creator: result.snippet.channelTitle,
                        channelID: result.snippet.channelId,
                        searchQuery: channel.searchQuery
                    )
                }
            }

            state.pendingByChannel[channel.id]?.removeAll { unavailableIDs.contains($0.videoID) }
            let batch = Array(state.pendingByChannel[channel.id, default: []].prefix(3))
            state.pendingByChannel[channel.id]?.removeFirst(batch.count)
            for item in batch { state.inspectedIDs.insert(item.videoID) }
            inspectedCount += batch.count
            let matches = await withTaskGroup(of: YouTubeShortItem?.self) { group in
                for item in batch {
                    group.addTask {
                        guard let transcript = try? await self.transcriptLoader(item.videoID),
                              transcript.languageCode.lowercased().hasPrefix("en"),
                              (channel.interest?.matchesContent(title: item.title, transcript: transcript) ?? true),
                              let estimatedLevel = ShortDifficultyEstimator.estimate(transcript: transcript, titleHint: item.title),
                              estimatedLevel == profile.level else { return nil }
                        return YouTubeShortItem(
                            videoID: item.videoID,
                            title: item.title,
                            topic: item.topic,
                            hook: item.hook,
                            level: estimatedLevel,
                            interests: item.interests,
                            creator: item.creator,
                            channelID: item.channelID,
                            searchQuery: item.searchQuery
                        )
                    }
                }
                var accepted: [YouTubeShortItem] = []
                for await item in group {
                    if let item {
                        accepted.append(item)
                        if accepted.count >= limit - available.count {
                            group.cancelAll()
                            break
                        }
                    }
                }
                let resultOrder = Dictionary(batch.enumerated().map { ($0.element.videoID, $0.offset) }, uniquingKeysWith: { first, _ in first })
                return accepted.sorted { resultOrder[$0.videoID, default: 0] < resultOrder[$1.videoID, default: 0] }
            }
            try Task.checkCancellation()
            state.verified.append(contentsOf: matches)
            available.append(contentsOf: matches.filter { !unavailableIDs.contains($0.videoID) })
        }

        discoverySessions[cacheKey] = state
        if available.isEmpty, let lastSearchError { throw lastSearchError }
        if let data = try? JSONEncoder().encode(DiscoveryCache(savedAt: Date(), items: state.verified)) {
            defaults.set(data, forKey: cacheKey)
            defaults.set(data, forKey: rollingCacheKey)
        }
        return ShortsDiscoveryBatch(items: diversified(available, interests: selected, preferredIDs: preferredIDs, preferredQueries: preferredQueries, limit: limit), hasMoreCandidates: state.hasMoreCandidates || available.count > limit)
    }

    private func diversified(
        _ items: [YouTubeShortItem],
        interests: [LearningInterest],
        preferredIDs: Set<String>,
        preferredQueries: Set<String>,
        limit: Int
    ) -> [YouTubeShortItem] {
        var chosen: [YouTubeShortItem] = []
        var selectedIDs = Set<String>()
        for item in items where item.channelID.map(preferredIDs.contains) == true || item.searchQuery.map({ preferredQueries.contains($0.lowercased()) }) == true {
            guard selectedIDs.insert(item.videoID).inserted else { continue }
            chosen.append(item)
            if chosen.count == limit { return chosen }
        }
        for interest in interests {
            guard let item = items.first(where: {
                $0.interests.contains(interest) && !selectedIDs.contains($0.videoID)
            }) else { continue }
            chosen.append(item)
            selectedIDs.insert(item.videoID)
            if chosen.count == limit { return chosen }
        }
        chosen.append(contentsOf: items.filter { !selectedIDs.contains($0.videoID) }.prefix(limit - chosen.count))
        return chosen
    }

    func discoverVideos(
        for profile: LearningProfile,
        limit: Int = 8,
        refresh: Bool = false
    ) async throws -> [VideoSuggestion] {
        guard limit > 0 else { return [] }
        guard let key = apiKey,
              !key.isEmpty, !key.contains("$(") else {
            throw DiscoveryError.missingAPIKey
        }

        let interests = profile.interests.sorted { $0.rawValue < $1.rawValue }
        let today = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let cacheKey = "shadowing.videos.discovery.v8.\(today).\(profile.level.rawValue).\(interests.map(\.rawValue).joined(separator: "."))"
        if !refresh,
           let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(VideoDiscoveryCache.self, from: data) {
            return Array(cached.items.prefix(limit))
        }

        let requestKey = "\(cacheKey).\(limit)"
        if let pending = videoRequests[requestKey] {
            let result = try await pending.task.value
            try Task.checkCancellation()
            return result
        }
        let requestID = UUID()
        let task = Task {
            try await self.performVideoDiscovery(for: profile, interests: interests, key: key, cacheKey: cacheKey, limit: limit)
        }
        videoRequests[requestKey] = (requestID, task)
        defer {
            if videoRequests[requestKey]?.id == requestID { videoRequests.removeValue(forKey: requestKey) }
        }
        let result = try await task.value
        try Task.checkCancellation()
        return result
    }

    private func performVideoDiscovery(
        for profile: LearningProfile,
        interests: [LearningInterest],
        key: String,
        cacheKey: String,
        limit: Int
    ) async throws -> [VideoSuggestion] {
        var suggestions: [VideoSuggestion] = []
        var seenIDs = Set<String>()
        var lastError: Error?
        for interest in interests {
            try Task.checkCancellation()
            let channelIDs = interest.curatedChannelIDs
            let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let channelID = profile.level == .beginner || channelIDs.isEmpty
                ? nil
                : channelIDs[day % channelIDs.count]

            var results: SearchResponse?
            do {
                results = try await searchVideos(interest: interest, level: profile.level, channelID: channelID, key: key)
            } catch {
                lastError = error
            }
            if results == nil, channelID != nil {
                do {
                    results = try await searchVideos(interest: interest, level: profile.level, channelID: nil, key: key)
                } catch {
                    lastError = error
                }
            }
            guard let results else { continue }
            var matches = await verifyVideos(results.items, interest: interest, level: profile.level, excluding: seenIDs)
            if matches.isEmpty, channelID != nil {
                do {
                    let fallback = try await searchVideos(interest: interest, level: profile.level, channelID: nil, key: key)
                    matches = await verifyVideos(fallback.items, interest: interest, level: profile.level, excluding: seenIDs)
                } catch {
                    lastError = error
                }
            }
            for suggestion in matches.prefix(2) where seenIDs.insert(suggestion.videoID).inserted {
                suggestions.append(suggestion)
            }
            if suggestions.count >= limit { break }
        }

        if suggestions.isEmpty, let lastError { throw lastError }
        if !suggestions.isEmpty,
           let data = try? JSONEncoder().encode(VideoDiscoveryCache(items: suggestions)) {
            defaults.set(data, forKey: cacheKey)
        }
        return Array(suggestions.prefix(limit))
    }

    private func verifyVideos(
        _ results: [SearchResult],
        interest: LearningInterest,
        level: EnglishLevel,
        excluding seenIDs: Set<String>
    ) async -> [VideoSuggestion] {
        let candidates = Array(results.prefix(12)).filter { result in
            guard let videoID = result.id.videoId else { return false }
            return !seenIDs.contains(videoID)
        }
        // No máximo 3 legendas por vez: rajadas maiores levam o YouTube a bloquear (HTTP 429).
        // A tela usa só os 2 primeiros por tema, então para assim que tiver 2.
        var verified: [VideoSuggestion] = []
        for batchStart in stride(from: 0, to: candidates.count, by: 3) {
            let batch = Array(candidates[batchStart..<min(batchStart + 3, candidates.count)])
            let found = await withTaskGroup(of: (Int, VideoSuggestion?).self) { group in
                for (offset, result) in batch.enumerated() {
                    group.addTask { (offset, await self.verifyVideo(result, interest: interest, level: level)) }
                }
                var items: [(Int, VideoSuggestion?)] = []
                for await item in group { items.append(item) }
                return items.sorted { $0.0 < $1.0 }.compactMap(\.1)
            }
            verified.append(contentsOf: found)
            if verified.count >= 2 || Task.isCancelled { break }
        }
        return verified
    }

    private func verifyVideo(_ result: SearchResult, interest: LearningInterest, level: EnglishLevel) async -> VideoSuggestion? {
        guard let videoID = result.id.videoId,
              let transcript = try? await transcriptLoader(videoID),
              transcript.languageCode.lowercased().hasPrefix("en"),
              interest.matchesContent(title: result.snippet.title, transcript: transcript),
              let firstStart = transcript.segments.first?.start else { return nil }
        let sample = YouTubeTranscript(
            videoID: videoID,
            title: transcript.title,
            channel: transcript.channel,
            languageCode: transcript.languageCode,
            source: transcript.source,
            segments: Array(transcript.segments.prefix { $0.start < firstStart + 120 })
        )
        guard ShortDifficultyEstimator.estimate(transcript: sample, titleHint: result.snippet.title) == level else { return nil }
        return VideoSuggestion(
            videoID: videoID,
            title: result.snippet.title,
            creator: result.snippet.channelTitle,
            source: .youtube,
            durationMinutes: nil,
            level: level,
            interests: [interest],
            goals: [.listening],
            accent: .blue,
            hook: "Inglês real sobre \(interest.title.lowercased())"
        )
    }

    private func searchVideos(
        interest: LearningInterest,
        level: EnglishLevel,
        channelID: String?,
        key: String
    ) async throws -> SearchResponse {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoDuration", value: "medium"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "relevanceLanguage", value: "en"),
            URLQueryItem(name: "maxResults", value: "12"),
            URLQueryItem(name: "key", value: key)
        ]
        if let channelID {
            components.queryItems?.append(URLQueryItem(name: "channelId", value: channelID))
            components.queryItems?.append(URLQueryItem(name: "order", value: "date"))
        } else {
            let query: String
            switch level {
            case .beginner: query = "\(interest.beginnerQuery) English conversation beginner"
            case .intermediate: query = "English \(interest.discoveryQuery) intermediate listening"
            case .advanced: query = "English \(interest.discoveryQuery)"
            }
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: request)
        try validateSearchResponse(response, data: data)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    private func cachedItems(for key: String, maxAge: TimeInterval? = nil) -> [YouTubeShortItem] {
        guard let data = defaults.data(forKey: key),
              let cache = try? JSONDecoder().decode(DiscoveryCache.self, from: data) else { return [] }
        if let maxAge, Date().timeIntervalSince(cache.savedAt) > maxAge { return [] }
        return cache.items
    }

    private func search(
        channelID: String,
        queryOverride: String?,
        pageToken: String?,
        level: EnglishLevel,
        key: String
    ) async throws -> SearchResponse {
        let interest = channelID.hasPrefix("query:")
            ? LearningInterest(rawValue: String(channelID.dropFirst("query:".count)))
            : nil
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoDuration", value: "short"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "relevanceLanguage", value: "en"),
            URLQueryItem(name: "maxResults", value: "25"),
            URLQueryItem(name: "key", value: key)
        ]
        // Sem `#shorts` na consulta: `videoDuration=short` já filtra a duração e a hashtag traz
        // sobretudo vídeos sem fala. Canal sem consulta lista os Shorts mais recentes dele.
        if let query = queryOverride.map(Self.youtubeQuery(for:)) ?? interest.map({
            level == .beginner ? "\($0.beginnerQuery) English conversation beginner" : $0.discoveryQuery
        }) {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        } else {
            components.queryItems?.append(URLQueryItem(name: "channelId", value: channelID))
            components.queryItems?.append(URLQueryItem(name: "order", value: "date"))
        }
        if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: request)
        try validateSearchResponse(response, data: data)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    func searchShortsAndChannels(query text: String, level: EnglishLevel) async throws -> ShortsSearchResults {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else { throw DiscoveryError.missingAPIKey }
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard query.count >= 2 else { return ShortsSearchResults(channels: [], shorts: []) }
        let cacheKey = "\(level.rawValue)|\(query.lowercased())"
        if let cached = shortSearchCache[cacheKey], Date().timeIntervalSince(cached.savedAt) < 600 {
            return cached.results
        }

        async let channels = searchChannels(query: query)
        async let shorts = searchShorts(query: query, level: level)
        let channelItems = try await channels
        let shortItems = try await shorts.items
        let results = ShortsSearchResults(channels: channelItems, shorts: shortItems)
        shortSearchCache[cacheKey] = (Date(), results)
        return results
    }

    func searchChannels(query text: String) async throws -> [ShortsChannelResult] {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else { throw DiscoveryError.missingAPIKey }
        let typed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard typed.count >= 2 else { return [] }
        // Mesma tradução da busca de Shorts: "viagem" trazia só canais brasileiros, sem legenda em inglês.
        let response = try await searchDirect(query: Self.youtubeQuery(for: typed), type: "channel", key: key)
        return response.items.compactMap { result in
            guard let id = result.id.channelId, !id.isEmpty else { return nil }
            return ShortsChannelResult(id: id, title: result.snippet.title)
        }
    }

    func searchChannelShorts(channel: ShortsChannelResult, query text: String, level: EnglishLevel) async throws -> [YouTubeShortItem] {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else { throw DiscoveryError.missingAPIKey }
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let response = try await search(channelID: channel.id, queryOverride: nil, pageToken: nil, level: level, key: key)
        return response.items.compactMap { result in
            guard let id = result.id.videoId, !id.isEmpty, result.snippet.channelId == channel.id else { return nil }
            return YouTubeShortItem(videoID: id, title: result.snippet.title, topic: "Canal escolhido", hook: "Short de \(channel.title)", level: level, interests: [], creator: channel.title, channelID: channel.id, searchQuery: query)
        }
    }

    /// Busca Shorts pela lupa. Cada chamada verifica alguns candidatos por vez e guarda o restante
    /// da página para `loadMore`, evitando disparar dezenas de pedidos de legenda de uma só vez.
    func searchShorts(query text: String, level: EnglishLevel, loadMore: Bool = false) async throws -> ShortsSearchPage {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else { throw DiscoveryError.missingAPIKey }
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard query.count >= 2 else { return ShortsSearchPage(items: [], youtubeQuery: query, hasMore: false) }
        let youtubeQuery = Self.youtubeQuery(for: query)
        let sessionKey = "\(level.rawValue)|\(youtubeQuery.lowercased())"
        if !loadMore, let recent = shortSearchSessions[sessionKey],
           !recent.accepted.isEmpty, Date().timeIntervalSince(recent.startedAt) < 600 {
            return recent.page(level: level, youtubeQuery: youtubeQuery)
        }
        var state = loadMore ? shortSearchSessions[sessionKey] ?? ShortSearchSession() : ShortSearchSession()

        let wanted = 6
        var acceptedNow = 0
        var inspectedNow = 0
        var pagesNow = 0
        var lastError: Error?
        while acceptedNow < wanted, inspectedNow < 18 {
            try Task.checkCancellation()
            if state.pending.isEmpty {
                guard state.canLoadPage, pagesNow < 2 else { break }
                do {
                    let response = try await searchDirect(query: youtubeQuery, type: "video", key: key, pageToken: state.nextPageToken)
                    pagesNow += 1
                    state.pagesLoaded += 1
                    state.nextPageToken = response.nextPageToken
                    state.pending = response.items.filter { result in
                        guard let id = result.id.videoId, !id.isEmpty, !state.inspectedIDs.contains(id) else { return false }
                        return !Self.titleSuggestsNoSpeech(result.snippet.title)
                    }
                } catch {
                    try Task.checkCancellation()
                    lastError = error
                    break
                }
                continue
            }

            let batch = Array(state.pending.prefix(3))
            state.pending.removeFirst(batch.count)
            inspectedNow += batch.count
            batch.compactMap(\.id.videoId).forEach { state.inspectedIDs.insert($0) }
            let outcomes = await withTaskGroup(of: (Int, SearchVerification).self) { group in
                for (index, result) in batch.enumerated() {
                    group.addTask { (index, await self.verifySearchResult(result, level: level, query: query)) }
                }
                var outcomes: [(Int, SearchVerification)] = []
                for await outcome in group { outcomes.append(outcome) }
                return outcomes.sorted { $0.0 < $1.0 }.map(\.1)
            }
            try Task.checkCancellation()
            for outcome in outcomes {
                if case .accepted(let item) = outcome {
                    state.accepted.append(item)
                    acceptedNow += 1
                }
            }
            if outcomes.contains(where: { if case .rateLimited = $0 { true } else { false } }) {
                lastError = DiscoveryError.captionsRateLimited
                break
            }
        }

        shortSearchSessions[sessionKey] = state
        if state.accepted.isEmpty, let lastError { throw lastError }
        return state.page(level: level, youtubeQuery: youtubeQuery)
    }

    private func verifySearchResult(_ result: SearchResult, level: EnglishLevel, query: String) async -> SearchVerification {
        guard let id = result.id.videoId else { return .rejected }
        let transcript: YouTubeTranscript
        do {
            transcript = try await transcriptLoader(id)
        } catch TranscriptError.requestFailed(let status) where status == 429 {
            return .rateLimited
        } catch {
            return .rejected
        }
        guard transcript.languageCode.lowercased().hasPrefix("en"),
              let estimated = ShortDifficultyEstimator.estimate(transcript: transcript, titleHint: result.snippet.title),
              estimated.isNear(level) else { return .rejected }
        let title = result.snippet.title
        let interests = Set(LearningInterest.allCases.filter { $0.matchesContent(title: title, transcript: transcript) })
        return .accepted(YouTubeShortItem(
            videoID: id,
            title: title,
            topic: "Sua busca",
            hook: "Um Short encontrado por você.",
            level: estimated,
            interests: interests,
            creator: result.snippet.channelTitle,
            channelID: result.snippet.channelId,
            searchQuery: query
        ))
    }

    /// Converte o texto digitado na consulta enviada ao YouTube. Termos de tema em português viram
    /// inglês, porque a busca em português só devolve vídeos sem legenda em inglês.
    nonisolated static func youtubeQuery(for text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"(?i)#?\bshorts?\b"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return text }
        var folded = " " + cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}' ]+"#, with: " ", options: .regularExpression) + " "
        var translated = false
        for (portuguese, english) in portugueseSearchTerms where folded.contains(" \(portuguese) ") {
            folded = folded.replacingOccurrences(of: " \(portuguese) ", with: " \(english) ")
            translated = true
        }
        guard translated else { return cleaned }
        let words = folded.split(separator: " ").map(String.init).filter { !portugueseStopWords.contains($0) }
        return words.isEmpty ? cleaned : words.joined(separator: " ")
    }

    private nonisolated static func titleSuggestsNoSpeech(_ title: String) -> Bool {
        title.range(of: #"(?i)(\basmr\b|#?\bedits?\b|\blyrics?\b|\bsongs?\b|\bmusic video\b|\bslowed\b|\breverb\b|\bphonk\b|\bamv\b|\bfancam\b|\bremix\b)"#, options: .regularExpression) != nil
    }

    // Frases antes de palavras soltas, para "entrevista de rua" não virar só "interview".
    private nonisolated static let portugueseSearchTerms: [(String, String)] = [
        ("entrevistas de rua", "street interviews"), ("entrevista de rua", "street interview"),
        ("entrevista de emprego", "job interview"), ("entrevistas de emprego", "job interviews"),
        ("morar fora", "living abroad"), ("estudar fora", "study abroad"), ("intercambio", "study abroad"),
        ("videogames", "video games"),
        ("vida real", "daily life"), ("dia a dia", "daily life"), ("rotina", "daily routine"),
        ("viagens", "travel"), ("viagem", "travel"), ("viajar", "travel"), ("turismo", "travel"),
        ("aeroporto", "airport"), ("ferias", "vacation"),
        ("compras", "shopping"), ("comprar", "shopping"), ("supermercado", "grocery store"), ("loja", "store"),
        ("culinaria", "cooking"), ("cozinhar", "cooking"), ("cozinha", "cooking"), ("receitas", "recipes"),
        ("receita", "recipe"), ("comida", "food"), ("restaurante", "restaurant"),
        ("tecnologia", "technology"), ("celular", "phone"), ("computador", "computer"),
        ("inteligencia artificial", "artificial intelligence"),
        ("negocios", "business"), ("empreendedorismo", "entrepreneur"), ("trabalho", "work"),
        ("carreira", "career"), ("curriculo", "resume"), ("reuniao", "business meeting"),
        ("dinheiro", "money"), ("financas", "finance"), ("investimentos", "investing"), ("investir", "investing"),
        ("acoes", "stock market"), ("bolsa de valores", "stock market"), ("empresa", "company"),
        ("filmes", "movies"), ("filme", "movie"), ("series", "tv series"), ("serie", "tv series"),
        ("cinema", "movies"), ("ator", "actor"), ("atriz", "actress"),
        ("musica", "music"), ("musicas", "music"), ("cantor", "singer"), ("cantora", "singer"), ("banda", "band"),
        ("noticias", "news"), ("politica", "politics"), ("economia", "economy"),
        ("historia", "history"), ("geografia", "geography"),
        ("saude", "health"), ("medicina", "medicine"), ("medico", "doctor"), ("hospital", "hospital"), ("farmacia", "pharmacy"),
        ("ciencia", "science"), ("espaco", "space"), ("fisica", "physics"), ("biologia", "biology"),
        ("engenharia", "engineering"), ("construcao", "construction"), ("arquitetura", "architecture"), ("obras", "construction"),
        ("carros", "cars"), ("carro", "car"), ("motores", "engines"), ("mecanica", "car mechanics"), ("automoveis", "cars"),
        ("aviacao", "aviation"), ("aviao", "airplane"), ("avioes", "airplanes"), ("piloto", "pilot"), ("pilotos", "pilots"),
        ("agricultura", "agriculture"), ("agronegocio", "agribusiness"), ("agro", "farming"), ("fazenda", "farm"), ("pecuaria", "livestock farming"), ("campo", "farming"),
        ("esportes", "sports"), ("esporte", "sports"), ("futebol americano", "nfl"), ("futebol", "soccer"),
        ("basquete", "basketball"), ("tenis", "tennis"),
        ("humor", "comedy"), ("comedia", "comedy"), ("engracado", "funny"), ("piadas", "jokes"), ("piada", "joke"),
        ("jogos", "video games"), ("jogo", "video game"),
        ("academia", "gym"), ("musculacao", "bodybuilding"), ("treino", "workout"), ("exercicios", "exercises"),
        ("entrevistas", "interviews"), ("entrevista", "interview"), ("conversa", "conversation"),
        ("pronuncia", "pronunciation"), ("ingles", "english")
    ]

    private nonisolated static let portugueseStopWords: Set<String> = [
        "de", "da", "do", "das", "dos", "e", "em", "no", "na", "nos", "nas", "para", "pra", "com",
        "um", "uma", "o", "a", "os", "as", "sobre"
    ]

    private func searchDirect(query: String, type: String, key: String, pageToken: String? = nil) async throws -> SearchResponse {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "maxResults", value: type == "channel" ? "5" : "25"),
            URLQueryItem(name: "key", value: key)
        ]
        if type == "video" {
            // `videoDuration=short` já limita a menos de 4 minutos. Não acrescentar `#shorts`:
            // a hashtag puxa edits, música e ASMR, quase sempre sem fala nem legenda em inglês.
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "videoDuration", value: "short"),
                URLQueryItem(name: "videoEmbeddable", value: "true"),
                URLQueryItem(name: "relevanceLanguage", value: "en"),
                URLQueryItem(name: "regionCode", value: "US")
            ])
        }
        if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: request)
        try validateSearchResponse(response, data: data)
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    private func validateSearchResponse(_ response: URLResponse, data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw DiscoveryError.searchFailed }
        guard status != 200 else { return }
        let failure = YouTubeSearchAPIError(statusCode: status, data: data)
        Self.logger.error("YouTube search failed: status=\(status) reason=\(failure.reason.rawValue, privacy: .public)")
        throw failure
    }

}

struct ShortsDiscoveryBatch: Sendable {
    let items: [YouTubeShortItem]
    let hasMoreCandidates: Bool
}

struct ShortsSearchPage: Sendable {
    let items: [YouTubeShortItem]
    /// Consulta enviada ao YouTube; difere do texto digitado quando termos em português foram traduzidos.
    let youtubeQuery: String
    let hasMore: Bool
}

private enum SearchVerification: Sendable {
    case accepted(YouTubeShortItem)
    case rejected
    case rateLimited
}

private struct ShortSearchSession {
    var pending: [SearchResult] = []
    var nextPageToken: String?
    var pagesLoaded = 0
    var inspectedIDs: Set<String> = []
    var accepted: [YouTubeShortItem] = []
    let startedAt = Date()

    var canLoadPage: Bool {
        pagesLoaded == 0 || (nextPageToken != nil && pagesLoaded < 4)
    }

    /// Nível exato primeiro; dentro de cada grupo, a ordem de relevância do YouTube.
    func page(level: EnglishLevel, youtubeQuery: String) -> ShortsSearchPage {
        let ordered = accepted.enumerated().sorted { first, second in
            let firstExact = first.element.level == level
            let secondExact = second.element.level == level
            return firstExact == secondExact ? first.offset < second.offset : firstExact
        }.map(\.element)
        return ShortsSearchPage(items: ordered, youtubeQuery: youtubeQuery, hasMore: !pending.isEmpty || canLoadPage)
    }
}

struct ShortsSearchResults: Sendable {
    let channels: [ShortsChannelResult]
    let shorts: [YouTubeShortItem]
}

struct ShortsChannelResult: Sendable, Identifiable {
    let id: String
    let title: String
}

private struct DiscoverySource {
    let id: String
    let interest: LearningInterest?
    var searchQuery: String? = nil
}

private struct DiscoverySession {
    var verified: [YouTubeShortItem]
    let channels: [DiscoverySource]
    var pendingByChannel: [String: [YouTubeShortItem]] = [:]
    var pageTokens: [String: String] = [:]
    var exhaustedChannels: Set<String> = []
    var nextChannelIndex = 0
    var inspectedIDs: Set<String>

    var hasMoreCandidates: Bool {
        channels.contains { !pendingByChannel[$0.id, default: []].isEmpty || !exhaustedChannels.contains($0.id) }
    }

    init(verified: [YouTubeShortItem], channels: [DiscoverySource]) {
        self.verified = verified
        self.channels = channels
        inspectedIDs = Set(verified.map(\.videoID))
    }

    mutating func nextChannel(canSearch: Bool, skipping failedChannels: Set<String>) -> DiscoverySource? {
        guard !channels.isEmpty else { return nil }
        for _ in channels.indices {
            let channel = channels[nextChannelIndex % channels.count]
            nextChannelIndex += 1
            if failedChannels.contains(channel.id) { continue }
            if !pendingByChannel[channel.id, default: []].isEmpty ||
                (canSearch && !exhaustedChannels.contains(channel.id)) {
                return channel
            }
        }
        return nil
    }
}

private struct DiscoveryCache: Codable {
    let savedAt: Date
    let items: [YouTubeShortItem]
}

private struct VideoDiscoveryCache: Codable {
    let items: [VideoSuggestion]
}

private struct SearchResponse: Decodable, Sendable {
    let nextPageToken: String?
    let items: [SearchResult]
}

private struct SearchResult: Decodable, Sendable {
    let id: SearchID
    let snippet: SearchSnippet
}

private struct SearchID: Decodable, Sendable {
    let videoId: String?
    let channelId: String?
}

private struct SearchSnippet: Decodable, Sendable {
    let title: String
    let channelId: String
    let channelTitle: String

    private enum CodingKeys: String, CodingKey {
        case title, channelId, channelTitle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = Self.decodeEntities(try values.decode(String.self, forKey: .title))
        channelId = try values.decode(String.self, forKey: .channelId)
        channelTitle = Self.decodeEntities(try values.decode(String.self, forKey: .channelTitle))
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

struct YouTubeSearchAPIError: LocalizedError, Sendable {
    enum Reason: String, Sendable {
        case quotaExceeded
        case rateLimited
        case invalidKey
        case restrictedKey
        case apiDisabled
        case unauthorized
        case invalidRequest
        case channelUnavailable
        case serviceUnavailable
        case unknown
    }

    let statusCode: Int
    let reason: Reason

    var blocksFurtherSearches: Bool { [400, 401, 403, 429].contains(statusCode) }

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
        let reasons = (response?.error.errors ?? []) + (response?.error.details ?? [])
        let recognized = reasons.compactMap { Self.reason(for: $0.reason ?? "") }
        if let reason = recognized.first(where: { $0 != .unauthorized && $0 != .invalidRequest }) ?? recognized.first {
            self.reason = reason
        } else {
            self.reason = switch statusCode {
            case 400: .invalidRequest
            case 401: .unauthorized
            case 429: .rateLimited
            case 500...599: .serviceUnavailable
            default: .unknown
            }
        }
    }

    var errorDescription: String? {
        switch reason {
        case .quotaExceeded: "A cota diária de buscas do YouTube foi atingida. Tente novamente mais tarde."
        case .rateLimited: "O YouTube limitou temporariamente as buscas. Aguarde um pouco e tente novamente."
        case .invalidKey: "A busca do YouTube está com um problema de configuração. Entre em contato pelo Suporte."
        case .restrictedKey: "O YouTube não autorizou esta versão do app a fazer buscas. Entre em contato pelo Suporte."
        case .apiDisabled: "A busca do YouTube está desativada para o app. Entre em contato pelo Suporte."
        case .unauthorized: "O YouTube não autorizou a busca. Tente novamente ou entre em contato pelo Suporte."
        case .invalidRequest: "O YouTube não aceitou os parâmetros desta consulta. Tente outra busca ou outro canal."
        case .channelUnavailable: "Este canal não está disponível para consulta no YouTube."
        case .serviceUnavailable: "O serviço de buscas do YouTube está temporariamente indisponível. Tente novamente em alguns minutos."
        case .unknown: "Não foi possível consultar o YouTube agora. Tente novamente ou entre em contato pelo Suporte."
        }
    }

    private static func reason(for value: String) -> Reason? {
        switch value.lowercased().replacingOccurrences(of: "_", with: "") {
        case "quotaexceeded", "dailylimitexceeded", "dailylimitexceededunreg": .quotaExceeded
        case "ratelimitexceeded", "userratelimitexceeded", "resourceexhausted": .rateLimited
        case "keyinvalid", "apikeyinvalid", "keyexpired", "apikeyexpired": .invalidKey
        case "iprefererblocked", "apikeyiosappblocked", "apikeyandroidappblocked", "apikeyhttpreferrerblocked", "apikeyipaddressblocked", "apikeyserviceblocked": .restrictedKey
        case "accessnotconfigured", "servicedisabled", "apidisabled": .apiDisabled
        case "autherror", "forbidden", "insufficientpermissions", "authorizationrequired": .unauthorized
        case "invalidfilters", "incompatibleparameters", "invalidpagetoken", "missingrequiredparameter", "unexpectedparameter", "invalidvalue", "badrequest", "invalidparameter": .invalidRequest
        case "channelnotfound", "channelclosed", "channelsuspended": .channelUnavailable
        default: nil
        }
    }

    private struct APIErrorResponse: Decodable {
        let error: Failure

        struct Failure: Decodable {
            let errors: [Detail]?
            let details: [Detail]?
        }

        struct Detail: Decodable {
            let reason: String?
        }
    }
}

private enum DiscoveryError: LocalizedError {
    case missingAPIKey
    case searchFailed
    case captionsRateLimited

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "A busca de vídeos está indisponível neste momento."
        case .searchFailed: "Não foi possível atualizar os vídeos. Tente novamente em alguns minutos."
        case .captionsRateLimited: "O YouTube limitou temporariamente a verificação de legendas. Tente de novo em alguns minutos."
        }
    }
}

extension EnglishLevel {
    /// Mesmo nível ou um vizinho: a busca manual aceita um degrau de diferença e ordena o nível exato primeiro.
    func isNear(_ other: EnglishLevel) -> Bool {
        let levels = EnglishLevel.allCases
        guard let first = levels.firstIndex(of: self), let second = levels.firstIndex(of: other) else { return false }
        return abs(first - second) <= 1
    }
}

extension LearningInterest {
    func matchesContent(title: String, transcript: YouTubeTranscript) -> Bool {
        let titleText = title.lowercased()
        let titleWords = Set(titleText.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if contentKeywords.contains(where: { keyword in
            keyword.contains(" ") ? titleText.contains(keyword) : titleWords.contains(keyword)
        }) { return true }

        let text = transcript.segments.map(\.text).joined(separator: " ").lowercased()
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let wordCounts = words.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let matchingCounts = contentKeywords.compactMap { keyword -> Int? in
            let count = keyword.contains(" ") ? text.components(separatedBy: keyword).count - 1 : wordCounts[keyword, default: 0]
            return count > 0 ? count : nil
        }
        return matchingCounts.count >= 2 && matchingCounts.reduce(0, +) >= max(3, words.count / 100)
    }

    private var contentKeywords: [String] {
        switch self {
        case .technology: ["technology", "tech", "computer", "computers", "phone", "phones", "iphone", "mac", "software", "apps", "artificial intelligence", "laptop", "internet"]
        case .business: ["business", "work", "working", "company", "companies", "money", "career", "job", "jobs", "office", "entrepreneur", "entrepreneurs", "invest", "investment"]
        case .career: ["career", "job", "jobs", "interview", "resume", "hiring", "salary", "office", "manager", "boss", "workplace", "remote work", "promotion", "linkedin", "coworker"]
        case .finance: ["finance", "financial", "money", "saving", "invest", "investing", "investment", "stock", "stocks", "market", "economy", "economic", "inflation", "bank", "banking", "budget", "wealth", "tax", "taxes"]
        case .travel: ["travel", "travelling", "traveling", "trip", "trips", "airport", "hotel", "vacation", "holiday", "tourist", "tourism", "passport", "flight", "flights"]
        case .livingAbroad: ["abroad", "living", "america", "country", "countries", "move", "moving", "immigrant", "immigration", "visa", "rent", "apartment", "culture", "american", "canadian", "college", "university", "expat"]
        case .shopping: ["shop", "shopping", "store", "buy", "buying", "price", "cost", "customer", "order", "ordering", "coffee", "cafe", "supermarket", "grocery", "clothes", "brand", "brands"]
        case .movies: ["movie", "movies", "film", "films", "cinema", "actor", "actors", "actress", "acting", "director", "netflix", "television", "tv", "series"]
        case .music: ["music", "song", "songs", "singer", "singing", "band", "album", "guitar", "piano", "concert", "musician", "artist", "pop", "rock", "grammy"]
        case .news: ["news", "headlines", "election", "government", "president", "minister", "policy", "journalist", "reporter", "reporters", "politics", "economic", "economy"]
        case .history: ["history", "historical", "ancient", "century", "war", "empire", "king", "queen", "world", "country", "geography", "map", "civilization", "museum"]
        case .lifestyle: ["life", "day", "today", "daily", "friend", "friends", "family", "home", "house", "morning", "night", "lunch", "dinner", "routine", "relationship", "relationships"]
        case .health: ["health", "healthy", "doctor", "doctors", "medical", "medicine", "hospital", "sleep", "brain", "body", "pain", "heart", "mental", "therapy", "vitamin", "symptoms"]
        case .science: ["science", "scientific", "scientist", "scientists", "physics", "chemistry", "biology", "space", "planet", "universe", "gravity", "research", "experiment", "experiments", "brain", "quantum"]
        case .engineering: ["engineering", "engineer", "engineers", "build", "building", "built", "construction", "bridge", "machine", "machines", "design", "structure", "architecture", "electricity", "energy", "factory"]
        case .cars: ["car", "cars", "drive", "driving", "engine", "motor", "truck", "trucks", "vehicle", "tire", "tires", "wheel", "highway", "tesla", "ford", "toyota", "mechanic"]
        case .aviation: ["aviation", "airplane", "airplanes", "aircraft", "pilot", "pilots", "cockpit", "runway", "airline", "airlines", "flight", "flights", "flying", "airport", "landing"]
        case .agriculture: ["farm", "farming", "farmer", "farmers", "agriculture", "crop", "crops", "tractor", "soil", "plant", "plants", "harvest", "cattle", "cow", "cows", "livestock", "ranch", "garden"]
        case .sports: ["sport", "sports", "football", "basketball", "baseball", "soccer", "tennis", "hockey", "nfl", "nba", "athlete", "athletes", "championship", "touchdown", "super bowl"]
        case .humor: ["funny", "comedy", "comedian", "comedians", "joke", "jokes", "laugh", "laughing", "hilarious", "humor", "humour", "roast", "roasted", "conan"]
        case .gaming: ["game", "games", "gaming", "gamer", "gamers", "xbox", "playstation", "nintendo", "steam", "fortnite", "minecraft", "pokemon", "zelda", "gta", "console"]
        case .fitness: ["gym", "fitness", "workout", "workouts", "muscle", "muscles", "exercise", "exercises", "training", "trainer", "weights", "weightlifting", "bench", "squat", "squats", "bodybuilding", "protein"]
        case .cooking: ["cook", "cooking", "food", "foods", "recipe", "recipes", "kitchen", "chef", "chefs", "steak", "meat", "chicken", "beef", "bake", "baking", "oven", "ingredient", "ingredients", "restaurant"]
        case .streetInterviews: ["interview", "interviews", "subway", "street", "stranger", "strangers", "opinion", "opinions", "take", "takes", "agree", "disagree", "think"]
        }
    }

    var beginnerQuery: String {
        switch self {
        case .technology: "using a computer"
        case .business: "at work"
        case .career: "job interview easy English"
        case .finance: "saving money finance simple English"
        case .travel: "at the airport hotel"
        case .livingAbroad: "living abroad in America"
        case .shopping: "shopping at the store ordering food"
        case .movies: "talking about movies"
        case .music: "talking about music songs"
        case .news: "news easy English"
        case .history: "history facts simple English"
        case .lifestyle: "daily routine"
        case .health: "at the doctor health tips"
        case .science: "science simple English"
        case .engineering: "engineering how things are built"
        case .cars: "how cars work driving"
        case .aviation: "on an airplane"
        case .agriculture: "life on a farm agriculture"
        case .sports: "talking about sports"
        case .humor: "funny conversation"
        case .gaming: "video games"
        case .fitness: "at the gym"
        case .cooking: "cooking in the kitchen"
        case .streetInterviews: "street interview easy English"
        }
    }

    var discoveryQuery: String {
        switch self {
        case .technology: "technology"
        case .business: "business interviews"
        case .career: "career job interview advice"
        case .finance: "personal finance money economy"
        case .travel: "travel experiences"
        case .livingAbroad: "living abroad cultural differences"
        case .shopping: "shopping store customer experience"
        case .movies: "movies and series"
        case .music: "music artist song interview"
        case .news: "news discussion"
        case .history: "history geography explained"
        case .lifestyle: "daily life conversations"
        case .health: "doctor health medicine explained"
        case .science: "science explained"
        case .engineering: "engineering construction explained"
        case .cars: "cars driving engine review"
        case .aviation: "aviation pilots"
        case .agriculture: "farming agriculture explained"
        case .sports: "sports interviews"
        case .humor: "comedy stories"
        case .gaming: "video games"
        case .fitness: "gym fitness"
        case .cooking: "cooking food"
        case .streetInterviews: "street interviews"
        }
    }

    var curatedChannelIDs: [String] {
        switch self {
        case .technology: ["UCc_ycus0q7DSd85ZkmEY5ig"]
        case .business: ["UCnjgxChqYYnyoqO4k_Q1d6Q"]
        case .career: ["UC0v-tlzsn0QZwJnkiaUSJVQ"]
        case .finance: ["UCK7tptUDHh-RYDsdxO1-5QQ"]
        case .travel: ["UCRUZXUjZKnKrar1LARRc1IQ"]
        case .livingAbroad: ["UCFKE7WVJfvaHW5q283SxchA"]
        case .shopping: ["UCbAwSkqJ1W_Eg7wr3cp5BUA"]
        case .movies: ["UCgRQHK8Ttr1j9xCEpCAlgbQ", "UCowq59Fx3ykFKujwDcisqPQ"]
        case .music: ["UCe9f_3dK3jK-fF5wP8_m6wA"]
        case .news: ["UCHaHD477h-FeBbVh9Sh7syA"]
        case .history: ["UCsooa4yRKGN_zEE8iknghZA"]
        case .lifestyle: ["UCAg6WsUmUZsxlJ-tOfoYR4w"]
        case .health: ["UC0QHWhjbe5fGJEPz3sVb6nw"]
        case .science: ["UCqoAEDirJPjEUFcF2FklnBA", "UCJIfeSCssxSC_Dhc5s7woww"]
        case .engineering: ["UC6107grRI4m0o2-emgoDnAA"]
        case .cars: ["UCsqjHFMB_JYTaEnf_vmTNqg"]
        case .aviation: ["UCx8Thl4BbkOwslTGXzPJx0A", "UCTbcSRduRJJTMaQhUVqywRw"]
        case .agriculture: ["UC4Tklxku1yPcRIumycLVwIQ", "UCA1y-4TJdVEcSMWN9OZfGSA"]
        case .sports: ["UCVRm2Ho8cL3lvWDyp2ayuFw"]
        case .humor: ["UCi7GJNg51C3jgmYTUwqoUXA"]
        case .gaming: ["UCT6QFE3peNry9PdO5uGj96g"]
        case .fitness: ["UCB2wtYpfbCpYDc5TeTwuqFA", "UCEjIjshJ8bvvCkGNk0pkYcA"]
        case .cooking: ["UCfE5Cz44GlZVyoaYTHJbuZw"]
        case .streetInterviews: ["UCYLf5YEC59GX69au3yb1-KQ"]
        }
    }
}
