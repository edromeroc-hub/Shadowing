import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

/// Catálogo da aba Músicas (`approvedMusic`): 1 leitura para o índice inteiro e 1 por música aberta.
@MainActor
@Observable
final class MusicCatalogService {
    static let shared = MusicCatalogService()

    private(set) var entries: [MusicIndexEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var lessons: [String: PreparedShortLesson] = [:]

    func loadIndexIfNeeded() async {
        guard entries.isEmpty, !isLoading else { return }
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Entre na sua conta para ver as músicas."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore().collection("approvedMusic").document("_index").getDocument()
            guard let rows = snapshot.data()?["entries"] as? [[String: Any]], !rows.isEmpty else {
                errorMessage = "As músicas ainda estão sendo preparadas. Volte daqui a pouco."
                return
            }
            let data = try JSONSerialization.data(withJSONObject: rows)
            entries = try JSONDecoder().decode([FailableEntry].self, from: data).compactMap(\.entry)
        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // Regra de `approvedMusic` ainda não publicada no Firestore.
            errorMessage = "As músicas ainda não foram liberadas. Tente de novo mais tarde."
        } catch {
            errorMessage = "Não foi possível carregar as músicas. Verifique a conexão e tente novamente."
        }
    }

    func lesson(for videoID: String) async throws -> PreparedShortLesson {
        if let lesson = lessons[videoID] { return lesson }
        let snapshot = try await Firestore.firestore().collection("approvedMusic").document(videoID).getDocument()
        guard snapshot.data()?["status"] as? String == "approved",
              let payload = snapshot.data()?["payload"] as? String,
              let record = try? JSONDecoder().decode(CatalogPayload.self, from: Data(payload.utf8)),
              record.videoID == videoID,
              let lesson = record.preparedLesson() else { throw TranscriptError.emptyCaptions }
        lessons[videoID] = lesson
        return lesson
    }

    /// Uma linha estragada no índice não derruba a lista inteira.
    private struct FailableEntry: Decodable {
        let entry: MusicIndexEntry?
        init(from decoder: Decoder) throws {
            entry = try? MusicIndexEntry(from: decoder)
        }
    }
}
