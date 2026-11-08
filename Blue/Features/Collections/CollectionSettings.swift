import SwiftUI

struct CollectionCreator: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var error: String?
    var body: some View {
        ErrorLine(key: error).task {
            do {
                let id = try store.createCollection(title: l("untitled"), fields: [])
                if !navigation.path.isEmpty { navigation.path.removeLast() }
                navigation.path.append(.collection(id))
            } catch { self.error = (error as? BlueError ?? .saveFailed).key }
        }
    }
}

struct CollectionSettings: View {
    let collectionID: UUID
    var body: some View { CollectionView(collectionID: collectionID) }
}
