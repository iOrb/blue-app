import SwiftUI

/// A fixed heading above scrolling content; the scrim and drag handle dismiss it.
struct BlueSheet<Content: View>: View {
    let title: String
    var dismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var offset: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18).ignoresSafeArea().onTapGesture(perform: dismiss)
                    .accessibilityIdentifier("sheetBackdrop")
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Capsule().fill(.tertiary).frame(width: 36, height: 4)
                        if !title.isEmpty {
                            Text(title).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 18)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture().onChanged { offset = max(0, $0.translation.height) }
                                .onEnded { value in
                                    if value.translation.height > 70 || value.predictedEndTranslation.height > 180 {
                                        dismiss()
                                    }
                                    offset = 0
                                })
                    content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: 760).frame(height: geometry.size.height * 0.86)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(Color(uiColor: .systemBackground)).ignoresSafeArea(.container, edges: .bottom)
                }
                .offset(y: offset)
                .accessibilityAction(.escape, dismiss)
            }
        }
    }
}

extension View {
    func blueSheet<Content: View>(
        isPresented: Binding<Bool>, title: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            BlueSheet(title: title, dismiss: { isPresented.wrappedValue = false }, content: content)
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
