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
                    .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.3))
                    .saturation(selected ? 1 : 0)

                    .frame(width: 44, height: 44)

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

extension FieldDefinition {
    /// Compatibility for saved starter schemas. New schemas carry their own display metadata.
    var inactiveStatus: String? {
        inactiveOptionID
            ?? options.first { ["wantWatch", "wantPlay", "wantTry", "wantVisit", "wantExplore"].contains($0.id) }?.id
    }
    func symbol(for option: FieldOption) -> String {
        if let icon = option.icon { return icon }
        switch option.id {
        case "watched": return "eye"
        case "watching", "playing": return "play"
        case "finished", "tried": return "checkmark.circle"
        case "visited": return "mappin"
        case "exploring": return "music.note"
        default: return indicatorSymbol
        }
    }
    var numberOptions: [Double] {
        let lower = minimum ?? 0
        let upper = maximum ?? (kind == .rating ? 10 : 100)
        let increment = step ?? (kind == .rating ? 0.5 : 1)
        guard lower.isFinite, upper.isFinite, increment > 0, upper >= lower else { return [] }
        return (0...min(1000, Int((upper - lower) / increment))).map { lower + Double($0) * increment }
    }
}

struct PropertyControl: View {
    let field: FieldDefinition
    let value: FieldValue?
    var filter = false
    var save: (FieldValue?) -> Void
    @Environment(Localizer.self) private var l
    @State private var showing = false
    var body: some View {
        Group {
            if field.kind.isBoolean {
                IndicatorControl(field: field, selected: value?.flag == true) { save(.flag(!(value?.flag ?? false))) }
            } else if field.kind == .status {
                HStack(spacing: 0) {
                    ForEach(field.options.filter { $0.id != field.inactiveStatus }) { option in
                        let selected = value?.text == option.id
                        Button {
                            save(
                                selected
                                    ? (filter ? nil : field.inactiveStatus.map(FieldValue.option)) : .option(option.id))
                        } label: {
                            ItemGlyph(symbol: field.symbol(for: option)).symbolVariant(selected ? .fill : .none).font(
                                .system(size: 20)
                            )
                            .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.3))
                            .saturation(selected ? 1 : 0)
                            .frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel(l.text(option.label))
                            .accessibilityValue(l(selected ? "yes" : "no"))
                            .accessibilityIdentifier("option-\(field.id)-\(option.id)")
                    }
                }
            } else {
                Button {
                    showing = true
                } label: {
                    Group {
                        if field.kind == .number || field.kind == .rating {
                            Text(value?.number.map(l.number) ?? "—").font(.title3.weight(.medium)).monospacedDigit()
                        } else if value != nil {
                            Text(l.value(value, field: field)).font(.subheadline).lineLimit(2)
                        } else {
                            ItemGlyph(symbol: field.indicatorSymbol).foregroundStyle(.tertiary)
                        }
                    }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(l.text(field.label))
                    .accessibilityValue(l.value(value, field: field)).accessibilityIdentifier("property-\(field.id)")
            }
        }
        .blueSheet(isPresented: $showing, title: l.text(field.label)) {
            VStack(alignment: .leading, spacing: 20) {
                if field.kind == .rating || field.kind == .number {
                    Picker(
                        l.text(field.label),
                        selection: Binding(get: { value?.number ?? field.minimum ?? 0 }, set: { save(.number($0)) })
                    ) {
                        ForEach(field.numberOptions, id: \.self) { number in Text(l.number(number)).tag(number) }
                    }.pickerStyle(.wheel).labelsHidden().accessibilityIdentifier("numberWheel")
                } else if field.kind == .date {
                    DatePicker(
                        l.text(field.label),
                        selection: Binding(
                            get: {
                                if case .date(let date) = value { return date }
                                return Date()
                            }, set: { save(.date($0)) }), displayedComponents: .date
                    ).datePickerStyle(.graphical)
                } else {
                    TextField(
                        l.text(field.label),
                        text: Binding(
                            get: { value?.text ?? "" },
                            set: { text in
                                save(
                                    text.isEmpty
                                        ? nil
                                        : field.kind == .tags
                                            ? .tags(
                                                text.split(separator: ",").map {
                                                    $0.trimmingCharacters(in: .whitespaces)
                                                }) : .text(text))
                            }), axis: .vertical
                    ).lineLimit(3...12)
                }
                if value != nil {
                    Button(l("filters.clear")) {
                        save(nil)
                        showing = false
                    }.frame(minHeight: 44)
                }
                Spacer()
            }.padding(.horizontal, 24)
        }
    }
}

struct RecordIndicators: View {
    let record: Record
    let collection: Collection
    var interactive = false
    var includeFavorite = true
    @Environment(LibraryStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    var body: some View {
        let fields =
            (includeFavorite ? [collection.fields.first { $0.kind == .favorite } ?? .favoriteIndicator] : [])
            + collection.fields.filter {
                $0.kind != .favorite && ($0.kind.isBoolean || $0.kind == .status || record.values[$0.id] != nil)
            }
        PropertyFlow { controls(fields) }
    }
    @ViewBuilder private func controls(_ fields: [FieldDefinition]) -> some View {
        ForEach(fields) { field in
            PropertyControl(
                field: field, value: field.kind == .favorite ? .flag(record.isFavorite) : record.values[field.id]
            ) { value in
                guard interactive, var fresh = store.record(record.id) else { return }
                if field.kind == .favorite { fresh.favorite = value?.flag ?? false }
                if field.id != "__favorite" { fresh.values[field.id] = value }
                do { try store.saveRecord(fresh, expectedRevision: fresh.revision) } catch {
                    navigation.noticeKey = (error as? BlueError ?? .saveFailed).key
                }
            }.disabled(!interactive)
        }
    }
}

struct PropertyFlow: Layout {
    var centered = false
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += min(size.width, width) + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[Int]] = [[]]
        var widths: [CGFloat] = [0]
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        for index in sizes.indices {
            let width = min(sizes[index].width, bounds.width)
            if !rows[rows.count - 1].isEmpty && widths[widths.count - 1] + spacing + width > bounds.width {
                rows.append([])
                widths.append(0)
            }
            let row = rows.count - 1
            if !rows[row].isEmpty { widths[row] += spacing }
            rows[row].append(index)
            widths[row] += width
        }
        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            var x = bounds.minX + (centered ? max(0, (bounds.width - widths[rowIndex]) / 2) : 0)
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
        }
    }
}
