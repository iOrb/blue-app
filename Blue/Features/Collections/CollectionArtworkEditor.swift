import PhotosUI
import SwiftUI

@MainActor private enum ArtworkCache {
    static let images: NSCache<NSUUID, UIImage> = {
        let cache = NSCache<NSUUID, UIImage>()
        cache.totalCostLimit = 24_000_000
        return cache
    }()
    static func image(_ artwork: CollectionArtwork) -> UIImage? {
        if let image = images.object(forKey: artwork.id as NSUUID) { return image }
        guard let image = UIImage(data: artwork.jpeg) else { return nil }
        images.setObject(image, forKey: artwork.id as NSUUID, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}

struct CollectionArtworkView: View {
    let artwork: CollectionArtwork?
    var symbol = "list.bullet"
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let artwork, let image = ArtworkCache.image(artwork) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ItemGlyph(symbol: symbol).font(.system(size: min(size * 0.55, 42))).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
        .accessibilityHidden(true)
    }
}

struct CollectionArtworkEditor: View {
    let collectionID: UUID
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(\.blueSheetDismiss) private var closeSheet
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = "list.bullet"
    @State private var artwork: CollectionArtwork?
    @State private var originalSymbol = "list.bullet"
    @State private var originalArtwork: CollectionArtwork?
    @State private var mode = 0
    @State private var subject = ""
    @State private var style = "illustration"
    @State private var theme = "abstract"
    private let themes = ["abstract", "nature", "space", "animals", "city"]
    @State private var candidates: [CollectionArtwork] = []
    @State private var photo: PhotosPickerItem?
    @State private var generating = false
    @State private var error: String?
    @State private var generation: Task<Void, Never>?
    private let symbols = [
        "list.bullet", "film", "book", "fork.knife", "music.note", "airplane", "mountain.2", "sparkles", "heart",
        "star", "house", "leaf", "🗿", "🍿", "🎮", "☕️",
    ]
    private let styles = ["illustration", "photo", "pop", "watercolor"]
    private var changed: Bool { symbol != originalSymbol || artwork != originalArtwork }

    var body: some View {
        VStack(spacing: 0) {
            BlueSheetHeader(title: l("artwork.title"), close: close) {
                if changed { BlueDoneButton(action: save).accessibilityIdentifier("saveCollectionArtwork") }
            }
            ScrollView {
                VStack(spacing: 20) {
                    CollectionArtworkView(artwork: artwork, symbol: symbol, size: 176)
                        .accessibilityIdentifier("artworkPreview")
                    Picker(l("artwork.title"), selection: $mode) {
                        Text(l("artwork.icon")).tag(0)
                        Text(l("artwork.photo")).tag(1)
                        Text(l("artwork.ai")).tag(2)
                    }.pickerStyle(.segmented).accessibilityIdentifier("artworkMode")
                    if mode == 0 {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(symbols, id: \.self) { value in
                                Button {
                                    symbol = value
                                    artwork = nil
                                } label: {
                                    ItemGlyph(symbol: value).frame(maxWidth: .infinity, minHeight: 48)
                                        .background(
                                            symbol == value && artwork == nil ? Color.primary.opacity(0.08) : .clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(BlueRowPress()).accessibilityLabel(value)
                                    .accessibilityIdentifier("collectionSymbol-\(value)")
                            }
                        }
                        TextField(
                            l("artwork.customIcon"),
                            text: Binding(
                                get: { symbol },
                                set: {
                                    symbol = $0
                                    artwork = nil
                                })
                        )
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("collectionSymbolInput")
                    } else if mode == 1 {
                        PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .automatic) {
                            Label(l("artwork.choosePhoto"), systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(BlueRowPress())
                    } else {
                        Menu {
                            ForEach(themes, id: \.self) { value in
                                Button(l("artwork.theme.\(value)")) {
                                    theme = value
                                    subject = l("artwork.prompt.\(value)")
                                }
                            }
                        } label: {
                            HStack {
                                Text(l("artwork.theme.\(theme)")).underline()
                                Image(systemName: "chevron.down").font(.caption)
                            }.frame(minHeight: 44)
                        }.buttonStyle(BlueRowPress())
                        TextField(l("artwork.subject"), text: $subject, axis: .vertical).lineLimit(1...3)
                            .accessibilityIdentifier("artworkSubject")
                        Menu {
                            ForEach(styles, id: \.self) { value in
                                Button(l("artwork.style.\(value)")) { style = value }
                            }
                        } label: {
                            HStack {
                                Text(l("artwork.style.\(style)")).underline()
                                Image(systemName: "chevron.down").font(.caption)
                            }.frame(minHeight: 44)
                        }.buttonStyle(BlueRowPress())
                        if !candidates.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(candidates) { candidate in
                                    Button {
                                        artwork = candidate
                                    } label: {
                                        CollectionArtworkView(artwork: candidate, size: 54)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9).strokeBorder(
                                                    artwork?.id == candidate.id ? Color.primary : .clear, lineWidth: 2))
                                    }.buttonStyle(BlueRowPress()).accessibilityLabel(l("artwork.variant"))
                                }
                            }
                        }
                        if AssistantConnection.key(for: .openai) != nil {
                            Button(action: generate) {
                                HStack(spacing: 8) {
                                    if generating { ProgressView() } else { Image(systemName: "sparkles") }
                                    Text(l(generating ? "artwork.generating" : "artwork.generate"))
                                }.frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(BlueRowPress()).disabled(
                                generating || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text(l("artwork.privacy")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(l("artwork.setup")) {
                                navigation.artworkRequestsSetup = true
                                close()
                            }.buttonStyle(BlueRowPress())
                        }
                    }
                    ErrorLine(key: error)
                }.padding(.horizontal, 24).padding(.bottom, 20).blueSheetContentSize()
            }.scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            guard let collection = store.collection(collectionID) else { return }
            symbol = collection.symbol
            artwork = collection.artwork
            originalSymbol = symbol
            originalArtwork = artwork
        }
        .onChange(of: mode) { _, value in
            if value == 2, subject.isEmpty { subject = l("artwork.prompt.\(theme)") }
        }
        .onDisappear { generation?.cancel() }
        .task(id: photo) {
            guard let photo else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw BlueError.invalidValue }
                let next = try await Task.detached { try CollectionArtworkService.prepare(data) }.value
                try Task.checkCancellation()
                artwork = next
                error = nil
            } catch is CancellationError {} catch { self.error = "artwork.failed" }
        }
    }

    private func close() { if let closeSheet { closeSheet() } else { dismiss() } }
    private func save() {
        guard var collection = store.collection(collectionID) else { return }
        collection.symbol = symbol
        collection.artwork = artwork
        do {
            try store.saveCollection(collection)
            close()
        } catch { self.error = "artwork.failed" }
    }
    private func generate() {
        guard let key = AssistantConnection.key(for: .openai), !generating else { return }
        let prompt = subject
        let selectedStyle =
            [
                "illustration": "editorial illustration", "photo": "editorial photography", "pop": "a pop art painting",
                "watercolor": "a watercolor painting",
            ][style] ?? style
        generating = true
        error = nil
        generation = Task {
            defer { generating = false }
            do {
                let next = try await CollectionArtworkService.generate(prompt: prompt, style: selectedStyle, key: key)
                try Task.checkCancellation()
                candidates = next
                artwork = next.first
            } catch is CancellationError {} catch { self.error = "artwork.failed" }
        }
    }
}
