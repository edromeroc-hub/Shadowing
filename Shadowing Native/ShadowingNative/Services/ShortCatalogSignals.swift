import FirebaseAuth
import FirebaseFirestore
import Foundation

enum ShortCatalogSignals {
    @MainActor
    static func recordView(item: YouTubeShortItem, profile: LearningProfile) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let defaults = UserDefaults.standard
        let key = "shadowing.shared-views.\(uid)"
        let day = currentDay()
        let viewed = defaults.string(forKey: "\(key).day") == day
            ? defaults.stringArray(forKey: "\(key).ids") ?? [] : []
        guard !viewed.contains(item.videoID),
              await record(item: item, profile: profile, reaction: nil) else { return }
        defaults.set(day, forKey: "\(key).day")
        defaults.set(Array((viewed + [item.videoID]).suffix(500)), forKey: "\(key).ids")
    }

    @MainActor
    @discardableResult
    static func record(item: YouTubeShortItem, profile: LearningProfile, reaction: ShortReaction?) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        var fields: [String: Any] = [
            "videoID": item.videoID,
            "level": profile.level.rawValue,
            "interests": profile.interests.map(\.rawValue),
            "viewed": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let reaction { fields["reaction"] = reaction.rawValue }
        do {
            try await Firestore.firestore().collection("shortSignals").document(uid)
                .collection("votes").document(item.videoID).setData(fields, merge: true)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func suggest(_ videoIDs: [String]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let validIDs = Array(Set(videoIDs.filter {
            $0.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
        })).prefix(3)
        guard !validIDs.isEmpty else { return }
        let day = currentDay()
        let defaults = UserDefaults.standard
        let key = "shadowing.shared-suggestions.\(uid)"
        let submitted = defaults.string(forKey: "\(key).day") == day
            ? defaults.stringArray(forKey: "\(key).ids") ?? [] : []
        let newIDs = Array(validIDs.filter { !submitted.contains($0) }.prefix(max(0, 50 - submitted.count)))
        guard !newIDs.isEmpty else { return }
        do {
            try await Firestore.firestore().collection("shortSignals").document(uid)
                .collection("suggestions").document(day).setData([
                    "videoIDs": FieldValue.arrayUnion(Array(newIDs)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            defaults.set(day, forKey: "\(key).day")
            defaults.set(submitted + newIDs, forKey: "\(key).ids")
        } catch {}
    }

    @MainActor
    static func deleteUserData(accountID: String) async throws {
        let root = Firestore.firestore().collection("shortSignals").document(accountID)
        for name in ["votes", "suggestions"] {
            while true {
                let documents = try await root.collection(name).limit(to: 100).getDocuments().documents
                if documents.isEmpty { break }
                let batch = Firestore.firestore().batch()
                for document in documents { batch.deleteDocument(document.reference) }
                try await batch.commit()
            }
        }
        try await root.delete()
        let defaults = UserDefaults.standard
        for kind in ["views", "suggestions"] {
            let key = "shadowing.shared-\(kind).\(accountID)"
            defaults.removeObject(forKey: "\(key).day")
            defaults.removeObject(forKey: "\(key).ids")
        }
    }

    private static func currentDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
