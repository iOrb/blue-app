import SwiftUI

struct CollectionCreator: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var collectionID: UUID?
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                QuietButton(key: "back", symbol: "chevron.left") { navigation.path.removeLast() }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityIdentifier("collectionBack")
                Spacer()
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BlueDoneButton(action: finish).accessibilityIdentifier("finishCollection")
                }
            }.padding(.horizontal, 18)
            TextField(l("title"), text: $name)
                .font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                .submitLabel(.done)
                .accessibilityIdentifier("collectionTitle")
                .onChange(of: name) { _, value in save(value) }
                .onSubmit(finish)
            ErrorLine(key: error)
            Spacer()
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private func finish() {
        if error != nil { save(name) }
        guard error == nil, let collectionID, navigation.path.last == .newCollection else { return }
        navigation.path[navigation.path.count - 1] = .collection(collectionID)
    }

    private func save(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if let collectionID, var collection = store.collection(collectionID) {
                collection.title = .user(value)
                try store.saveCollection(collection)
            } else {
                collectionID = try store.createCollection(title: value, fields: [])
            }
            error = nil
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }

}

struct CollectionSettings: View {
    let collectionID: UUID
    var body: some View { CollectionView(collectionID: collectionID) }
}
