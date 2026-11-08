import SwiftUI

/// A compact, readable action shared by navigation, filters and item properties.
struct QuickChoice: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 13).frame(minHeight: 44)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
                .background(selected ? Color.primary : Color.primary.opacity(0.055), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DismissAssistantOnTap: ViewModifier {
    @Environment(NavigationState.self) private var navigation
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                navigation.assistantFocused = false
                navigation.assistantExpanded = false
            })
    }
}

struct ItemGlyph: View {
    let symbol: String
    var body: some View {
        if UIImage(systemName: symbol) != nil {
            Image(systemName: symbol)
        } else {
            Text(String(symbol.prefix(4))).font(.system(size: 22))
        }
    }
}

extension IndicatorTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .green: .green
        case .red: .red
        case .pink: .pink
        case .yellow: .yellow
        }
    }
}

extension FieldDefinition {
    static var favoriteIndicator: FieldDefinition {
        FieldDefinition(
            id: "__favorite", label: .key("field.favorite"), kind: .favorite, showInRow: true, tint: .yellow)
    }
    var indicatorSymbol: String { icon ?? kind.symbol }
    var indicatorColor: Color { (tint ?? (kind == .favorite ? .yellow : kind == .like ? .pink : .blue)).color }
}

struct IndicatorControl: View {
    let field: FieldDefinition
    let selected: Bool
    var showsLabel = false
    var action: () -> Void
    @Environment(Localizer.self) private var l
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ItemGlyph(symbol: field.indicatorSymbol)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.7))
                    .saturation(selected ? 1 : 0).opacity(selected ? 1 : 0.7)
                    .frame(width: 44, height: 44)
                    .background(
                        selected ? field.indicatorColor.opacity(0.1) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 14))
                if showsLabel { Text(l.text(field.label)).font(.subheadline).foregroundStyle(.primary) }
            }.contentShape(Rectangle())
        }.buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityLabel(
            l.text(field.label)
        )
        .accessibilityValue(l(selected ? "yes" : "no"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(l.text(field.label))
    }
}

struct RecordIndicators: View {
    let record: Record
    let collection: Collection
    var interactive = false
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    private var fields: [FieldDefinition] {
        [collection.fields.first { $0.kind == .favorite } ?? .favoriteIndicator]
            + collection.fields.filter { $0.kind.isBoolean && $0.kind != .favorite }
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)], alignment: .leading, spacing: 8)
        {
            ForEach(fields) { field in
                let selected = field.kind == .favorite ? record.isFavorite : record.values[field.id]?.flag == true
                if interactive {
                    IndicatorControl(field: field, selected: selected) { toggle(field) }
                        .accessibilityIdentifier(
                            field.kind == .favorite
                                ? "favorite-\(record.title)" : "indicator-\(record.title)-\(field.id)")
                } else {
                    ItemGlyph(symbol: field.indicatorSymbol).symbolVariant(selected ? .fill : .none)
                        .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.35))
                        .saturation(selected ? 1 : 0).opacity(selected ? 1 : 0.5)
                        .frame(width: 28, height: 28).accessibilityLabel(l.text(field.label))
                }
            }
        }
    }
    private func toggle(_ field: FieldDefinition) {
        guard var current = store.record(record.id) else { return }
        do {
            if field.kind == .favorite {
                current.favorite = !current.isFavorite
                if field.id != "__favorite" { current.values[field.id] = .flag(current.isFavorite) }
            } else {
                current.values[field.id] = .flag(!(current.values[field.id]?.flag ?? false))
            }
            try store.saveRecord(current, expectedRevision: current.revision)
        } catch { navigation.noticeKey = (error as? BlueError ?? .saveFailed).key }
    }
}
