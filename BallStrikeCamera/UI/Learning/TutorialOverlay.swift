import SwiftUI

// MARK: - Anchor plumbing

private struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialAnchorID: CGRect] = [:]
    static func reduce(value: inout [TutorialAnchorID: CGRect],
                       nextValue: () -> [TutorialAnchorID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this element's frame to the guided tour so it can be spotlit.
    /// Measured in `.global` (physical screen) space so it lines up with the
    /// full-screen, safe-area-ignoring overlay regardless of where the element
    /// lives in the hierarchy.
    func tutorialAnchor(_ id: TutorialAnchorID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TutorialAnchorKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        )
    }

    /// Installed once on the shell root: collects anchor frames into the
    /// controller and hosts the overlay above everything.
    func tutorialHost(_ controller: TutorialController) -> some View {
        onPreferenceChange(TutorialAnchorKey.self) { controller.updateAnchors($0) }
            .overlay {
                if controller.isActive {
                    TutorialOverlayView().environmentObject(controller)
                        .transition(.opacity)
                }
            }
    }
}

// MARK: - Overlay

/// Full-screen dim with a spotlight cut-out around the current step's target and
/// a caption card. Tapping anywhere (or Next) advances; Skip ends the tour.
struct TutorialOverlayView: View {
    @EnvironmentObject var tutorial: TutorialController

    private let pad: CGFloat = 8          // spotlight breathing room around target
    private let corner: CGFloat = 14
    private let cardWidth: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            let step = tutorial.currentStep
            let rect = spotlightRect(in: geo.size)

            ZStack {
                // Dim + cut-out
                Color.black.opacity(0.74)
                    .reverseMask {
                        if let r = rect {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .frame(width: r.width, height: r.height)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }

                // Highlight ring around the target
                if let r = rect {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(TCTheme.gold, lineWidth: 2)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                        .shadow(color: TCTheme.gold.opacity(0.5), radius: 8)
                }

                // Caption card
                if let step {
                    captionCard(step)
                        .frame(width: cardWidth)
                        .position(cardPosition(for: rect, in: geo.size))
                }
            }
            .animation(.easeInOut(duration: 0.28), value: tutorial.index)
        }
        .ignoresSafeArea()
    }

    // MARK: Spotlight geometry

    private func spotlightRect(in size: CGSize) -> CGRect? {
        guard let raw = tutorial.currentAnchorRect else { return nil }
        let r = raw.insetBy(dx: -pad, dy: -pad)
        // Clamp inside the screen so the ring never draws off-edge.
        let x = max(0, r.minX)
        let y = max(0, r.minY)
        let w = min(size.width, r.maxX) - x
        let h = min(size.height, r.maxY) - y
        guard w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Place the card opposite the spotlight so it never covers the target.
    private func cardPosition(for rect: CGRect?, in size: CGSize) -> CGPoint {
        guard let rect else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let cardHalf: CGFloat = 92
        let below = rect.maxY + 24 + cardHalf
        let above = rect.minY - 24 - cardHalf
        // Prefer the roomier side.
        let spaceBelow = size.height - rect.maxY
        let y: CGFloat = spaceBelow > 220 ? below : above
        let clampedY = min(max(cardHalf + 24, y), size.height - cardHalf - 24)
        return CGPoint(x: size.width / 2, y: clampedY)
    }

    // MARK: Card

    private func captionCard(_ step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)

            Text(step.body)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                // Progress dots
                HStack(spacing: 5) {
                    ForEach(0..<tutorial.steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == tutorial.index ? TCTheme.gold : TCTheme.textMuted.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer(minLength: 0)

                Button("Skip") { tutorial.skip() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .buttonStyle(.plain)

                Button {
                    advance()
                } label: {
                    Text(tutorial.isLastStep ? "Done" : "Next")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(TCTheme.gold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TCTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 18, x: 0, y: 8)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.28)) { tutorial.advance() }
    }
}

// MARK: - Reverse mask helper

private extension View {
    /// Punches a hole in this view using `mask` shape (destination-out blend).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .center) {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}
