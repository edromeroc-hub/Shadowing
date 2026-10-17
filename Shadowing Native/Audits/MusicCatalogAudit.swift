import Foundation

@main
struct MusicCatalogAudit {
    static func main() throws {
        let fixture = URL(fileURLWithPath: "Audits/fixtures/music/index.json")
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: Any]]
        // Mesmo caminho do app: linha estragada é descartada sem derrubar o índice.
        let entries = rows.compactMap { row -> MusicIndexEntry? in
            guard let data = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? JSONDecoder().decode(MusicIndexEntry.self, from: data)
        }
        precondition(entries.count == 7, "linha sem videoID é descartada")
        precondition(entries[6].level == nil && entries[6].durationText == "4:21", "nível ausente vira nil")
        precondition(entries[5].genres == [.rock], "estilo desconhecido é ignorado")
        precondition(entries[4].isShort && !entries[0].isShort)
        print("PASS index decoding")

        let engine = MusicRecommendationEngine(entries: entries)
        precondition(engine.songCount(in: .rock) == 5 && engine.songCount(in: .metal) == 0, "estilo vazio fica \"em breve\"")
        precondition(MusicGenre.allCases.contains(.metal) && MusicGenre(rawValue: "hiphop") == .hiphop)
        let rockArtists = engine.topArtists(in: [.rock])
        precondition(rockArtists.first == MusicArtistSuggestion(name: "Queen", songCount: 3), "banda com mais músicas primeiro")
        precondition(rockArtists.map(\.name) == ["Queen", "Green Day", "Linkin Park"])
        precondition(engine.topArtists(in: [.rock], format: "short") == [MusicArtistSuggestion(name: "Queen", songCount: 1)], "bandas contam só o formato escolhido")
        print("PASS genres and artist suggestions")

        let first = engine.ranked(format: "video", genres: [.rock], seed: 42)
        precondition(Set(first.map(\.videoID)) == ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc", "fffffffffff"], "só vídeos do estilo")
        precondition(zip(first, first.dropFirst()).allSatisfy { $0.artist != $1.artist }, "mesma banda não aparece em sequência")
        precondition(first == engine.ranked(format: "video", genres: [.rock], seed: 42), "mesma semente, mesma ordem")
        let followed = engine.ranked(format: "video", genres: [.rock], followedArtists: ["Linkin Park"], seed: 7)
        precondition(followed.first?.artist == "Linkin Park", "banda seguida sobe")
        // Já praticada desce (só sobe de novo para intercalar bandas).
        for seed in UInt64(0)..<20 {
            let practiced = engine.ranked(format: "video", genres: [.rock], practicedVideoIDs: ["fffffffffff"], seed: seed)
            precondition(practiced.first?.videoID != "fffffffffff", "música já praticada não abre a lista")
        }
        let onlyQueen = engine.ranked(format: "video", genres: [.pop], artist: "Queen", seed: 1)
        precondition(onlyQueen.map(\.artist) == ["Queen", "Queen"], "filtro por banda ignora o estilo")
        precondition(engine.ranked(format: "short", genres: [.rock], seed: 1).map(\.videoID) == ["eeeeeeeeeee"])
        print("PASS ranking")

        precondition(engine.search("queen").count == 3 && engine.search("BEYONCE").first?.title == "Halo", "busca sem acento e sem caixa")
        precondition(engine.search("  ").isEmpty)
        print("PASS search")

        var preferences = MusicPreferences()
        preferences.genres = [.rock, .metal]
        let decoded = try JSONDecoder().decode(MusicPreferences.self, from: JSONEncoder().encode(preferences))
        precondition(decoded.genres == [.rock, .metal])
        let future = try JSONDecoder().decode(MusicPreferences.self, from: Data(#"{"genreIDs":["rock","kpop"],"followedArtists":[],"updatedAt":0}"#.utf8))
        precondition(future.genres == [.rock], "estilo desconhecido não apaga os outros")
        print("PASS preferences")
    }
}
