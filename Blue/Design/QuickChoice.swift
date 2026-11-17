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
    var compact = false
    var action: () -> Void
    @Environment(Localizer.self) private var l
    var body: some View {
        PropertyButton(color: field.indicatorColor, action: action) {
            HStack(spacing: 9) {
                ItemGlyph(symbol: field.indicatorSymbol)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: compact ? 16 : 23, weight: .medium))
                    .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.3))
                    .saturation(selected ? 1 : 0)

                    .frame(width: compact ? 34 : 44, height: 44)

                if showsLabel { Text(l.text(field.label)).font(.subheadline).foregroundStyle(.primary) }
            }.contentShape(Rectangle())
        }.frame(minWidth: compact ? 34 : 44, minHeight: 44).contentShape(Rectangle())
            .accessibilityLabel(
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

private struct PropertyButton<Label: View>: View {
    let color: Color
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var burst: PropertyBurst?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if !reduceMotion { burst = PropertyBurst() }
            action()
        } label: {
            label()
        }
        .buttonStyle(PropertyPress())
        .overlay {
            if let burst {
                burst.view(color: color)
                    .frame(width: 96, height: 96)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task(id: burst?.id) {
            guard let id = burst?.id else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                if burst?.id == id { burst = nil }
            } catch {}
        }
    }
}

private struct PropertyPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.primary.opacity(0.08) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.19, bounce: 0.28), value: configuration.isPressed)
    }
}

private struct PropertyBurst {
    struct Particle {
        let angle: Double
        let offset: Double
        let distance: Double
        let size: Double
    }

    let id = UUID()
    let start = Date()
    let particles = (0..<7).map { index in
        Particle(
            angle: Double(index) * 2 * .pi / 7 + .random(in: -0.38...0.38),
            offset: .random(in: 6...13),
            distance: .random(in: 15...29),
            size: .random(in: 1.6...3.5)
        )
    }

    func view(color: Color) -> some View {
        TimelineView(.animation) { timeline in
            let progress = min(1, max(0, timeline.date.timeIntervalSince(start) / 0.35))
            let travel = 1 - (1 - progress) * (1 - progress)
            Canvas { context, size in
                for particle in particles {
                    let radius = particle.offset + particle.distance * travel
                    let diameter = particle.size * (1 - 0.45 * progress)
                    let center = CGPoint(
                        x: size.width / 2 + cos(particle.angle) * radius,
                        y: size.height / 2 + sin(particle.angle) * radius
                    )
                    let bounds = CGRect(
                        x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: bounds), with: .color(color.opacity(0.9 * (1 - progress))))
                }
            }
        }
    }
}

