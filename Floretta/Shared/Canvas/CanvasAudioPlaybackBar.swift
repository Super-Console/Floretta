import AVKit
import SwiftUI

/// Native SwiftUI controls positioned over the node whose audio is currently playing.
struct CanvasAudioPlaybackBar: View {
    let player: AVPlayer
    let onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let duration = max(0, player.currentItem?.duration.seconds ?? 0)
            let current = max(0, player.currentTime().seconds)
            VStack(spacing: 4) {
                if player.currentItem?.status == .failed {
                    Label("音频文件无法播放", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                    Button {
                        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
                    } label: {
                        Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(player.timeControlStatus == .playing ? "暂停音频" : "播放音频")
                    Slider(value: Binding(
                        get: { min(current, duration) },
                        set: { player.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }
                    ), in: 0...max(duration, 0.01))
                    .disabled(duration <= 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭音频播放器")
                    }
                    HStack {
                        Text(Self.time(current))
                        Spacer()
                        Text(Self.time(duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .appleGlassChrome(.floatingPanel)
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
