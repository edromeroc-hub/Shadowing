import SwiftUI

/// Aba Músicas: estilos escolhidos na primeira visita, bandas do estilo, busca e Shorts ou vídeos completos.
struct MusicHomeView: View {
    @Environment(StudyProgressStore.self) private var progressStore
    @State private var catalog = MusicCatalogService.shared
    @State private var format = "video"
    @State private var selectedGenre: MusicGenre?
    @State private var selectedArtist: String?
    @State private var searchText = ""
    @State private var isEditingGenres = false
    @State private var openSong: MusicIndexEntry?
    // A lista muda a cada visita, mas não pula enquanto o aluno rola.
    @State private var seed = UInt64.random(in: 0...UInt64.max)

    private var engine: MusicRecommendationEngine { MusicRecommendationEngine(entries: catalog.entries) }
    private var chosenGenres: Set<MusicGenre> { progressStore.musicPreferences?.genres ?? [] }
    private var activeGenres: Set<MusicGenre> { selectedGenre.map { [$0] } ?? chosenGenres }
    private var followedArtists: Set<String> { progressStore.musicPreferences?.followedArtists ?? [] }

    private var songs: [MusicIndexEntry] {
        engine.ranked(
            format: format,
            genres: activeGenres,
            artist: selectedArtist,
            followedArtists: followedArtists,
            practicedVideoIDs: Set(progressStore.videos.keys),
            seed: seed
        )
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            content
        }
        .navigationTitle("Músicas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() } }
        .task { await catalog.loadIndexIfNeeded() }
        .sheet(isPresented: $isEditingGenres) {
            NavigationStack {
                MusicGenrePicker(engine: engine, initialSelection: chosenGenres, actionTitle: "Salvar") { genres in
                    progressStore.setMusicGenres(genres)
                    if let selectedGenre, !genres.contains(selectedGenre) { self.selectedGenre = nil }
                    isEditingGenres = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancelar") { isEditingGenres = false }
                    }
                }
            }
        }
        .navigationDestination(item: $openSong) { song in
            YouTubeImportView(
                initialLink: song.isShort ? "https://youtube.com/shorts/\(song.videoID)" : "https://www.youtube.com/watch?v=\(song.videoID)",
                isShort: song.isShort,
                catalogLesson: { try await MusicCatalogService.shared.lesson(for: song.videoID) }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if catalog.entries.isEmpty {
            if let message = catalog.errorMessage {
                ContentUnavailableView {
                    Label("Músicas indisponíveis", systemImage: "music.note")
                } description: {
                    Text(message)
                } actions: {
                    Button("Tentar novamente") { Task { await catalog.loadIndexIfNeeded() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Carregando músicas…").tint(ShadowingTheme.blue)
            }
        } else if chosenGenres.isEmpty {
            MusicGenrePicker(engine: engine, initialSelection: [], actionTitle: "Começar") { genres in
                progressStore.setMusicGenres(genres)
            }
        } else {
            library
        }
    }

    private var library: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Aprenda inglês\ncantando")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                searchField

                Picker("Formato", selection: $format) {
                    Text("Vídeos completos").tag("video")
                    Text("Shorts").tag("short")
                }
                .pickerStyle(.segmented)

                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    genreChips
                    artistChips
                    songList(songs)
                } else {
                    let results = engine.search(searchText).filter { $0.format == format }
                    Text(results.isEmpty ? "Nada encontrado em \(format == "short" ? "Shorts" : "vídeos completos")." : "\(results.count) resultado\(results.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    songList(results)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .opaqueTopScrollEdge()
        .onChange(of: format) { _, _ in selectedArtist = nil }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar banda ou música", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .shadowingGlass(cornerRadius: 16)
    }

    private var genreChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                FilterChip(title: "Para você", isSelected: selectedGenre == nil) {
                    selectedGenre = nil
                    selectedArtist = nil
                }
                ForEach(MusicGenre.allCases.filter(chosenGenres.contains)) { genre in
                    FilterChip(title: genre.title, isSelected: selectedGenre == genre) {
                        selectedGenre = genre
                        selectedArtist = nil
                    }
                }
                Button {
                    isEditingGenres = true
                } label: {
                    Label("Estilos", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ShadowingTheme.blue)
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var artistChips: some View {
        let artists = engine.topArtists(in: activeGenres, format: format)
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedGenre.map { "Bandas de \($0.title.lowercased())" } ?? "Bandas para você")
                    .font(.title3.bold())
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(artists) { artist in
                            artistChip(artist)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Text("Toque para filtrar. Toque e segure para seguir a banda.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func artistChip(_ artist: MusicArtistSuggestion) -> some View {
        let isSelected = selectedArtist == artist.name
        let isFollowed = followedArtists.contains(artist.name)
        return Button {
            selectedArtist = isSelected ? nil : artist.name
        } label: {
            HStack(spacing: 6) {
                if isFollowed { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                Text(artist.name)
                Text("\(artist.songCount)").foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? ShadowingTheme.violet : .white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isFollowed ? "Deixar de seguir" : "Seguir \(artist.name)", systemImage: isFollowed ? "star.slash" : "star") {
                progressStore.setMusicArtist(artist.name, followed: !isFollowed)
            }
        }
        .accessibilityHint(isFollowed ? "Banda seguida" : "")
    }

    @ViewBuilder
    private func songList(_ list: [MusicIndexEntry]) -> some View {
        if list.isEmpty {
            ContentUnavailableView(
                "Nada por aqui ainda",
                systemImage: "music.note",
                description: Text(format == "short" ? "Ainda não há Shorts deste estilo. Veja os vídeos completos." : "Ainda não há vídeos deste estilo. Veja os Shorts.")
            )
            .padding(.top, 12)
        } else if format == "short" {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 14) {
                ForEach(list) { song in
                    Button { openSong = song } label: { MusicShortCard(song: song) }
                        .buttonStyle(.plain)
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(list) { song in
                    Button { openSong = song } label: { MusicVideoRow(song: song, isPracticed: progressStore.videos[song.videoID] != nil) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct MusicVideoRow: View {
    let song: MusicIndexEntry
    let isPracticed: Bool

    var body: some View {
        HStack(spacing: 12) {
            MusicThumbnail(videoID: song.videoID)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.subheadline.bold()).lineLimit(2)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(song.durationText)
                    if let level = song.level { Text("· \(level.title)") }
                    if isPracticed { Text("· praticada").foregroundStyle(ShadowingTheme.mint) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(ShadowingTheme.blue)
        }
        .padding(10)
        .shadowingGlass(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

private struct MusicShortCard: View {
    let song: MusicIndexEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MusicThumbnail(videoID: song.videoID)
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(song.durationText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                }
            Text(song.title).font(.caption.bold()).lineLimit(2)
            Text(song.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MusicThumbnail: View {
    let videoID: String

    var body: some View {
        Color.black
            .overlay {
                AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
            .clipped()
    }
}

/// Grade de estilos: primeira visita à aba e edição pelo botão "+ Estilos".
struct MusicGenrePicker: View {
    let engine: MusicRecommendationEngine
    let actionTitle: String
    let onDone: (Set<MusicGenre>) -> Void
    @State private var selection: Set<MusicGenre>

    init(engine: MusicRecommendationEngine, initialSelection: Set<MusicGenre>, actionTitle: String, onDone: @escaping (Set<MusicGenre>) -> Void) {
        self.engine = engine
        self.actionTitle = actionTitle
        self.onDone = onDone
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Que música você curte?")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Escolha um ou mais estilos. Depois as sugestões ficam por nossa conta.")
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(MusicGenre.allCases) { genre in
                            genreCard(genre)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onDone(selection)
            } label: {
                Text(selection.isEmpty ? "Escolha pelo menos um estilo" : actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Fundo sólido: desativado, o botão é translúcido e os cards apareciam por trás do texto.
            .background(LinearGradient(colors: [ShadowingTheme.ink.opacity(0), ShadowingTheme.ink.opacity(0.95)], startPoint: .top, endPoint: .center))
        }
    }

    private func genreCard(_ genre: MusicGenre) -> some View {
        let count = engine.songCount(in: genre)
        let isSelected = selection.contains(genre)
        return Button {
            if isSelected { selection.remove(genre) } else { selection.insert(genre) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: genre.systemImage)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : ShadowingTheme.blue)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                    }
                }
                Text(genre.title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(count == 0 ? "em breve" : "\(count) músicas")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? ShadowingTheme.blue : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(count == 0 ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityLabel("\(genre.title), \(count == 0 ? "em breve" : "\(count) músicas")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
