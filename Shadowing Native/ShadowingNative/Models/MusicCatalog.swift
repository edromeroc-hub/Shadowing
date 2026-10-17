import Foundation

/// Mesma lista de `MUSIC_GENRES` em `curadoria-gemini/lib/music.mjs`. Estilo sem músicas no índice aparece como "em breve".
enum MusicGenre: String, CaseIterable, Codable, Identifiable, Sendable {
    case pop, rock, metal, country, rnb, hiphop, indie, acoustic, classics, gospel, jazz, electronic, reggae

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pop: "Pop"
        case .rock: "Rock"
        case .metal: "Heavy metal"
        case .country: "Country"
        case .rnb: "R&B"
        case .hiphop: "Hip hop"
        case .indie: "Indie"
        case .acoustic: "Acústico"
        case .classics: "Clássicos"
        case .gospel: "Gospel"
        case .jazz: "Jazz & blues"
        case .electronic: "Eletrônica"
        case .reggae: "Reggae"
        }
    }

    var systemImage: String {
        switch self {
        case .pop: "star.fill"
        case .rock: "guitars.fill"
        case .metal: "bolt.fill"
        case .country: "sun.horizon.fill"
        case .rnb: "heart.fill"
        case .hiphop: "music.mic"
        case .indie: "leaf.fill"
        case .acoustic: "music.quarternote.3"
        case .classics: "opticaldisc.fill"
        case .gospel: "hands.sparkles.fill"
        case .jazz: "pianokeys"
        case .electronic: "waveform"
        case .reggae: "beach.umbrella.fill"
        }
    }
}

struct MusicPreferences: Codable, Equatable, Sendable {
    /// Guardado como texto: um estilo removido numa versão futura não apaga as outras escolhas.
    var genreIDs: Set<String> = []
    var followedArtists: Set<String> = []
    var updatedAt: Date = .distantPast

    var genres: Set<MusicGenre> {
        get { Set(genreIDs.compactMap(MusicGenre.init(rawValue:))) }
        set { genreIDs = Set(newValue.map(\.rawValue)) }
    }
}

/// Uma linha de `approvedMusic/_index` (chaves curtas para o índice inteiro caber num documento).
struct MusicIndexEntry: Codable, Hashable, Identifiable, Sendable {
    let videoID: String
    let format: String
    let artist: String
    let title: String
    let genreIDs: [String]
    let level: EnglishLevel?
    let durationSeconds: Int

    var id: String { videoID }
    var isShort: Bool { format == "short" }
    var genres: Set<MusicGenre> { Set(genreIDs.compactMap(MusicGenre.init(rawValue:))) }

    private enum CodingKeys: String, CodingKey {
        case videoID = "v", format = "f", artist = "a", title = "t", genreIDs = "g", level = "l", durationSeconds = "d"
    }

    init(videoID: String, format: String, artist: String, title: String, genreIDs: [String], level: EnglishLevel?, durationSeconds: Int) {
        self.videoID = videoID
        self.format = format
        self.artist = artist
        self.title = title
        self.genreIDs = genreIDs
        self.level = level
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoID = try container.decode(String.self, forKey: .videoID)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "video"
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        genreIDs = try container.decodeIfPresent([String].self, forKey: .genreIDs) ?? []
        level = try container.decodeIfPresent(String.self, forKey: .level).flatMap(EnglishLevel.init(rawValue:))
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
    }

    var durationText: String {
        String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)
    }
}

struct MusicArtistSuggestion: Hashable, Identifiable, Sendable {
    let name: String
    let songCount: Int
    var id: String { name }
}

/// Recomendações da aba Músicas, sem rede: tudo sai do índice já baixado.
struct MusicRecommendationEngine: Sendable {
    let entries: [MusicIndexEntry]

    func songCount(in genre: MusicGenre) -> Int {
        entries.filter { $0.genres.contains(genre) }.count
    }

    /// Bandas com mais músicas no estilo, para os atalhos "Bandas de rock".
    /// Com `format`, só conta as músicas daquele formato (filtrar a banda nunca deixa a lista vazia).
    func topArtists(in genres: Set<MusicGenre>, format: String? = nil, limit: Int = 12) -> [MusicArtistSuggestion] {
        var counts: [String: Int] = [:]
        for entry in entries where !entry.genres.isDisjoint(with: genres) && !entry.artist.isEmpty && format.map({ entry.format == $0 }) ?? true {
            counts[entry.artist, default: 0] += 1
        }
        return counts.map { MusicArtistSuggestion(name: $0.key, songCount: $0.value) }
            .sorted { $0.songCount == $1.songCount ? $0.name < $1.name : $0.songCount > $1.songCount }
            .prefix(limit)
            .map { $0 }
    }

    /// Busca por artista ou música, sem acento e sem diferença de maiúsculas.
    func search(_ text: String) -> [MusicIndexEntry] {
        let query = Self.fold(text)
        guard !query.isEmpty else { return [] }
        return entries.filter { Self.fold("\($0.artist) \($0.title)").contains(query) }
            .sorted { Self.fold($0.artist).hasPrefix(query) && !Self.fold($1.artist).hasPrefix(query) }
    }

    /// Estilos escolhidos primeiro, depois bandas seguidas e o que ainda não foi praticado.
    /// A semente muda a cada sessão para a lista variar; a mesma semente dá a mesma ordem.
    func ranked(
        format: String,
        genres: Set<MusicGenre>,
        artist: String? = nil,
        followedArtists: Set<String> = [],
        practicedVideoIDs: Set<String> = [],
        seed: UInt64
    ) -> [MusicIndexEntry] {
        let pool = entries.filter { entry in
            entry.format == format &&
                (artist.map { entry.artist == $0 } ?? (genres.isEmpty || !entry.genres.isDisjoint(with: genres)))
        }
        let practicedArtists = Set(pool.filter { practicedVideoIDs.contains($0.videoID) }.map(\.artist))
        func score(_ entry: MusicIndexEntry) -> Int {
            entry.genres.intersection(genres).count * 4 +
                (followedArtists.contains(entry.artist) ? 10 : 0) +
                (practicedArtists.contains(entry.artist) ? 3 : 0) -
                (practicedVideoIDs.contains(entry.videoID) ? 8 : 0)
        }
        var ordered = pool.sorted { first, second in
            let firstScore = score(first)
            let secondScore = score(second)
            if firstScore != secondScore { return firstScore > secondScore }
            return Self.shuffleKey(first.videoID, seed: seed) < Self.shuffleKey(second.videoID, seed: seed)
        }
        // Nunca a mesma banda duas vezes seguidas, quando houver outra para intercalar.
        var result: [MusicIndexEntry] = []
        while !ordered.isEmpty {
            let index = artist == nil ? (ordered.firstIndex { $0.artist != result.last?.artist } ?? 0) : 0
            result.append(ordered.remove(at: index))
        }
        return result
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Embaralhamento estável (FNV-1a): não depende do `hashValue`, que muda a cada execução.
    private static func shuffleKey(_ text: String, seed: UInt64) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037 ^ seed
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
