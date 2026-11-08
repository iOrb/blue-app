import SwiftUI

/// A fixed heading above scrolling content; the scrim and drag handle dismiss it.
struct BlueSheet<Content: View>: View {
    let title: String
    let fitsContent: Bool
    var dismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var presentationID = UUID()
    @Environment(NavigationState.self) private var navigation
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture(perform: dismiss)
                    .accessibilityIdentifier("sheetBackdrop")
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Capsule().fill(.tertiary).frame(width: 36, height: 4)
                        if !title.isEmpty {
                            Text(title).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, title.isEmpty ? 4 : 14)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture().onChanged { offset = max(0, $0.translation.height) }
                                .onEnded { value in
                                    if value.translation.height > 70 || value.predictedEndTranslation.height > 180 {
                                        dismiss()
                                    }
                                    offset = 0
                                })
                    content().frame(maxWidth: .infinity, maxHeight: fitsContent ? nil : .infinity, alignment: .top)
                }
                .frame(maxWidth: 760).frame(height: fitsContent ? nil : geometry.size.height * 0.86)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: -5)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .padding(.top, fitsContent ? geometry.size.height * 0.18 : 0)
                .offset(y: offset)
                .accessibilityAction(.escape, dismiss)
            }
        }
        .onAppear { navigation.presentations.insert(presentationID) }
        .onDisappear { navigation.presentations.remove(presentationID) }
    }
}

extension View {
    func blueSheet<Content: View>(
        isPresented: Binding<Bool>, title: String, fitsContent: Bool = false, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            BlueSheet(
                title: title, fitsContent: fitsContent, dismiss: { isPresented.wrappedValue = false }, content: content
            )
            .presentationBackground(.clear)
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
    @State private var presentationID = UUID()
    @Environment(NavigationState.self) private var navigation
    let title: String
    var cancel: () -> Void
    var confirm: () -> Void
    @Environment(Localizer.self) private var l
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.title2.weight(.semibold))
                HStack {
                    Button(l("cancel"), action: cancel).frame(minHeight: 44)
                    Spacer()
                    Button(role: .destructive, action: confirm) { Label(l("delete"), systemImage: "minus") }.frame(
                        minHeight: 44
                    )
                    .accessibilityIdentifier("confirmDelete")
                }
            }.padding(28).frame(maxWidth: 350).background(
                Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28)
            ).padding(24)
            VStack {
                HStack {
                    Spacer()
                    Button(action: cancel) {
                        Image(systemName: "xmark").frame(width: 48, height: 48).background(
                            .regularMaterial, in: Circle())
                    }.accessibilityLabel(l("close")).accessibilityIdentifier("closeConfirmation")
                }
                Spacer()
            }.padding(20)
        }.accessibilityAction(.escape, cancel)
            .onAppear { navigation.presentations.insert(presentationID) }
            .onDisappear { navigation.presentations.remove(presentationID) }
    }
}
private struct BlueConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var confirm: () -> Void
    @State private var accepted = false
    func body(content: Content) -> some View {
        content.fullScreenCover(
            isPresented: $isPresented,
            onDismiss: {
                if accepted {
                    accepted = false
                    confirm()
                }
            },
            content: {
                BlueConfirmation(
                    title: title, cancel: { isPresented = false },
                    confirm: {
                        accepted = true
                        isPresented = false
                    }
                ).presentationBackground(.clear)
            })
    }
}
extension View {
    func blueConfirmation(isPresented: Binding<Bool>, title: String, confirm: @escaping () -> Void) -> some View {
        modifier(BlueConfirmationModifier(isPresented: isPresented, title: title, confirm: confirm))
    }
}
struct DetailHeader<Options: View>: View {
    var close: () -> Void
    @ViewBuilder var options: () -> Options
    @Environment(Localizer.self) private var l
    var body: some View {
        HStack {
            QuietButton(key: "back", symbol: "chevron.down", action: close).accessibilityIdentifier("detailBack")
            Spacer()
            Menu {
                options()
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .accessibilityLabel(l("options")).accessibilityIdentifier("detailOptions")
        }.padding(.horizontal, 16)
    }
}
struct PlainNoteBody: View {
    @Binding var text: String
    @Environment(Localizer.self) private var l
    var identifier = "noteBody"
    var body: some View {
        TextField(l("note.markdown"), text: $text, axis: .vertical)
            .lineLimit(8...1000).font(.body).frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityIdentifier(identifier)
    }
}
