import SwiftUI

struct SearchView: View {
    @Binding var showNowPlaying: Bool
    let onAccountAvatarTap: () -> Void
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var searchText = ""
    @State private var selectedCategory: SearchCategory = .songs
    @State private var songResults: [Track] = []
    @State private var artistResults: [ArtistSummary] = []
    @State private var albumResults: [AlbumSummary] = []
    @State private var playlistResults: [PlaylistSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequestTask: Task<Void, Never>?
    @State private var currentOffset = 0
    @State private var hasMore = true
    @State private var isLoadingMore = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedAlbumID: Int?
    @State private var selectedArtistID: Int?
    @State private var selectedPlaylistID: Int?
    /// Cached pagination + query per category so switching tabs reuses in-memory results instead of refetching.
    @State private var searchCachePerCategory: [SearchCategory: CategorySearchCache] = [:]

    init(
        showNowPlaying: Binding<Bool> = .constant(false),
        onAccountAvatarTap: @escaping () -> Void = {}
    ) {
        self._showNowPlaying = showNowPlaying
        self.onAccountAvatarTap = onAccountAvatarTap
    }

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    searchBar
                    categoryPicker
                    resultState
                }
                .padding(.horizontal, OtoMetrics.screenPadding)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle(String(localized: String.LocalizationValue("tab_search")))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OtoTabProfileAvatarButton(action: onAccountAvatarTap)
            }
        }
        .navigationDestination(item: Binding(
            get: { selectedAlbumID.map(AlbumRoute.init(id:)) },
            set: { selectedAlbumID = $0?.id }
        )) { route in
            AlbumDetailView(albumID: route.id, showNowPlaying: $showNowPlaying)
        }
        .navigationDestination(item: Binding(
            get: { selectedArtistID.map(ArtistRoute.init(id:)) },
            set: { selectedArtistID = $0?.id }
        )) { route in
            ArtistDetailView(artistID: route.id, showNowPlaying: $showNowPlaying)
        }
        .navigationDestination(item: Binding(
            get: { selectedPlaylistID.map(PlaylistRoute.init(id:)) },
            set: { selectedPlaylistID = $0?.id }
        )) { route in
            PlaylistDetailView(playlistID: route.id, showNowPlaying: $showNowPlaying)
        }
        .onChange(of: selectedCategory) { _, newCategory in
            guard !trimmedQuery.isEmpty else { return }
            searchTask?.cancel()
            searchRequestTask?.cancel()
            if let cache = searchCachePerCategory[newCategory], cache.query == trimmedQuery {
                currentOffset = cache.lastRequestOffset
                hasMore = cache.hasMore
                searchError = nil
                isSearching = false
                isLoadingMore = false
                return
            }
            restartSearch()
        }
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private var currentResultCount: Int {
        switch selectedCategory {
        case .songs:
            songResults.count
        case .artists:
            artistResults.count
        case .albums:
            albumResults.count
        case .playlists:
            playlistResults.count
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.otoTextSecondary)

            TextField(String(localized: String.LocalizationValue("search_placeholder")), text: $searchText)
                .focused($isSearchFieldFocused)
                .font(.otoBody)
                .foregroundStyle(Color.otoTextPrimary)
                .otoMusicSearchFieldBehavior()
                .onSubmit {
                    searchTask?.cancel()
                    searchRequestTask?.cancel()
                    isSearchFieldFocused = false
                    restartSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    searchRequestTask?.cancel()

                    let trimmed = newValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        clearResults()
                        return
                    }

                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            restartSearch()
                        }
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.otoPanelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.otoPanelStroke, lineWidth: OtoMetrics.hairlineWidth)
                )
        )
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        OtoChip(isActive: selectedCategory == category) {
                            Text(category.title)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var resultState: some View {
        if let searchError {
            LiquidGlassCard {
                Text(searchError)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)
            }
        } else if isSearching && currentResultCount == 0 {
            LiquidGlassCard {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.otoAccent)
                    Spacer()
                }
                .padding(.vertical, 28)
            }
        } else {
            LazyVStack(spacing: 12) {
                switch selectedCategory {
                case .songs:
                    songRows
                case .artists:
                    artistRows
                case .albums:
                    albumRows
                case .playlists:
                    playlistRows
                }

                if isLoadingMore {
                    ProgressView()
                        .tint(.otoAccent)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private var songRows: some View {
        ForEach(Array(songResults.enumerated()), id: \.element.id) { index, track in
            Button {
                isSearchFieldFocused = false
                setNowPlayingZoomSource?(
                    .listRow(scope: "search-songs", trackID: track.id, rowIndex: index)
                )
                PlayerService.shared.playQueue(tracks: songResults, startIndex: index)
                showNowPlaying = true
            } label: {
                SearchResultRow(
                    coverURL: track.coverURL,
                    title: track.title,
                    subtitle: "\(track.artist) · \(track.album)",
                    actionLabel: String(localized: String.LocalizationValue("search_play")),
                    listZoomSourceID: .listRow(scope: "search-songs", trackID: track.id, rowIndex: index)
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                triggerLoadMoreIfNeeded(index: index)
            }
        }
    }

    private var artistRows: some View {
        ForEach(Array(artistResults.enumerated()), id: \.element.id) { index, artist in
            Button {
                selectedArtistID = artist.id
            } label: {
                SearchResultRow(
                    coverURL: artist.avatarURL,
                    title: artist.name,
                    subtitle: String(localized: String.LocalizationValue("search_artist_subtitle")),
                    actionLabel: String(localized: String.LocalizationValue("search_open")),
                    circularCover: true
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                triggerLoadMoreIfNeeded(index: index)
            }
        }
    }

    private var albumRows: some View {
        ForEach(Array(albumResults.enumerated()), id: \.element.id) { index, album in
            Button {
                selectedAlbumID = album.id
            } label: {
                SearchResultRow(
                    coverURL: album.coverURL,
                    title: album.name,
                    subtitle: String(format: String(localized: String.LocalizationValue("search_album_subtitle")), album.artist, album.trackCount),
                    actionLabel: String(localized: String.LocalizationValue("search_detail"))
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                triggerLoadMoreIfNeeded(index: index)
            }
        }
    }

    private var playlistRows: some View {
        ForEach(Array(playlistResults.enumerated()), id: \.element.id) { index, playlist in
            Button {
                selectedPlaylistID = playlist.id
            } label: {
                SearchResultRow(
                    coverURL: playlist.coverURL,
                    title: playlist.name,
                    subtitle: String(format: String(localized: String.LocalizationValue("search_playlist_subtitle")), playlist.trackCount),
                    actionLabel: String(localized: String.LocalizationValue("search_detail"))
                )
            }
            .buttonStyle(.plain)
            .onAppear {
                triggerLoadMoreIfNeeded(index: index)
            }
        }
    }

    private func restartSearch() {
        currentOffset = 0
        hasMore = true
        clearResults(for: selectedCategory)
        performSearch()
    }

    private func clearResults() {
        songResults = []
        artistResults = []
        albumResults = []
        playlistResults = []
        searchCachePerCategory = [:]
        searchError = nil
        isSearching = false
        isLoadingMore = false
        currentOffset = 0
        hasMore = true
    }

    private func clearResults(for category: SearchCategory) {
        searchError = nil
        searchCachePerCategory[category] = nil
        switch category {
        case .songs:
            songResults = []
        case .artists:
            artistResults = []
        case .albums:
            albumResults = []
        case .playlists:
            playlistResults = []
        }
    }

    private func triggerLoadMoreIfNeeded(index: Int) {
        if index >= currentResultCount - 5, hasMore, !isLoadingMore {
            loadMore()
        }
    }

    private func performSearch() {
        let query = trimmedQuery
        guard !query.isEmpty else { return }

        let requestedCategory = selectedCategory
        let requestedOffset = currentOffset

        if requestedOffset == 0 {
            isSearching = true
        } else {
            isLoadingMore = true
        }
        searchError = nil

        searchRequestTask = Task {
            do {
                switch requestedCategory {
                case .songs:
                    let results = try await NetEaseService.shared.searchSongs(query: query, limit: 20, offset: requestedOffset)
                    await MainActor.run {
                        apply(results: results, for: requestedCategory, query: query, offset: requestedOffset)
                    }
                case .artists:
                    let results = try await NetEaseService.shared.searchArtists(query: query, limit: 20, offset: requestedOffset)
                    await MainActor.run {
                        apply(results: results, for: requestedCategory, query: query, offset: requestedOffset)
                    }
                case .albums:
                    let results = try await NetEaseService.shared.searchAlbums(query: query, limit: 20, offset: requestedOffset)
                    await MainActor.run {
                        apply(results: results, for: requestedCategory, query: query, offset: requestedOffset)
                    }
                case .playlists:
                    let results = try await NetEaseService.shared.searchPlaylists(query: query, limit: 20, offset: requestedOffset)
                    await MainActor.run {
                        apply(results: results, for: requestedCategory, query: query, offset: requestedOffset)
                    }
                }
            } catch {
                await MainActor.run {
                    guard selectedCategory == requestedCategory, trimmedQuery == query else { return }
                    searchError = OtoL10n.text("search_failed", error.localizedDescription)
                    isSearching = false
                    isLoadingMore = false
                }
            }
        }
    }

    private func apply(results: [Track], for category: SearchCategory, query: String, offset: Int) {
        guard selectedCategory == category, trimmedQuery == query else { return }
        if offset == 0 {
            songResults = results
        } else {
            songResults.append(contentsOf: results)
        }
        searchCachePerCategory[category] = CategorySearchCache(
            query: query,
            lastRequestOffset: offset,
            hasMore: results.count == 20
        )
        finalizeSearch(count: results.count)
    }

    private func apply(results: [ArtistSummary], for category: SearchCategory, query: String, offset: Int) {
        guard selectedCategory == category, trimmedQuery == query else { return }
        if offset == 0 {
            artistResults = results
        } else {
            artistResults.append(contentsOf: results)
        }
        searchCachePerCategory[category] = CategorySearchCache(
            query: query,
            lastRequestOffset: offset,
            hasMore: results.count == 20
        )
        finalizeSearch(count: results.count)
    }

    private func apply(results: [AlbumSummary], for category: SearchCategory, query: String, offset: Int) {
        guard selectedCategory == category, trimmedQuery == query else { return }
        if offset == 0 {
            albumResults = results
        } else {
            albumResults.append(contentsOf: results)
        }
        searchCachePerCategory[category] = CategorySearchCache(
            query: query,
            lastRequestOffset: offset,
            hasMore: results.count == 20
        )
        finalizeSearch(count: results.count)
    }

    private func apply(results: [PlaylistSummary], for category: SearchCategory, query: String, offset: Int) {
        guard selectedCategory == category, trimmedQuery == query else { return }
        if offset == 0 {
            playlistResults = results
        } else {
            playlistResults.append(contentsOf: results)
        }
        searchCachePerCategory[category] = CategorySearchCache(
            query: query,
            lastRequestOffset: offset,
            hasMore: results.count == 20
        )
        finalizeSearch(count: results.count)
    }

    private func finalizeSearch(count: Int) {
        hasMore = count == 20
        isSearching = false
        isLoadingMore = false
    }

    private func loadMore() {
        guard !isLoadingMore && hasMore else { return }
        currentOffset += 20
        performSearch()
    }
}

private struct SearchResultRow: View {
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    let coverURL: String
    let title: String
    let subtitle: String
    let actionLabel: String
    var circularCover: Bool = false
    var listZoomSourceID: NowPlayingZoomSourceID? = nil

    var body: some View {
        LiquidGlassCard {
            HStack(spacing: 14) {
                cover

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.otoHeadline)
                        .foregroundStyle(Color.otoTextPrimary)
                    Text(subtitle)
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(actionLabel)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if circularCover {
            RemoteImageView(urlString: coverURL, placeholderStyle: .avatar)
                .frame(width: 58, height: 58)
                .modifier(SearchCoverZoomModifier(
                    listZoomSourceID: listZoomSourceID,
                    heroNamespace: heroNamespace,
                    circular: true,
                    matchedTransitionCornerRadius: 29
                ))
        } else {
            RemoteImageView(urlString: coverURL)
                .frame(width: 58, height: 58)
                .modifier(SearchCoverZoomModifier(
                    listZoomSourceID: listZoomSourceID,
                    heroNamespace: heroNamespace,
                    circular: false,
                    matchedTransitionCornerRadius: 16
                ))
        }
    }
}

private struct CategorySearchCache: Equatable {
    var query: String
    var lastRequestOffset: Int
    var hasMore: Bool
}

private struct SearchCoverZoomModifier: ViewModifier {
    let listZoomSourceID: NowPlayingZoomSourceID?
    let heroNamespace: Namespace.ID?
    let circular: Bool
    /// Corner radius for `matchedTransitionSource` (must be `RoundedRectangle`); for circular covers use half the side length.
    let matchedTransitionCornerRadius: CGFloat
    private static let displayCornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if let listZoomSourceID, let heroNamespace {
            content
                .nowPlayingMatchedListArtwork(
                    sourceID: listZoomSourceID,
                    namespace: heroNamespace,
                    cornerRadius: matchedTransitionCornerRadius
                )
        } else if circular {
            content.clipShape(Circle())
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: Self.displayCornerRadius, style: .continuous))
        }
    }
}

private enum SearchCategory: String, CaseIterable, Identifiable {
    case songs
    case artists
    case albums
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs: String(localized: String.LocalizationValue("search_cat_songs"))
        case .artists: String(localized: String.LocalizationValue("search_cat_artists"))
        case .albums: String(localized: String.LocalizationValue("search_cat_albums"))
        case .playlists: String(localized: String.LocalizationValue("search_cat_playlists"))
        }
    }
}

private struct AlbumRoute: Identifiable, Hashable {
    let id: Int
}

private struct ArtistRoute: Identifiable, Hashable {
    let id: Int
}

private struct PlaylistRoute: Identifiable, Hashable {
    let id: Int
}

private extension View {
    @ViewBuilder
    func otoMusicSearchFieldBehavior() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
        #else
        self
        #endif
    }
}
