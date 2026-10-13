import Foundation
import Observation

struct VocabularyEntry: Codable, Identifiable, Hashable {
    let word: String
    private(set) var translations: [String: String]
    var addedAt: Date
    var encounters: Int

    var id: String { word }

    init(word: String, translations: [String: String] = [:], addedAt: Date, encounters: Int) {
        self.word = word
        self.translations = translations
        self.addedAt = addedAt
        self.encounters = encounters
    }

    func translation(for language: SupportedLanguage) -> String? {
        translations[language.translationCode]
    }

    mutating func setTranslation(_ translation: String, language: SupportedLanguage) {
        translations[language.translationCode] = translation
    }

    private enum CodingKeys: String, CodingKey {
        case word
        case translation
        case translations
        case addedAt
        case encounters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        encounters = try container.decodeIfPresent(Int.self, forKey: .encounters) ?? 1
        translations = try container.decodeIfPresent([String: String].self, forKey: .translations) ?? [:]

        if let legacyTranslation = try container.decodeIfPresent(String.self, forKey: .translation),
           translations[SupportedLanguage.portugueseBrazil.translationCode] == nil {
            translations[SupportedLanguage.portugueseBrazil.translationCode] = legacyTranslation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(translations, forKey: .translations)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(encounters, forKey: .encounters)
    }
}

@MainActor
@Observable
final class VocabularyStore {
    private(set) var entries: [VocabularyEntry]

    private let defaults: UserDefaults
    private let storageKey = "shadowing.native.vocabulary"
    private var activeAccountID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let savedEntries = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            entries = savedEntries
        } else {
            entries = []
        }
    }

    var recentEntries: [VocabularyEntry] {
        entries.sorted { $0.addedAt > $1.addedAt }
    }

    func merge(_ remoteEntries: [VocabularyEntry]) {
        var combined = Dictionary(uniqueKeysWithValues: entries.map { ($0.word, $0) })
        for entry in remoteEntries {
            if let local = combined[entry.word] {
                combined[entry.word] = VocabularyEntry(
                    word: entry.word,
                    translations: local.translations.merging(entry.translations) { current, _ in current },
                    addedAt: min(local.addedAt, entry.addedAt),
                    encounters: max(local.encounters, entry.encounters)
                )
            } else {
                combined[entry.word] = entry
            }
        }
        entries = Array(combined.values)
        save()
    }

    func activateAccount(_ accountID: String?) {
        guard activeAccountID != accountID else { return }
        let nextKey = key(for: accountID)
        if activeAccountID == nil, accountID != nil, defaults.object(forKey: nextKey) == nil,
           let guestData = defaults.data(forKey: storageKey) {
            defaults.set(guestData, forKey: nextKey)
            defaults.removeObject(forKey: storageKey)
        }
        activeAccountID = accountID
        if let data = defaults.data(forKey: nextKey),
           let stored = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            entries = stored
        } else {
            entries = []
        }
    }

    func deleteAccountData(for accountID: String) {
        defaults.removeObject(forKey: key(for: accountID))
        if activeAccountID == accountID {
            activeAccountID = nil
            entries = []
        }
    }

    func contains(_ word: String) -> Bool {
        entries.contains { $0.word == normalize(word) }
    }

    @discardableResult
    func add(_ word: String) -> Bool {
        let normalized = normalize(word)
        guard !normalized.isEmpty, !contains(normalized) else { return false }
        entries.append(VocabularyEntry(word: normalized, addedAt: Date(), encounters: 1))
        save()
        return true
    }

    @discardableResult
    func toggle(_ word: String) -> Bool {
        let normalized = normalize(word)
        guard !normalized.isEmpty else { return false }

        if let index = entries.firstIndex(where: { $0.word == normalized }) {
            entries.remove(at: index)
            save()
            return false
        }

        return add(normalized)
    }

    func translation(for word: String, language: SupportedLanguage) -> String? {
        let normalized = normalize(word)
        return entries.first(where: { $0.word == normalized })?.translation(for: language)
    }

    func setTranslation(_ translation: String, for word: String, language: SupportedLanguage) {
        let normalized = normalize(word)
        guard let index = entries.firstIndex(where: { $0.word == normalized }) else { return }
        entries[index].setTranslation(
            translation.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language
        )
        save()
    }

    private func normalize(_ word: String) -> String {
        word
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key(for: activeAccountID))
    }

    private func key(for accountID: String?) -> String {
        accountID.map { "\(storageKey).\($0)" } ?? storageKey
    }
}
