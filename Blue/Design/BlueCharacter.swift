import SwiftUI

struct BlueCharacter: View {
    var state: CharacterState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Localizer.self) private var l
    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: state == .idle ? 1.0 / 15 : 1.0 / 30, paused: reduceMotion || scenePhase != .active)
        ) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let scale = min(size.width / 64, size.height / 64)
                context.scaleBy(x: scale, y: scale)
                let breath = reduceMotion ? 0 : sin(time * 2) * 1.2
                let lean: Double = state == .thinking ? -5 : (state == .searching ? sin(time * 3) * 5 : 0)
                context.translateBy(x: lean, y: breath)
                let blue = Color(red: 0.16, green: 0.33, blue: 0.88)
                var body = Path()
                body.move(to: CGPoint(x: 20, y: 18))
                body.addCurve(
                    to: CGPoint(x: 48, y: 28), control1: CGPoint(x: 22, y: 4), control2: CGPoint(x: 49, y: 10))
                body.addCurve(
                    to: CGPoint(x: 45, y: 48), control1: CGPoint(x: 56, y: 38), control2: CGPoint(x: 52, y: 50))
                body.addCurve(
                    to: CGPoint(x: 17, y: 45), control1: CGPoint(x: 35, y: 54), control2: CGPoint(x: 11, y: 52))
                body.addCurve(
                    to: CGPoint(x: 20, y: 18), control1: CGPoint(x: 9, y: 35), control2: CGPoint(x: 15, y: 23))
                context.fill(body, with: .color(blue.opacity(0.12)))
                context.stroke(
                    body, with: .color(blue), style: StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
                func line(_ points: [CGPoint], width: Double = 2.4) {
                    var path = Path()
                    path.addLines(points)
                    context.stroke(
                        path, with: .color(blue),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                let raised = state == .success || state == .listening
                let working = state == .working ? sin(time * 12) * 4 : 0
                line([
                    CGPoint(x: 16, y: 32), CGPoint(x: 8, y: raised ? 17 : 39 + working),
                    CGPoint(x: 5, y: raised ? 20 : 35 + working),
                ])
                line([
                    CGPoint(x: 49, y: 31), CGPoint(x: 56, y: raised ? 16 : 38 - working),
                    CGPoint(x: 59, y: raised ? 19 : 35 - working),
                ])
                line([CGPoint(x: 25, y: 50), CGPoint(x: 23, y: 58), CGPoint(x: 18, y: 58)])
                line([CGPoint(x: 40, y: 50), CGPoint(x: 42, y: 57), CGPoint(x: 47, y: 57)])
                let blink = !reduceMotion && time.truncatingRemainder(dividingBy: 5) < 0.15
                let eyeY: Double = state == .thinking ? 25 : 29
                for x in [26.0, 38.0] {
                    if blink || state == .success {
                        line([CGPoint(x: x - 2, y: eyeY), CGPoint(x: x, y: eyeY - 2), CGPoint(x: x + 2, y: eyeY)])
                    } else {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: eyeY, width: 3, height: state == .listening ? 5 : 3.5)),
                            with: .color(blue))
                    }
                }
                let mouthY = state == .error ? 41.0 : 37.0
                line(
                    [
                        CGPoint(x: 29, y: mouthY), CGPoint(x: 33, y: state == .error ? 38 : 40),
                        CGPoint(x: 37, y: mouthY),
                    ], width: 1.8)
                if state == .searching {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: 43, y: 31, width: 12, height: 12)), with: .color(blue), lineWidth: 2)
                    line([CGPoint(x: 53, y: 41), CGPoint(x: 58, y: 47)])
                }
            }
        }
        .frame(width: 52, height: 56)
        .accessibilityLabel(l("character.\(state.rawValue)"))
    }
}

struct QuietButton: View {
    let key: String
    let symbol: String
    var action: () -> Void
    @Environment(Localizer.self) private var l
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityLabel(l(key))
    }
}

struct ErrorLine: View {
    let key: String?
    @Environment(Localizer.self) private var l
    var body: some View {
        if let key { Text(l(key)).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("errorMessage") }
    }
}

struct KeyboardDismissToolbar: ViewModifier {
    @Environment(Localizer.self) private var l
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(l("done")) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .accessibilityIdentifier("keyboardDone")
            }
        }
    }
}
