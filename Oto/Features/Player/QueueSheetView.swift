import SwiftUI

struct QueueSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = PlayerService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BlurredBackground()

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                                queueRow(track: track, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .onAppear {
                        scrollQueueToCurrentItem(proxy: proxy)
                    }
                    .onChange(of: player.currentIndex) { _, _ in
                        scrollQueueToCurrentItem(proxy: proxy)
                    }
                }
            }
            .navigationTitle(String(localized: String.LocalizationValue("nav_up_next")))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        player.clearQueue()
                        dismiss()
                    } label: {
                        Text("action_clear_queue")
                    }
                    .disabled(player.queue.isEmpty)
                }
            }
        }
    }

    private func scrollQueueToCurrentItem(proxy: ScrollViewProxy) {
        let idx = player.currentIndex
        guard idx >= 0, idx < player.queue.count else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(idx, anchor: .center)
        }
    }

    @ViewBuilder
    private func queueRow(track: Track, index: Int) -> some View {
        let isCurrent = index == player.currentIndex

        Button {
            if !isCurrent {
                player.jumpTo(index: index)
            }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(urlString: track.coverURL)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if isCurrent {
                            Text("queue_now_badge")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.otoAccent)
                                )
                        }
                        Text(track.title)
                            .font(.otoHeadline)
                            .foregroundStyle(Color.otoTextPrimary)
                            .lineLimit(1)
                    }
                    Text(track.artist)
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isCurrent, player.isPlaying {
                    OtoInlinePlayingIndicator()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCurrent ? Color.otoAccent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
