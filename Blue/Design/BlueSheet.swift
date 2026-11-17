import SwiftUI

private struct BlueSheetSurfaceKey: EnvironmentKey {
    static let defaultValue = Color(uiColor: .systemBackground)
}

extension EnvironmentValues {
    var blueSheetSurface: Color {
        get { self[BlueSheetSurfaceKey.self] }
        set { self[BlueSheetSurfaceKey.self] = newValue }
    }
}

private struct BlueSheetDismissKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var blueSheetDismiss: (@MainActor () -> Void)? {
        get { self[BlueSheetDismissKey.self] }
        set { self[BlueSheetDismissKey.self] = newValue }
    }
}

struct BlueCloseButton: View {
    let action: () -> Void

    var body: some View {
        QuietButton(key: "close", symbol: "chevron.left", action: action)
            .glassEffect(.regular.interactive(), in: Circle())
    }
}

struct BlueDoneButton: View {
    let action: () -> Void

    var body: some View {
        QuietButton(key: "done", symbol: "checkmark", action: action)
            .glassEffect(.regular.interactive(), in: Circle())
    }
}

private struct BlueSheetHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BlueSheet<Content: View>: View {
    let title: String
    let ownHeader: Bool
    let initialHeight: CGFloat
    let allowsExpansion: Bool
    let close: @MainActor () -> Void
    @ViewBuilder var content: () -> Content
    @State private var measuredHeight: CGFloat = 0
    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var surface: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(uiColor: .systemBackground)
    }
    private var compactDetent: PresentationDetent {
        let height = measuredHeight > 0 ? min(560, max(188, measuredHeight + 60)) : initialHeight
        return .height(height.rounded(.up))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !ownHeader {
                BlueSheetHeader(title: title, close: close) { EmptyView() }
            }
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.blueSheetSurface, surface)
        .environment(\.blueSheetDismiss, close)
        .onPreferenceChange(BlueSheetHeight.self) { if $0 > 0 { measuredHeight = $0.rounded(.up) } }
        .presentationDetents(
            allowsExpansion ? [compactDetent, .large] : [compactDetent],
            selection: Binding(get: { expanded ? .large : compactDetent }, set: { expanded = $0 == .large })
        )
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.disabled)
        .presentationBackground(surface)
        .presentationCornerRadius(30)
        .accessibilityAction(.escape, close)
    }
}

extension View {
    func blueSheet<Content: View>(
        isPresented: Binding<Bool>, title: String, initialHeight: CGFloat = 380, ownHeader: Bool = false,
        allowsExpansion: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            BlueSheet(
                title: title, ownHeader: ownHeader, initialHeight: initialHeight, allowsExpansion: allowsExpansion,
                close: { isPresented.wrappedValue = false }, content: content
            )
        }
    }

    // Measure the intrinsic content inside a scroll view, independently of the current detent.
    func blueSheetContentSize() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: BlueSheetHeight.self, value: geometry.size.height)
            }
        }
    }
}

struct EditableMarkdown: View {
    @Binding var text: String
    @State private var editing = false
    @FocusState private var focused: Bool
    @Environment(Localizer.self) private var l
    var identifier = "noteBody"
    var body: some View {
        Group {
            if editing {
                TextEditor(text: $text).font(.body).frame(minHeight: 300).scrollContentBackground(.hidden)
                    .focused($focused).accessibilityLabel(l("note.markdown")).accessibilityIdentifier(identifier)
            } else {
                Group {
                    if text.isEmpty {
                        Text(l("note.markdown")).foregroundStyle(.tertiary).padding(.vertical, 20)
                    } else {
                        MarkdownView(text: $text)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).contentShape(Rectangle())
                .onTapGesture {
                    editing = true
                    focused = true
                }
                .accessibilityIdentifier("markdownPreview")
                .accessibilityAction {
                    editing = true
                    focused = true
                }
            }
        }.onChange(of: focused) { _, value in if !value { editing = false } }
    }
}

struct BlueConfirmation: View {
    let title: String
    let visible: Bool
    var cancel: () -> Void
    var confirm: () -> Void
    @Environment(Localizer.self) private var l
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.28 : 0).ignoresSafeArea().onTapGesture(
                perform: cancel)
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(l("delete.irreversible")).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Button(l("cancel"), action: cancel).frame(minHeight: 44)
                    Spacer()
                    Button(role: .destructive, action: confirm) { BlueDeleteLabel() }.frame(
                        minHeight: 44
                    )
                    .foregroundStyle(.red).accessibilityIdentifier("confirmDelete")
                }
            }.padding(28).frame(maxWidth: 350).background(
                Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28)
            ).padding(24).scaleEffect(visible || reduceMotion ? 1 : 0.96).opacity(visible ? 1 : 0)
            VStack {
                HStack {
                    Spacer()
                    Button(action: cancel) {
                        Image(systemName: "xmark").frame(width: 48, height: 48).background(
                            .regularMaterial, in: Circle())
                    }.accessibilityLabel(l("close")).accessibilityIdentifier("closeConfirmation")
                }
                Spacer()
            }.padding(20).opacity(visible ? 1 : 0)
        }
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .accessibilityAction(.escape, cancel)
    }
}
private struct BlueConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var confirm: () -> Void
    @State private var mounted = false
    @State private var visible = false
    @State private var accepted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .fullScreenCover(
                isPresented: $mounted,
                onDismiss: {
                    if accepted { confirm() }
                    accepted = false
                }
            ) {
                BlueConfirmation(
                    title: title, visible: visible,
                    cancel: { close(accepted: false) }, confirm: { close(accepted: true) }
                )
                .presentationBackground(.clear)
                .onAppear { withAnimation(animation) { visible = true } }
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    setMounted(true)
                } else if mounted {
                    close(accepted: false)
                }
            }
    }

    private var animation: Animation { .easeInOut(duration: reduceMotion ? 0.12 : 0.22) }

    private func close(accepted: Bool) {
        guard visible else { return }
        self.accepted = accepted
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            visible = false
        } completion: {
            setMounted(false)
            isPresented = false
        }
    }

    private func setMounted(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { mounted = value }
    }
}

extension View {
    func blueConfirmation(isPresented: Binding<Bool>, title: String, confirm: @escaping () -> Void) -> some View {
        modifier(BlueConfirmationModifier(isPresented: isPresented, title: title, confirm: confirm))
    }
}
struct BlueSheetHeader<Actions: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.title2.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 52)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sheetTitle")
            }
            HStack {
                BlueCloseButton(action: close).accessibilityIdentifier("closeSheet")
                Spacer()
                actions()
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
    }
}

struct DetailHeader<Options: View>: View {
    var title = ""
    var close: () -> Void
    @ViewBuilder var options: () -> Options
    @Environment(Localizer.self) private var l
    var body: some View {
        BlueSheetHeader(title: title, close: close) {
            Menu {
                options()
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(BlueRowPress(shape: AnyShape(Circle())))
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(l("options")).accessibilityIdentifier("detailOptions")
        }
    }
}
struct PlainNoteBody: View {
    @Binding var text: String
    @Environment(Localizer.self) private var l
    var identifier = "noteBody"
    var minimumLines = 8
    var body: some View {
        TextField(l("note.markdown"), text: $text, axis: .vertical)
            .lineLimit(minimumLines...1000).font(.body).frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityIdentifier(identifier)
    }
}
