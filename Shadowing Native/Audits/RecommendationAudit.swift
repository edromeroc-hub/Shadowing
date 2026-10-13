import Foundation

@main
struct RecommendationAudit {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--transcript") {
            let transcript = try await YouTubeTranscriptService.shared.fetchTranscript(videoID: CommandLine.arguments[2])
            let words = transcript.segments.flatMap { $0.text.split(whereSeparator: { !$0.isLetter && $0 != "'" }) }
            print("\(transcript.title) segments=\(transcript.segments.count) words=\(words.count) level=\(ShortDifficultyEstimator.estimate(transcript: transcript)?.rawValue ?? "nil")")
            for segment in transcript.segments { print("\(segment.start)-\(segment.end) \(segment.text)") }
            return
        }
        if CommandLine.arguments.contains("--live") {
            let plistPath = CommandLine.arguments[2]
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: plistPath)), format: nil) as! [String: Any]
            let key = info["YouTubeDataAPIKey"] as? String
            if CommandLine.arguments.contains("--channels") {
                var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
                components.queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "id", value: LearningInterest.allCases.flatMap(\.curatedChannelIDs).joined(separator: ",")), URLQueryItem(name: "key", value: key)]
                var request = URLRequest(url: components.url!)
                request.setValue(info["CFBundleIdentifier"] as? String, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
                let (data, response) = try await URLSession.shared.data(for: request)
                print("CHANNEL status=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = object["items"] as? [[String: Any]] {
                    for item in items { print("CHANNEL \(item["id"] ?? "") | \((item["snippet"] as? [String: Any])?["title"] ?? "")") }
                }
                components.queryItems = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "forHandle", value: "SubwayTakes"), URLQueryItem(name: "key", value: key)]
                request.url = components.url!
                let (subwayData, _) = try await URLSession.shared.data(for: request)
                if let object = try JSONSerialization.jsonObject(with: subwayData) as? [String: Any], let items = object["items"] as? [[String: Any]] {
                    for item in items { print("SUBWAY \(item["id"] ?? "") | \((item["snippet"] as? [String: Any])?["title"] ?? "")") }
                }
                return
            }
            let suite = "shadowing.recommendation-audit.live"
            let defaults = UserDefaults(suiteName: suite)!
            if CommandLine.arguments.contains("--fresh") { defaults.removePersistentDomain(forName: suite) }
            let service = ShortsDiscoveryService(apiKey: key, defaults: defaults)
            let interest = LearningInterest(rawValue: CommandLine.arguments[3])!
            let level = EnglishLevel(rawValue: CommandLine.arguments[4])!
            var profile = LearningProfile.starter
            profile.level = level
            profile.interests = [interest]
            let started = Date()
            do {
                if CommandLine.arguments.contains("--videos") {
                    let videos = try await service.discoverVideos(for: profile, limit: 3)
                    for video in videos { print("VIDEO \(video.videoID) | \(video.creator) | \(video.level.rawValue) | \(video.title)") }
                    print("RESULT videos=\(videos.count) elapsed=\(Int(Date().timeIntervalSince(started)))s")
                } else {
                    var seen = Set<String>()
                    let batches = CommandLine.arguments.contains("--next") ? 2 : 1
                    for batch in 0..<batches {
                        let items = try await service.discover(for: profile, feedback: [:], excluding: seen, limit: 3)
                        for item in items {
                            print("SHORT batch=\(batch) \(item.videoID) | \(item.creator ?? "") | \(item.level.rawValue) | \(item.title)")
                            precondition(item.level == level && item.interests.contains(interest))
                            precondition(seen.insert(item.videoID).inserted)
                        }
                        print("RESULT batch=\(batch) shorts=\(items.count) elapsed=\(Int(Date().timeIntervalSince(started)))s")
                    }
                }
            } catch { print("FAIL \(error.localizedDescription) elapsed=\(Int(Date().timeIntervalSince(started)))s") }
            return
        }
        let defaults = UserDefaults(suiteName: "shadowing.recommendation-audit.unit")!
        let model = AppModel(defaults: defaults)
        var catalog: [YouTubeShortItem] = []
        for level in EnglishLevel.allCases {
            for interest in LearningInterest.allCases {
                for number in 0..<3 {
                    catalog.append(YouTubeShortItem(videoID: "\(level.rawValue)-\(interest.rawValue)-\(number)", title: "Fixture", topic: interest.title, hook: "", level: level, interests: [interest], creator: "Creator \(number)"))
                }
            }
        }
        var checks = 0
        for level in EnglishLevel.allCases {
            for interest in LearningInterest.allCases {
                var profile = LearningProfile.starter
                profile.level = level
                profile.interests = [interest]
                let result = ShortsRecommendationEngine().feed(for: profile, catalog: catalog)
                precondition(result.count == 3 && result.allSatisfy { $0.level == level && $0.interests == [interest] })
                let hidden = result[0]
                let tooHard = result[1]
                let feedback = [
                    hidden.videoID: ShortFeedback(videoID: hidden.videoID, creator: hidden.creator, interests: hidden.interests, reaction: .hidden, updatedAt: Date()),
                    tooHard.videoID: ShortFeedback(videoID: tooHard.videoID, creator: tooHard.creator, interests: tooHard.interests, reaction: .neutral, updatedAt: Date(), difficulty: .tooHard)
                ]
                precondition(ShortsRecommendationEngine().feed(for: profile, feedback: feedback, catalog: catalog).count == 1)
                model.profile = profile
                let videos = catalog.map { VideoSuggestion(videoID: $0.videoID, title: $0.title, creator: $0.creator!, source: .youtube, durationMinutes: 5, level: $0.level, interests: $0.interests, goals: [.listening], accent: .blue, hook: "") }
                let recommendations = model.recommendations(history: [], catalog: videos)
                precondition(recommendations.count == 3 && recommendations.allSatisfy { $0.level == level && $0.interests == [interest] })
                checks += 3
            }
        }
        print("PASS \(checks) topic/level/feedback checks across 42 profiles")
        let duplicates = catalog + catalog
        var mixedProfile = LearningProfile.starter
        mixedProfile.interests = [.fitness, .cooking, .gaming]
        let mixed = ShortsRecommendationEngine().feed(for: mixedProfile, catalog: duplicates)
        precondition(Set(mixed.map(\.videoID)).count == mixed.count)
        precondition(Set(mixed.prefix(3).flatMap(\.interests)).count == 3)
        let likedItem = catalog.first { $0.level == .intermediate && $0.interests == [.fitness] }!
        let likes = [likedItem.videoID: ShortFeedback(videoID: likedItem.videoID, creator: likedItem.creator, interests: likedItem.interests, reaction: .liked, updatedAt: Date())]
        let personalized = ShortsRecommendationEngine().feed(for: mixedProfile, feedback: likes, catalog: catalog)
        precondition(personalized.first?.videoID == likedItem.videoID)
        precondition(Set(personalized.prefix(3).flatMap(\.interests)).count == 3)
        let slow = fixtureTranscript(id: "slow")
        precondition(ShortDifficultyEstimator.estimate(transcript: slow) == .beginner)
        precondition(ShortDifficultyEstimator.estimate(transcript: slow, titleHint: "Everyday English B1 Slow English") == .intermediate)
        precondition(ShortDifficultyEstimator.estimate(transcript: slow, titleHint: "C1 Advanced English") == .advanced)
        precondition(!LearningInterest.fitness.matchesContent(title: "Cooking chicken", transcript: slow))
        let incidental = YouTubeTranscript(videoID: "incidental", title: "Job interview", channel: "Fixture", languageCode: "en", source: "fixture", segments: slow.segments + [YouTubeTranscriptSegment(text: "I can use a computer.", start: 40, end: 44)])
        precondition(!LearningInterest.technology.matchesContent(title: incidental.title, transcript: incidental))
        let technology = YouTubeTranscript(videoID: "technology", title: "A conversation", channel: "Fixture", languageCode: "en", source: "fixture", segments: [YouTubeTranscriptSegment(text: "My computer runs this software. My phone uses another app.", start: 0, end: 12)])
        precondition(LearningInterest.technology.matchesContent(title: technology.title, transcript: technology))
        var segments = slow.segments
        segments[0] = YouTubeTranscriptSegment(text: "Who has the stronger grip David with one hand or Patty with two hands come on go", start: 0, end: 5)
        let burst = YouTubeTranscript(videoID: "burst", title: "", channel: "", languageCode: "en", source: "fixture", segments: segments)
        precondition(ShortDifficultyEstimator.estimate(transcript: burst) != .beginner)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let networkDefaults = UserDefaults(suiteName: "shadowing.recommendation-audit.mock-network")!
        networkDefaults.removePersistentDomain(forName: "shadowing.recommendation-audit.mock-network")
        let service = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: networkDefaults, transcriptLoader: { fixtureTranscript(id: $0) })
        var profile = LearningProfile.starter
        profile.level = .beginner
        profile.interests = [.fitness]
        let firstBatch = try await service.discover(for: profile, feedback: [:])
        precondition(firstBatch.count == 3)
        precondition(firstBatch.allSatisfy { $0.title.contains("' & \"practice\"") && $0.creator == "Fixture & Channel" })
        FixtureURLProtocol.requests.reset()
        let searchResults = try await service.searchShortsAndChannels(query: "fitness", level: .beginner)
        precondition(searchResults.channels.first?.id == "fixture-channel")
        precondition(!searchResults.shorts.isEmpty && searchResults.shorts.allSatisfy { $0.level == .beginner && $0.searchQuery == "fitness" })
        let channelShorts = try await service.searchChannelShorts(channel: searchResults.channels[0], query: "fitness", level: .beginner)
        precondition(channelShorts.count == 6)
        precondition(channelShorts.allSatisfy { $0.channelID == "fixture-channel" && $0.searchQuery == "fitness" })
        precondition(ShortsRecommendationEngine().feed(for: profile, preferredQueries: ["fitness"], catalog: channelShorts).count == 6)
        let searchRequestCount = FixtureURLProtocol.requests.count
        _ = try await service.searchShortsAndChannels(query: "fitness", level: .beginner)
        precondition(FixtureURLProtocol.requests.count == searchRequestCount)
        let personalChannel = ShortChannelPreference(id: "fixture-channel", title: "Fixture Channel", isFollowed: true, updatedAt: Date())
        let personalSearch = ShortSearchPreference(query: "fitness", count: 1, updatedAt: Date())
        let personalizedBatch = try await service.discoverBatch(for: profile, feedback: [:], channels: [personalChannel], searches: [personalSearch], limit: 1)
        precondition(personalizedBatch.items.count == 1 && personalizedBatch.items[0].channelID == personalChannel.id)
        let unrelated = YouTubeShortItem(videoID: "followed", title: "Followed", topic: "Seu canal", hook: "", level: .beginner, interests: [], creator: "Fixture Channel", channelID: personalChannel.id)
        precondition(ShortsRecommendationEngine().feed(for: profile, preferredChannelIDs: [personalChannel.id], catalog: [unrelated]).map(\.videoID) == [unrelated.videoID])
        let ordinary = YouTubeShortItem(videoID: "ordinary", title: "Ordinary", topic: "Fitness", hook: "", level: .beginner, interests: [.fitness], creator: "Other", channelID: "other-channel")
        let mixedRecommendations = ShortsRecommendationEngine().feed(for: profile, preferredChannelIDs: [personalChannel.id], catalog: [unrelated, ordinary])
        precondition(mixedRecommendations.first?.videoID == unrelated.videoID)
        let fastDefaults = UserDefaults(suiteName: "shadowing.recommendation-audit.first-short")!
        fastDefaults.removePersistentDomain(forName: "shadowing.recommendation-audit.first-short")
        let fastService = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: fastDefaults, transcriptLoader: { id in
            try await Task.sleep(for: .milliseconds(id == "fixture-0" ? 20 : 1500))
            return fixtureTranscript(id: id)
        })
        let firstStarted = Date()
        let firstReady = try await fastService.discoverBatch(for: profile, feedback: [:], limit: 1)
        precondition(firstReady.items.count == 1 && firstReady.items[0].videoID == "fixture-0")
        precondition(Date().timeIntervalSince(firstStarted) < 1)
        let remaining = try await fastService.discoverBatch(for: profile, feedback: [:], excluding: Set(firstReady.items.map(\.videoID)), limit: 3)
        precondition(remaining.items.count == 3 && !remaining.items.contains { $0.videoID == firstReady.items[0].videoID })
        let secondBatch = try await service.discover(for: profile, feedback: [:], excluding: Set(firstBatch.map(\.videoID)))
        precondition(secondBatch.count == 3 && Set(firstBatch.map(\.videoID)).isDisjoint(with: secondBatch.map(\.videoID)))
        let emptyLimit = try await service.discover(for: profile, feedback: [:], limit: 0)
        precondition(emptyLimit.isEmpty)
        let videos = try await service.discoverVideos(for: profile, limit: 3)
        precondition(videos.count == 2 && videos.allSatisfy { $0.level == .beginner && $0.interests == [.fitness] })
        let hiddenID = firstBatch[0].videoID
        let hiddenFeedback = [hiddenID: ShortFeedback(videoID: hiddenID, creator: nil, interests: [.fitness], reaction: .hidden, updatedAt: Date())]
        let afterHidden = try await service.discover(for: profile, feedback: hiddenFeedback)
        precondition(afterHidden.allSatisfy { $0.videoID != hiddenID })
        let failingDefaults = UserDefaults(suiteName: "shadowing.recommendation-audit.failure")!
        failingDefaults.removePersistentDomain(forName: "shadowing.recommendation-audit.failure")
        let recovering = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: failingDefaults, transcriptLoader: { id in
            var transcript = fixtureTranscript(id: id)
            transcript = YouTubeTranscript(videoID: id, title: "", channel: "", languageCode: "en", source: "fixture", segments: transcript.segments.map { YouTubeTranscriptSegment(text: $0.text, start: $0.start * 0.8, end: $0.end * 0.8) })
            return transcript
        })
        profile.level = .intermediate
        let recovered = try await recovering.discover(for: profile, feedback: [:])
        precondition(!recovered.isEmpty)
        for level in EnglishLevel.allCases {
            for interest in LearningInterest.allCases {
                let suite = "shadowing.recommendation-audit.pipeline.\(level.rawValue).\(interest.rawValue)"
                let isolatedDefaults = UserDefaults(suiteName: suite)!
                isolatedDefaults.removePersistentDomain(forName: suite)
                let factor = level == .beginner ? 1.0 : (level == .intermediate ? 0.8 : 0.45)
                let pipeline = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: isolatedDefaults, transcriptLoader: { id in
                    let reference = fixtureTranscript(id: id)
                    return YouTubeTranscript(videoID: id, title: "", channel: "", languageCode: "en", source: "fixture", segments: reference.segments.map { YouTubeTranscriptSegment(text: $0.text, start: $0.start * factor, end: $0.end * factor) })
                })
                var testProfile = LearningProfile.starter
                testProfile.level = level
                testProfile.interests = [interest]
                let batch = try await pipeline.discoverBatch(for: testProfile, feedback: [:])
                precondition(batch.items.count == 3 && batch.items.allSatisfy { $0.level == level && $0.interests == [interest] })
                let videoBatch = try await pipeline.discoverVideos(for: testProfile, limit: 3)
                precondition(videoBatch.count == 2 && videoBatch.allSatisfy { $0.level == level && $0.interests == [interest] })
            }
        }

        let accountSuite = "shadowing.recommendation-audit.accounts"
        let accountDefaults = UserDefaults(suiteName: accountSuite)!
        accountDefaults.removePersistentDomain(forName: accountSuite)
        let accountModel = AppModel(defaults: accountDefaults)
        let accountProgress = StudyProgressStore(defaults: accountDefaults)
        accountModel.activateAccount("student-a")
        accountProgress.activateAccount("student-a")
        accountModel.profile = mixedProfile
        accountModel.completeOnboarding()
        accountProgress.react(to: likedItem, as: .liked)
        accountProgress.setShortChannel("fixture-channel", title: "Fixture Channel", followed: true)
        accountProgress.rememberShortSearch("fitness")
        accountModel.activateAccount("student-b")
        accountProgress.activateAccount("student-b")
        precondition(accountProgress.shortFeedback.isEmpty && accountProgress.followedShortChannels.isEmpty && accountProgress.recentShortSearches.isEmpty && !accountModel.hasCompletedOnboarding)
        accountModel.profile.level = .beginner
        accountModel.profile.interests = [.aviation]
        accountModel.completeOnboarding()
        accountModel.activateAccount("student-a")
        accountProgress.activateAccount("student-a")
        precondition(accountModel.profile == mixedProfile)
        precondition(accountProgress.shortFeedback[likedItem.videoID]?.reaction == .liked)
        precondition(accountProgress.followedShortChannels.map(\.id) == ["fixture-channel"])
        precondition(accountProgress.recentShortSearches.map(\.query) == ["fitness"])
        accountProgress.react(to: likedItem, as: .hidden)
        precondition(accountProgress.shortFeedback[likedItem.videoID]?.reaction == .hidden)
        accountProgress.react(to: likedItem, as: .hidden)
        precondition(accountProgress.shortFeedback[likedItem.videoID]?.reaction == .neutral)
        let restoredProgress = StudyProgressStore(defaults: accountDefaults)
        restoredProgress.activateAccount("student-a")
        precondition(restoredProgress.shortFeedback[likedItem.videoID]?.reaction == .neutral)
        precondition(restoredProgress.followedShortChannels.map(\.id) == ["fixture-channel"])
        let snapshotData = try JSONEncoder().encode(restoredProgress.snapshot)
        let snapshot = try JSONDecoder().decode(StudyProgressSnapshot.self, from: snapshotData)
        precondition(snapshot.shortChannels.count == 1 && snapshot.shortSearches.count == 1)
        var legacySnapshot = try JSONSerialization.jsonObject(with: snapshotData) as! [String: Any]
        legacySnapshot.removeValue(forKey: "shortChannels")
        legacySnapshot.removeValue(forKey: "shortSearches")
        let migrated = try JSONDecoder().decode(StudyProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: legacySnapshot))
        precondition(migrated.shortChannels.isEmpty && migrated.shortSearches.isEmpty)

        let coalescingSuite = "shadowing.recommendation-audit.coalescing"
        let coalescingDefaults = UserDefaults(suiteName: coalescingSuite)!
        coalescingDefaults.removePersistentDomain(forName: coalescingSuite)
        let coalescing = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: coalescingDefaults, transcriptLoader: { id in
            try await Task.sleep(for: .milliseconds(50))
            return fixtureTranscript(id: id)
        })
        profile.level = .beginner
        let coalescingProfile = profile
        FixtureURLProtocol.requests.reset()
        async let todayResults = coalescing.discoverVideos(for: coalescingProfile, limit: 3, refresh: true)
        async let exploreResults = coalescing.discoverVideos(for: coalescingProfile, limit: 3, refresh: true)
        let concurrent = try await (todayResults, exploreResults)
        precondition(concurrent.0.map(\.videoID) == concurrent.1.map(\.videoID))
        precondition(FixtureURLProtocol.requests.count == 1)
        let cancelled = Task { try await coalescing.discoverVideos(for: coalescingProfile, limit: 3, refresh: true) }
        try await Task.sleep(for: .milliseconds(10))
        let joined = Task { try await coalescing.discoverVideos(for: coalescingProfile, limit: 3, refresh: true) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled screen accepted stale results")
        } catch is CancellationError {}
        let joinedResults = try await joined.value
        precondition(joinedResults.count == 2)

        let rejectedSuite = "shadowing.recommendation-audit.rejected"
        let rejectedDefaults = UserDefaults(suiteName: rejectedSuite)!
        rejectedDefaults.removePersistentDomain(forName: rejectedSuite)
        let rejected = ShortsDiscoveryService(apiKey: "fixture", session: session, defaults: rejectedDefaults, transcriptLoader: { id in
            let original = fixtureTranscript(id: id)
            return YouTubeTranscript(videoID: id, title: original.title, channel: original.channel, languageCode: "es", source: "fixture", segments: original.segments)
        })
        var rejectedProfile = profile
        rejectedProfile.interests = [.cooking]
        let rejectedBatch = try await rejected.discoverBatch(for: rejectedProfile, feedback: [:])
        precondition(rejectedBatch.items.isEmpty && !rejectedBatch.hasMoreCandidates)
        let rejectedVideos = try await rejected.discoverVideos(for: rejectedProfile)
        precondition(rejectedVideos.isEmpty)
        let deniedConfiguration = URLSessionConfiguration.ephemeral
        deniedConfiguration.protocolClasses = [DeniedURLProtocol.self]
        let deniedDefaults = UserDefaults(suiteName: "shadowing.recommendation-audit.denied")!
        deniedDefaults.removePersistentDomain(forName: "shadowing.recommendation-audit.denied")
        let deniedService = ShortsDiscoveryService(
            apiKey: "fixture",
            session: URLSession(configuration: deniedConfiguration),
            defaults: deniedDefaults,
            transcriptLoader: { fixtureTranscript(id: $0) }
        )
        DeniedURLProtocol.requests.reset()
        do {
            _ = try await deniedService.discoverBatch(for: profile, feedback: [:], limit: 1)
            preconditionFailure("API authorization failure was silently retried")
        } catch {
            precondition(DeniedURLProtocol.requests.count == 1)
        }
        let missingKey = ShortsDiscoveryService(apiKey: nil, session: session, defaults: UserDefaults(suiteName: "shadowing.recommendation-audit.missing-key")!)
        do {
            _ = try await missingKey.discoverBatch(for: profile, feedback: [:])
            preconditionFailure("Missing key silently accepted")
        } catch {}
        print("PASS account isolation, feedback persistence and undo, request coalescing, cancelled waiter, non-English rejection and missing API key")

        print("PASS discovery pipeline for all 42 profiles: English captions, topic, level, video and Short results")
        print("PASS duplicate IDs, multi-topic balance, personal likes, fast speech bursts, prepared batches, exclusions, hidden feedback, video discovery and partial search failure")
        precondition(ShortsDiscoveryService.youtubeQuery(for: "viagem") == "travel")
        precondition(ShortsDiscoveryService.youtubeQuery(for: "Receitas de comida") == "recipes food")
        precondition(ShortsDiscoveryService.youtubeQuery(for: "entrevista de rua") == "street interview")
        precondition(ShortsDiscoveryService.youtubeQuery(for: "gordon ramsay #shorts") == "gordon ramsay")
        precondition(ShortsDiscoveryService.youtubeQuery(for: "Tom Holland") == "Tom Holland")
        precondition(EnglishLevel.beginner.isNear(.intermediate) && !EnglishLevel.beginner.isNear(.advanced))
        let searchPage = try await service.searchShorts(query: "fitness", level: .beginner)
        precondition(!searchPage.items.isEmpty && searchPage.items.allSatisfy { $0.level.isNear(.beginner) })
        let pinnedShort = YouTubeShortItem(videoID: "pinned", title: "Picked in search", topic: "Sua busca", hook: "", level: .intermediate, interests: [])
        precondition(ShortsRecommendationEngine().feed(for: profile, catalog: [pinnedShort]).isEmpty)
        precondition(ShortsRecommendationEngine().feed(for: profile, pinnedIDs: ["pinned"], catalog: [pinnedShort]).map(\.videoID) == ["pinned"])
        print("PASS search query translation, adjacent-level search results and pinned search picks")
    }

    static func fixtureTranscript(id: String) -> YouTubeTranscript {
        YouTubeTranscript(videoID: id, title: "Fixture", channel: "Fixture", languageCode: "en", source: "fixture", segments: (0..<10).map { index in
            YouTubeTranscriptSegment(text: "You can take your time now.", start: Double(index) * 4, end: Double(index + 1) * 4)
        })
    }
}

final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static let requests = RequestCounter()

    override func startLoading() {
        Self.requests.increment()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let type = components.queryItems?.first { $0.name == "type" }?.value
        let channel = components.queryItems?.first { $0.name == "channelId" }?.value
        let query = components.queryItems?.first { $0.name == "q" }?.value ?? ""
        let topicText = LearningInterest.allCases.first { $0.curatedChannelIDs.contains(channel ?? "") }?.discoveryQuery ?? query
        let status = channel == LearningInterest.fitness.curatedChannelIDs.first ? 500 : 200
        let items: [[String: Any]] = type == "channel"
            ? [["id": ["channelId": "fixture-channel"], "snippet": ["title": "Fixture Channel", "channelId": "fixture-channel", "channelTitle": "Fixture Channel"]]]
            : (0..<6).map { index in
                ["id": ["videoId": "fixture-\(index)"], "snippet": ["title": "\(topicText) \(index) &#39; &amp; &quot;practice&quot;", "channelId": channel ?? "fixture-channel", "channelTitle": "Fixture &amp; Channel"]]
            }
        let data = try! JSONSerialization.data(withJSONObject: ["items": items])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class DeniedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static let requests = RequestCounter()

    override func startLoading() {
        Self.requests.increment()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        value = 0
    }
}
