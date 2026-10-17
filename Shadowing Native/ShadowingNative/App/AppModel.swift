import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var profile: LearningProfile
    var hasCompletedOnboarding: Bool
    var selectedTab: AppTab = .today
    /// O perfil abre por cima da aba atual (ícone no topo), em vez de ocupar uma aba.
    var isProfilePresented = false
    private(set) var profileUpdatedAt: Date

    private let defaults: UserDefaults
    private let profileKey = "shadowing.native.profile"
    private let onboardingKey = "shadowing.native.onboarding.complete"
    private let profileUpdatedKey = "shadowing.native.profile.updated-at"
    private var activeAccountID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: onboardingKey)
        profileUpdatedAt = defaults.object(forKey: profileUpdatedKey) as? Date ?? .distantPast

        if let data = defaults.data(forKey: profileKey),
           let savedProfile = try? JSONDecoder().decode(LearningProfile.self, from: data) {
            profile = savedProfile
        } else {
            profile = .starter
        }
    }

    func recommendations(
        history: [StudiedVideo],
        feedback: [String: ShortFeedback] = [:],
        catalog: [VideoSuggestion] = VideoSuggestion.catalog
    ) -> [VideoSuggestion] {
        var ranked: [(suggestion: VideoSuggestion, score: Int)] = []

        let catalogByID = Dictionary(catalog.map { ($0.videoID, $0) }, uniquingKeysWith: { first, _ in first })
        var preferredInterests: [LearningInterest: Int] = [:]
        var preferredCreators: [String: Int] = [:]
        for video in history.prefix(30) {
            if let catalogItem = catalogByID[video.videoID] {
                for interest in catalogItem.interests {
                    preferredInterests[interest, default: 0] += 1
                }
            }
            preferredCreators[video.channel.lowercased(), default: 0] += 1
        }

        for suggestion in catalogByID.values
        where suggestion.level == profile.level && !suggestion.interests.isDisjoint(with: profile.interests)
            && feedback[suggestion.videoID]?.reaction != .hidden
            && feedback[suggestion.videoID]?.difficulty != .tooHard {
            let matchingInterests = suggestion.interests.intersection(profile.interests).count
            let matchingGoals = suggestion.goals.intersection(profile.goals).count
            let levelBonus = suggestion.level == profile.level ? 3 : 0
            let interestHistoryScore = suggestion.interests.reduce(0) { $0 + min(preferredInterests[$1, default: 0], 3) }
            let creatorScore = min(preferredCreators[suggestion.creator.lowercased(), default: 0], 3) * 2
            let alreadyStudiedPenalty = history.contains { $0.videoID == suggestion.videoID } ? 8 : 0
            let shortFeedbackScore = feedback.values.reduce(0) { score, item in
                let matchingTopics = item.interests.intersection(suggestion.interests).count
                let sameCreator = item.creator?.localizedCaseInsensitiveCompare(suggestion.creator) == .orderedSame
                switch item.reaction {
                case .liked: return score + matchingTopics * 2 + (sameCreator ? 4 : 0)
                case .hidden: return score - matchingTopics - (sameCreator ? 3 : 0)
                case .neutral: return score
                }
            }
            let score = (matchingInterests * 4) + (matchingGoals * 2) + levelBonus
                + interestHistoryScore + creatorScore + shortFeedbackScore - alreadyStudiedPenalty
            ranked.append((suggestion, score))
        }

        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                let firstDuration = lhs.suggestion.durationMinutes ?? Int.max
                let secondDuration = rhs.suggestion.durationMinutes ?? Int.max
                return firstDuration == secondDuration ? lhs.suggestion.videoID < rhs.suggestion.videoID : firstDuration < secondDuration
            }
            return lhs.score > rhs.score
        }

        var recommendations: [VideoSuggestion] = []
        var topicCounts: [LearningInterest: Int] = [:]
        while !ranked.isEmpty {
            let leastCount = ranked.flatMap { $0.suggestion.interests.intersection(profile.interests) }
                .map { topicCounts[$0, default: 0] }.min() ?? 0
            let index = ranked.firstIndex { candidate in
                candidate.suggestion.interests.intersection(profile.interests).contains { topicCounts[$0, default: 0] == leastCount }
            } ?? 0
            let suggestion = ranked.remove(at: index).suggestion
            recommendations.append(suggestion)
            for interest in suggestion.interests.intersection(profile.interests) { topicCounts[interest, default: 0] += 1 }
        }
        return recommendations
    }

    func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        profileUpdatedAt = Date()
        defaults.set(data, forKey: storageKey(profileKey, accountID: activeAccountID))
        defaults.set(profileUpdatedAt, forKey: storageKey(profileUpdatedKey, accountID: activeAccountID))
    }

    func completeOnboarding() {
        saveProfile()
        hasCompletedOnboarding = true
        defaults.set(true, forKey: storageKey(onboardingKey, accountID: activeAccountID))
    }

    func resetOnboarding() {
        profile = .starter
        hasCompletedOnboarding = false
        defaults.removeObject(forKey: storageKey(profileKey, accountID: activeAccountID))
        defaults.removeObject(forKey: storageKey(onboardingKey, accountID: activeAccountID))
        profileUpdatedAt = Date()
        defaults.set(profileUpdatedAt, forKey: storageKey(profileUpdatedKey, accountID: activeAccountID))
    }

    func activateAccount(_ accountID: String?) {
        guard activeAccountID != accountID else { return }
        let nextProfileKey = storageKey(profileKey, accountID: accountID)
        let nextOnboardingKey = storageKey(onboardingKey, accountID: accountID)
        let nextUpdatedKey = storageKey(profileUpdatedKey, accountID: accountID)

        if activeAccountID == nil, accountID != nil, defaults.object(forKey: nextProfileKey) == nil {
            if let guestProfile = defaults.data(forKey: profileKey) {
                defaults.set(guestProfile, forKey: nextProfileKey)
            }
            defaults.set(defaults.bool(forKey: onboardingKey), forKey: nextOnboardingKey)
            if let guestUpdated = defaults.object(forKey: profileUpdatedKey) {
                defaults.set(guestUpdated, forKey: nextUpdatedKey)
            }
            defaults.removeObject(forKey: profileKey)
            defaults.removeObject(forKey: onboardingKey)
            defaults.removeObject(forKey: profileUpdatedKey)
        }

        activeAccountID = accountID
        if let data = defaults.data(forKey: nextProfileKey),
           let stored = try? JSONDecoder().decode(LearningProfile.self, from: data) {
            profile = stored
        } else {
            profile = .starter
        }
        hasCompletedOnboarding = defaults.bool(forKey: nextOnboardingKey)
        profileUpdatedAt = defaults.object(forKey: nextUpdatedKey) as? Date ?? .distantPast
    }

    func deleteAccountData(for accountID: String) {
        defaults.removeObject(forKey: storageKey(profileKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(onboardingKey, accountID: accountID))
        defaults.removeObject(forKey: storageKey(profileUpdatedKey, accountID: accountID))
        if activeAccountID == accountID {
            activeAccountID = nil
            profile = .starter
            hasCompletedOnboarding = false
            profileUpdatedAt = .distantPast
        }
    }

    func merge(profile remoteProfile: LearningProfile, completedOnboarding: Bool, updatedAt: Date) {
        if updatedAt > profileUpdatedAt {
            profile = remoteProfile
            hasCompletedOnboarding = completedOnboarding
            profileUpdatedAt = updatedAt
            if let data = try? JSONEncoder().encode(profile) {
                defaults.set(data, forKey: storageKey(profileKey, accountID: activeAccountID))
            }
            defaults.set(completedOnboarding, forKey: storageKey(onboardingKey, accountID: activeAccountID))
            defaults.set(updatedAt, forKey: storageKey(profileUpdatedKey, accountID: activeAccountID))
        }
    }

    private func storageKey(_ base: String, accountID: String?) -> String {
        accountID.map { "\(base).\($0)" } ?? base
    }
}

enum AppTab: Hashable {
    case today
    case explore
    case shorts
    case music
    case progress
}