struct PropertyControl: View {
    let field: FieldDefinition
    let value: FieldValue?
    var filter = false
    var labeled = false
    var compact = false
    var statusOption: FieldOption?
    var save: (FieldValue?) -> Void
    @Environment(Localizer.self) private var l
    @ScaledMetric(relativeTo: .caption2) private var captionSize = 9.0
    @State private var showing = false
    var body: some View {
        Group {
            if field.kind.isBoolean {
                VStack(spacing: 4) {
                    IndicatorControl(field: field, selected: value?.flag == true, compact: compact) {
                        save(.flag(!(value?.flag ?? false)))
                    }
                    .background(
                        labeled ? Color.secondary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    if labeled { fieldCaption(l.text(field.label)) }
                }
            } else if field.kind == .status {
                HStack(alignment: .top, spacing: compact ? 1 : 7) {
                    ForEach(
                        field.options.filter {
                            $0.id != field.inactiveStatus && (statusOption == nil || statusOption?.id == $0.id)
                        }
                    ) { option in
                        let selected = value?.text == option.id
                        PropertyButton(color: field.indicatorColor) {
                            save(
                                selected
                                    ? (filter ? nil : field.inactiveStatus.map(FieldValue.option)) : .option(option.id))
                        } label: {
                            VStack(spacing: 4) {
                                ItemGlyph(symbol: field.symbol(for: option))
                                    .symbolVariant(selected ? .fill : .none).font(.system(size: compact ? 16 : 23))
                                    .foregroundStyle(selected ? field.indicatorColor : Color.secondary.opacity(0.55))
                                    .saturation(selected ? 1 : 0)
                                    .frame(width: compact ? 34 : 44, height: 44)
                                    .background(
                                        labeled ? Color.secondary.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                                if labeled { fieldCaption(l.text(option.label)) }
                            }
                        }.accessibilityLabel(l.text(option.label))
                            .accessibilityValue(l(selected ? "yes" : "no"))
                            .accessibilityIdentifier("option-\(field.id)-\(option.id)")
                    }
                }
            } else {
                PropertyButton(color: field.indicatorColor) {
                    showing = true
                } label: {
                    VStack(spacing: 4) {
                        Group {
                            if field.kind == .number || field.kind == .rating {
                                if let number = value?.number {
                                    Text(l.number(number)).font(
                                        compact ? .footnote.weight(.medium) : .title3.weight(.medium)
                                    ).monospacedDigit()
                                } else {
                                    Circle().fill(Color.secondary.opacity(0.72)).frame(width: 4, height: 4)
                                }
                            } else if value != nil && !compact {
                                Text(l.value(value, field: field)).font(.subheadline).lineLimit(2)
                            } else {
                                ItemGlyph(symbol: field.indicatorSymbol).foregroundStyle(.tertiary)
                            }
                        }.frame(width: labeled ? 44 : nil, height: labeled ? 44 : nil)
                            .frame(minWidth: compact ? 34 : 44, minHeight: 44).contentShape(Rectangle())
                            .background(
                                labeled ? Color.secondary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12)
                            )
                        if labeled { fieldCaption(l.text(field.label)) }
                    }
                }.accessibilityLabel(l.text(field.label))
                    .accessibilityValue(l.value(value, field: field)).accessibilityIdentifier("property-\(field.id)")
            }
        }
        .blueSheet(isPresented: $showing, title: l.text(field.label), initialHeight: 280) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if field.kind == .rating || field.kind == .number {
                        Picker(
                            l.text(field.label),
                            selection: Binding(get: { value?.number ?? field.minimum ?? 0 }, set: { save(.number($0)) })
                        ) {
                            ForEach(field.numberOptions, id: \.self) { number in Text(l.number(number)).tag(number) }
                        }.pickerStyle(.wheel).labelsHidden().frame(height: 160).clipped()
                            .accessibilityIdentifier("numberWheel")
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
                .blueSheetContentSize()
            }.scrollDismissesKeyboard(.interactively)
        }
    }
    private func fieldCaption(_ text: String) -> some View {
        Text(text).font(.system(size: captionSize)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
            .frame(width: 68, alignment: .top)
            .accessibilityHidden(true)
    }

}

struct RecordIndicators: View {
    let record: Record
    let collection: Collection
    var interactive = false
    var includeFavorite = true
    var labeled = false
    var compact = false
    @Environment(LibraryStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    var body: some View {
        let fields =
            (includeFavorite ? [collection.fields.first { $0.kind == .favorite } ?? .favoriteIndicator] : [])
            + collection.fields.filter {
                $0.kind != .favorite
                    && ($0.kind.isBoolean || $0.kind == .status || $0.kind == .number || $0.kind == .rating
                        || record.values[$0.id] != nil)
            }
        PropertyFlow(trailing: compact, spacing: compact ? 2 : 6) { controls(fields) }
    }
    @ViewBuilder private func controls(_ fields: [FieldDefinition]) -> some View {
        ForEach(fields) { field in
            PropertyControl(
                field: field, value: field.kind == .favorite ? .flag(record.isFavorite) : record.values[field.id],
                labeled: labeled, compact: compact
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
    var trailing = false
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
            let remaining = max(0, bounds.width - widths[rowIndex])
            var x = bounds.minX + (trailing ? remaining : centered ? remaining / 2 : 0)
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
        }
    }
}
