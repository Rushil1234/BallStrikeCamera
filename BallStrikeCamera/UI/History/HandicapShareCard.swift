import SwiftUI
import UIKit

// MARK: - Verified Handicap share card

/// The shareable handicap card. Fixed brand-dark palette (TCTheme.capture*) so
/// it renders identically in any chat, light mode included. The gold "verified"
/// seal appears only when at least one counted round was attested by a playing
/// partner — the seal means peer-attested, nothing more.
struct HandicapShareCardView: View {
    let indexString: String       // e.g. "12.4" or "+1.2"
    let usedCount: Int            // K differentials averaged
    let totalCount: Int           // rounds in the last-20 window
    let attestedCount: Int        // counted rounds attested by partners

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    private var verified: Bool { attestedCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            TCWordmark(size: 22, onDark: true)
                .padding(.top, 26)

            if verified {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("TRUE CARRY VERIFIED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                }
                .foregroundColor(TCTheme.captureGold)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(TCTheme.captureGold.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(TCTheme.captureGold.opacity(0.4), lineWidth: 1))
                .padding(.top, 18)
            }

            Text("HANDICAP INDEX")
                .font(.system(size: 12, weight: .bold))
                .tracking(2.2)
                .foregroundColor(TCTheme.captureBone.opacity(0.55))
                .padding(.top, verified ? 22 : 34)

            Text(indexString)
                .font(.system(size: 76, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.captureBone)
                .padding(.top, 2)

            VStack(spacing: 5) {
                Text("Best \(usedCount) of last \(totalCount) round\(totalCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.captureSilver)
                if verified {
                    Text("\(attestedCount) attested by playing partners")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.captureGold)
                }
            }
            .padding(.top, 14)

            Rectangle()
                .fill(TCTheme.captureBone.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 44)
                .padding(.top, 24)

            HStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: Date()))
                Text("·")
                Text("truecarrygolf.com")
            }
            .font(.system(size: 11))
            .foregroundColor(TCTheme.captureBone.opacity(0.45))
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .frame(width: 340)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.137, green: 0.196, blue: 0.157),
                        TCTheme.captureBg,
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                // Soft bone glow behind the number, echoing the brand vignette.
                RadialGradient(
                    colors: [TCTheme.captureBone.opacity(0.08), .clear],
                    center: .init(x: 0.5, y: 0.42),
                    startRadius: 10, endRadius: 240
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TCTheme.captureGold.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Renders the card to a UIImage for the share sheet (3× for crisp chat previews).
@MainActor
func renderHandicapCard(indexString: String, usedCount: Int, totalCount: Int, attestedCount: Int) -> UIImage? {
    let card = HandicapShareCardView(
        indexString: indexString,
        usedCount: usedCount,
        totalCount: totalCount,
        attestedCount: attestedCount
    )
    .padding(14) // margin so the rounded corners aren't clipped by renderers
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    renderer.isOpaque = false
    return renderer.uiImage
}
