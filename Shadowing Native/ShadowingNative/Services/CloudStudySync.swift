import FirebaseFirestore
import Foundation
import Observation

private struct CloudStudySnapshot: Codable {
    var profile: LearningProfile
    var completedOnboarding: Bool
    var profileUpdatedAt: Date
    var progress: StudyProgressSnapshot
    var vocabulary: [VocabularyEntry]
}

@MainActor
@Observable
final class CloudStudySync {
    enum Status: Equatable {
        case signedOut
        case loading
        case synced
        case pending
        case failed(String)
    }

    private(set) var status: Status = .signedOut
    private var accountID: String?
    private var isReady = false
    private var isDirty = false
    private var isDeletingData = false
    private var saveTask: Task<Void, Never>?
    private var saveTaskID: UUID?
    private var generation = 0
    private var database: Firestore { Firestore.firestore() }

    func start(
        accountID: String?,
        appModel: AppModel,
        progressStore: StudyProgressStore,
        vocabularyStore: VocabularyStore
    ) async {
        guard self.accountID != accountID else { return }
        generation += 1
        let currentGeneration = generation
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
        isReady = false
        isDirty = false
        isDeletingData = false
        self.accountID = accountID
        guard let accountID else {
            status = .signedOut
            return
        }

        status = .loading
        do {
            let document = try await database.collection("nativeStudy").document(accountID).getDocument(source: .server)
            guard currentGeneration == generation else { return }
            let remotePayload = document.data()?["payload"] as? String
            if let payload = remotePayload,
               let data = payload.data(using: .utf8) {
                let remote = try JSONDecoder().decode(CloudStudySnapshot.self, from: data)
                appModel.merge(
                    profile: remote.profile,
                    completedOnboarding: remote.completedOnboarding,
                    updatedAt: remote.profileUpdatedAt
                )
                progressStore.merge(remote.progress)
                vocabularyStore.merge(remote.vocabulary)
            }
            isReady = true
            let localPayload = try encodePayload(
                appModel: appModel,
                progressStore: progressStore,
                vocabularyStore: vocabularyStore
            )
            if localPayload == remotePayload {
                status = .synced
            } else {
                scheduleSave(appModel: appModel, progressStore: progressStore, vocabularyStore: vocabularyStore)
            }
        } catch {
            guard currentGeneration == generation else { return }
            status = .failed("Não foi possível sincronizar: \(error.localizedDescription)")
        }
    }

    func retry(
        appModel: AppModel,
        progressStore: StudyProgressStore,
        vocabularyStore: VocabularyStore
    ) async {
        guard let accountID, !isDeletingData else { return }
        self.accountID = nil
        await start(accountID: accountID, appModel: appModel, progressStore: progressStore, vocabularyStore: vocabularyStore)
    }

    func scheduleSave(
        appModel: AppModel,
        progressStore: StudyProgressStore,
        vocabularyStore: VocabularyStore
    ) {
        guard isReady, accountID != nil, !isDeletingData else { return }
        isDirty = true
        status = .pending
        guard saveTask == nil else { return }
        let currentGeneration = generation
        let taskID = UUID()
        saveTaskID = taskID
        saveTask = Task {
            while isDirty && currentGeneration == generation && !Task.isCancelled {
                isDirty = false
                try? await Task.sleep(for: .seconds(1))
                guard currentGeneration == generation, !Task.isCancelled, let accountID else { break }
                do {
                    let payload = try encodePayload(
                        appModel: appModel,
                        progressStore: progressStore,
                        vocabularyStore: vocabularyStore
                    )
                    try await database.collection("nativeStudy").document(accountID).setData([
                        "schemaVersion": 1,
                        "payload": payload,
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    if currentGeneration == generation, !isDirty { status = .synced }
                } catch {
                    guard currentGeneration == generation else { break }
                    status = .failed("Dados salvos neste aparelho, mas não na nuvem: \(error.localizedDescription)")
                    break
                }
            }
            if saveTaskID == taskID {
                saveTask = nil
                saveTaskID = nil
            }
        }
    }

    func delete(accountID: String) async throws {
        guard self.accountID == accountID else { throw CloudSyncError.accountMismatch }
        generation += 1
        let deletionGeneration = generation
        isDeletingData = true
        let pendingSave = saveTask
        pendingSave?.cancel()
        saveTask = nil
        saveTaskID = nil
        isReady = false
        isDirty = false
        await pendingSave?.value
        guard self.accountID == accountID, generation == deletionGeneration else {
            throw CloudSyncError.accountMismatch
        }
        do {
            try await ShortCatalogSignals.deleteUserData(accountID: accountID)
            try await database.collection("nativeStudy").document(accountID).delete()
            guard generation == deletionGeneration, self.accountID == accountID else {
                throw CloudSyncError.accountMismatch
            }
            status = .signedOut
        } catch {
            if generation == deletionGeneration {
                isDeletingData = false
                status = .failed("Não foi possível excluir seus estudos. Tente novamente com conexão à internet.")
            }
            throw error
        }
    }

    func resumeAfterFailedDeletion(
        appModel: AppModel,
        progressStore: StudyProgressStore,
        vocabularyStore: VocabularyStore
    ) async {
        isDeletingData = false
        await retry(appModel: appModel, progressStore: progressStore, vocabularyStore: vocabularyStore)
    }

    private func encodePayload(
        appModel: AppModel,
        progressStore: StudyProgressStore,
        vocabularyStore: VocabularyStore
    ) throws -> String {
        let snapshot = CloudStudySnapshot(
            profile: appModel.profile,
            completedOnboarding: appModel.hasCompletedOnboarding,
            profileUpdatedAt: appModel.profileUpdatedAt,
            progress: progressStore.snapshot,
            vocabulary: vocabularyStore.entries.sorted { $0.word < $1.word }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(snapshot)
        guard data.count < 850_000, let payload = String(data: data, encoding: .utf8) else {
            throw CloudSyncError.dataTooLarge
        }
        return payload
    }
}

private enum CloudSyncError: LocalizedError {
    case dataTooLarge
    case accountMismatch

    var errorDescription: String? {
        switch self {
        case .dataTooLarge:
            "O histórico ultrapassou o limite de sincronização. Os dados continuam salvos neste aparelho."
        case .accountMismatch:
            "Sua sessão mudou. Entre novamente antes de excluir a conta. Nenhuma exclusão foi confirmada."
        }
    }
}
