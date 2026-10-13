import Foundation

struct ShortsRecommendationEngine: Sendable {
    func feed(
        for profile: LearningProfile,
        history: [StudiedVideo] = [],
        feedback: [String: ShortFeedback] = [:],
        preferredChannelIDs: Set<String> = [],
        preferredQueries: Set<String> = [],
        sharedScores: [String: Int] = [:],
        pinnedIDs: Set<String> = [],
        catalog: [YouTubeShortItem] = YouTubeShortItem.demoCatalog
    ) -> [YouTubeShortItem] {
        var seenIDs = Set<String>()
        // `pinnedIDs`: Shorts abertos explicitamente pela busca, que pode aceitar um nível vizinho.
        let eligible = catalog.filter { item in
            (pinnedIDs.contains(item.videoID) ||
                item.level == profile.level &&
                (!item.interests.isDisjoint(with: profile.interests) ||
                    item.channelID.map(preferredChannelIDs.contains) == true ||
                    item.searchQuery.map { preferredQueries.contains($0.lowercased()) } == true)) &&
                feedback[item.videoID]?.reaction != .hidden &&
                feedback[item.videoID]?.difficulty != .tooHard &&
                seenIDs.insert(item.videoID).inserted
        }
        var preferredInterests: [LearningInterest: Int] = [:]
        for watched in history {
            guard let item = eligible.first(where: { $0.videoID == watched.videoID }) else { continue }
            for interest in item.interests { preferredInterests[interest, default: 0] += 1 }
        }
        var ranked = eligible.sorted { first, second in
            let firstScore = score(first, for: profile, history: history, feedback: feedback, preferredInterests: preferredInterests, preferredChannelIDs: preferredChannelIDs, preferredQueries: preferredQueries) + min(sharedScores[first.videoID, default: 0], 15)
            let secondScore = score(second, for: profile, history: history, feedback: feedback, preferredInterests: preferredInterests, preferredChannelIDs: preferredChannelIDs, preferredQueries: preferredQueries) + min(sharedScores[second.videoID, default: 0], 15)
            return firstScore == secondScore ? first.videoID < second.videoID : firstScore > secondScore
        }
        var result: [YouTubeShortItem] = []
        var topicCounts: [LearningInterest: Int] = [:]
        while !ranked.isEmpty {
            let leastCount = ranked.flatMap { $0.interests.intersection(profile.interests) }
                .map { topicCounts[$0, default: 0] }.min() ?? 0
            let balancedIndices = ranked.indices.filter { index in
                let item = ranked[index]
                let topics = item.interests.intersection(profile.interests)
                if topics.isEmpty {
                    return pinnedIDs.contains(item.videoID) ||
                        item.channelID.map(preferredChannelIDs.contains) == true ||
                        item.searchQuery.map { preferredQueries.contains($0.lowercased()) } == true
                }
                return topics.contains { topicCounts[$0, default: 0] == leastCount }
            }
            let index = balancedIndices.first { index in
                let candidate = ranked[index]
                guard let previous = result.last?.creator, let creator = candidate.creator else { return true }
                return creator.localizedCaseInsensitiveCompare(previous) != .orderedSame
            } ?? balancedIndices.first ?? 0
            let item = ranked.remove(at: index)
            result.append(item)
            for interest in item.interests.intersection(profile.interests) { topicCounts[interest, default: 0] += 1 }
        }
        return result
    }

    private func score(
        _ item: YouTubeShortItem,
        for profile: LearningProfile,
        history: [StudiedVideo],
        feedback: [String: ShortFeedback],
        preferredInterests: [LearningInterest: Int],
        preferredChannelIDs: Set<String>,
        preferredQueries: Set<String>
    ) -> Int {
        let interestScore = item.interests.intersection(profile.interests).count * 5
        let historyScore = item.interests.reduce(0) { $0 + min(preferredInterests[$1, default: 0], 3) }
        let watchedPenalty = history.contains { $0.videoID == item.videoID } ? 3 : 0
        let liked = feedback.values.filter { $0.reaction == .liked }
        let hidden = feedback.values.filter { $0.reaction == .hidden }
        let likedTopics = liked.reduce(0) { $0 + $1.interests.intersection(item.interests).count }
        let hiddenTopics = hidden.reduce(0) { $0 + $1.interests.intersection(item.interests).count }
        let creator = item.creator?.lowercased()
        let creatorLikes = liked.filter { $0.creator?.lowercased() == creator && creator != nil }.count
        let creatorHides = hidden.filter { $0.creator?.lowercased() == creator && creator != nil }.count
        let likedItemBonus = feedback[item.videoID]?.reaction == .liked ? 2 : 0
        let difficultyPenalty = feedback[item.videoID]?.difficulty == .tooEasy ? 8 : 0
        let channelScore = item.channelID.map(preferredChannelIDs.contains) == true ? 18 : 0
        let searchScore = item.searchQuery.map({ preferredQueries.contains($0.lowercased()) }) == true ? 12 : 0
        return interestScore + historyScore + channelScore + searchScore + min(likedTopics, 5) * 3 + min(creatorLikes, 3) * 6
            - min(hiddenTopics, 3) * 2 - min(creatorHides, 3) * 4 - watchedPenalty + likedItemBonus - difficultyPenalty
    }
}
