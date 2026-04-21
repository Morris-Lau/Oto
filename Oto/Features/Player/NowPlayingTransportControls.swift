import SwiftUI

struct PlayerControlsView: View {
    let track: Track
    let width: CGFloat
    var isLoading: Bool = false
    var onShowQueue: (() -> Void)? = nil
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var pendingSeekTarget: Double?
    @State private var player = PlayerService.shared

    private var isPersonalFM: Bool {
        player.playbackSource?.systemRecommendationKind == .personalFM
    }

    private var forwardDisabled: Bool {
        guard !player.queue.isEmpty else { return true }
        return false
    }

    private var playbackModeIconName: String {
        switch player.playbackMode {
        case .listLoop: return "repeat"
        case .singleLoop: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    private var displayTime: Double {
        if isDragging {
            return sliderValue
        }
        if let pending = pendingSeekTarget {
            return pending
        }
        return player.currentTime
    }

    var body: some View {
        VStack(spacing: 12) {
            bufferedSlider

            HStack {
                Text(formatTime(displayTime))
                    .font(.glassCaption)
                    .foregroundStyle(Color.glassSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .leading)
                Spacer()
                Text(formatTime(player.duration))
                    .font(.glassCaption)
                    .foregroundStyle(Color.glassSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 32) {
                Button {
                    player.cyclePlaybackMode()
                } label: {
                    Image(systemName: playbackModeIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.glassPrimary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(isPersonalFM || isLoading)

                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.glassPrimary)
                }
                .disabled(player.queue.isEmpty || (player.playbackMode == .listLoop && player.currentIndex <= 0) || isPersonalFM || isLoading)

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.glassPrimary)
                        .background(Circle().fill(.ultraThinMaterial))
                }

                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.glassPrimary)
                }
                .disabled(forwardDisabled || isLoading)

                Button {
                    onShowQueue?()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.glassPrimary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(onShowQueue == nil || isLoading)
            }
        }
        .frame(width: width)
        .onAppear {
            sliderValue = player.currentTime
        }
        .onChange(of: player.currentTime) { _, newValue in
            if let pending = pendingSeekTarget, abs(newValue - pending) < 0.5 {
                pendingSeekTarget = nil
            }
            if abs(newValue - sliderValue) > 1 {
                sliderValue = newValue
            }
        }
    }

    private var bufferedSlider: some View {
        let duration = player.duration
        let bufferedTime = player.bufferedTime

        return GeometryReader { geo in
            let totalWidth = geo.size.width
            let playRatio = min(CGFloat(displayTime / max(duration, 1)), 1.0)
            let bufferRatio = min(CGFloat(bufferedTime / max(duration, 1)), 1.0)
            let thumbRadius: CGFloat = 6
            let thumbX = min(max(totalWidth * playRatio, thumbRadius), totalWidth - thumbRadius)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.glassAccent.opacity(0.2))

                Capsule()
                    .fill(Color.glassAccent.opacity(0.4))
                    .frame(width: totalWidth * bufferRatio)

                Capsule()
                    .fill(Color.glassAccent)
                    .frame(width: totalWidth * playRatio)

                Circle()
                    .fill(Color.glassAccent)
                    .frame(width: 12, height: 12)
                    .position(x: thumbX, y: 2)
            }
            .frame(height: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = Double(gesture.location.x / totalWidth)
                        sliderValue = max(0, min(duration, ratio * duration))
                        isDragging = true
                    }
                    .onEnded { _ in
                        let target = sliderValue
                        pendingSeekTarget = target
                        isDragging = false
                        player.seek(to: target)
                    }
            )
        }
        .frame(height: 20)
        .padding(.horizontal, 20)
    }

    private func formatTime(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
