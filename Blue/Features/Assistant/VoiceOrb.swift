import SwiftUI

struct VoiceOrb: View {
    let phase: LiveVoiceService.Phase
    let level: Double
    let muted: Bool

    @Environment(Localizer.self) private var l
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 188

    private var status: String {
        switch phase {
        case .idle, .failed: "voice.start"
        case .connecting: "voice.connecting"
        case .listening: "voice.listening"
        case .speaking: "voice.speaking"
        case .working: "character.working"
        case .muted: "voice.muted"
        }
    }

    var body: some View {
        Group {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let energy = muted ? 0.0 : phase == .speaking ? 1.0 : 0.3 + level * 0.6
                let pulse = reduceMotion ? 1 : 1 + 0.045 * energy * sin(time * 4)
                ZStack {
                    Circle().fill(.blue.opacity(0.16)).blur(radius: 24).scaleEffect(1.19)
                    Circle().fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.20, blue: 0.74), Color(red: 0.13, green: 0.36, blue: 0.98),
                            ],
                            startPoint: .bottomLeading, endPoint: .topTrailing)
                    )
                    ZStack {
                        Circle().fill(.cyan.opacity(0.82)).frame(width: diameter * 0.75)
                            .blur(radius: 22).offset(x: 53 * sin(time * 0.64), y: -44 + 25 * cos(time * 0.7))
                        Circle().fill(.indigo).frame(width: diameter * 0.7)
                            .blur(radius: 28).offset(x: -55 * cos(time * 0.48), y: 48)
                        Circle().fill(.white.opacity(0.65)).frame(width: diameter * 0.35)
                            .blur(radius: 30).offset(x: 46 * cos(time * 0.55), y: -72)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(Circle())
                    Circle().strokeBorder(.white.opacity(0.26), lineWidth: 1)
                    Image(systemName: muted ? "mic.slash" : phase == .working ? "ellipsis" : "waveform")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(.white)
                }
                .frame(width: min(232, diameter), height: min(232, diameter))
                .scaleEffect(pulse)
                .saturation(muted || phase == .failed ? 0.35 : 1)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l(status))
        .accessibilityIdentifier("liveVoiceOrb")
    }
}
