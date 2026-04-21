import CoreImage.CIFilterBuiltins
import SwiftUI

struct OtoLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = SessionStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BlurredBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                        qrLoginCard
                    }
                    .padding(OtoMetrics.screenPadding)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(String(localized: String.LocalizationValue("profile_login")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var qrLoginCard: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("profile_scan_title")
                    .font(.otoHeadline)
                    .foregroundStyle(Color.otoTextPrimary)

                Text(session.qrStatusText)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)

                if let qrURL = session.qrSession?.qrURL,
                   let qrImage = QRCodeImageRenderer.image(from: qrURL) {
                    HStack {
                        Spacer()
                        qrImage
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                        Spacer()
                    }
                }

                Button {
                    session.startQRCodeLogin()
                } label: {
                    OtoChip(isActive: true) {
                        Text(session.qrSession == nil ? String(localized: String.LocalizationValue("profile_generate_qr")) : String(localized: String.LocalizationValue("profile_regenerate_qr")))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OtoAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = SessionStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BlurredBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    if let profile = session.profile {
                        LiquidGlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 14) {
                                    accountAvatarView(profile)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.nickname)
                                            .font(.otoHeadline)
                                            .foregroundStyle(Color.otoTextPrimary)
                                        if !profile.signature.isEmpty {
                                            Text(profile.signature)
                                                .font(.otoCaption)
                                                .foregroundStyle(Color.otoTextSecondary)
                                                .lineLimit(4)
                                        }
                                    }
                                }

                                HStack(spacing: 10) {
                                    OtoChip(isActive: true) {
                                        Text("profile_logged_in")
                                    }

                                    Button("profile_logout") {
                                        Task { await session.logout() }
                                    }
                                    .font(.otoCaption)
                                    .foregroundStyle(Color.otoAccent)
                                }
                            }
                        }
                        .padding(OtoMetrics.screenPadding)
                    }
                }
            }
            .navigationTitle(String(localized: String.LocalizationValue("profile_account")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action_close") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accountAvatarView(_ profile: UserProfileSummary) -> some View {
        if profile.avatarURL.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.otoAccent)
                .frame(width: 56, height: 56)
        } else {
            RemoteImageView(urlString: profile.avatarURL, placeholderStyle: .avatar)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        }
    }
}

private enum QRCodeImageRenderer {
    static func image(from content: String) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
        #else
        return nil
        #endif
    }
}
