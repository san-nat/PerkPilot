import SwiftUI

// MARK: - Cupertino design tokens
//
// One home for the app's Apple-esque visual language: generous radii,
// hairline separators, adaptive surfaces, and the per-card metal finishes.
// Everything here adapts to light/dark automatically — no hard-coded
// light-only palettes.

enum PPTheme {
    // MARK: Shape
    static let bentoRadius: CGFloat = 22
    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 999
    static let gridSpacing: CGFloat = 12
    static let screenPad: CGFloat = 16

    // MARK: Surfaces
    /// Bento tile fill — the classic secondary grouped background.
    static var tileBackground: Color { Color(.secondarySystemGroupedBackground) }
    static var pageBackground: Color { Color(.systemGroupedBackground) }
    static var hairline: Color { Color.primary.opacity(0.08) }

    // MARK: Accent
    /// Champagne-gold accent for progress + highlights. Warmer in dark mode.
    static let gold = dynamic(
        light: Color(red: 0.60, green: 0.44, blue: 0.13),
        dark: Color(red: 0.96, green: 0.76, blue: 0.36)
    )
    static let success = Color.green

    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Hex colors

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Card metal finishes
//
// "Tactile luxury with digital precision": each card renders as a heavy-metal
// card with a per-issuer metallic gradient, diagonal sheen, and embossed type.

struct MetalSpec {
    var gradient: [Color]
    var foreground: Color
    /// Sheen overlay strength (0…1).
    var sheen: Double
}

enum CardMetal {
    static func spec(for stableId: String) -> MetalSpec {
        switch stableId {
        case "amex-platinum":
            // Brushed platinum silver.
            return MetalSpec(
                gradient: [Color(hex: "F4F7FA"), Color(hex: "C6D0DC"), Color(hex: "98A5B6"), Color(hex: "DEE5ED")],
                foreground: Color(hex: "1E2A3A"), sheen: 0.55
            )
        case "chase-sapphire-reserve":
            // Deep sapphire.
            return MetalSpec(
                gradient: [Color(hex: "123A63"), Color(hex: "0A2540"), Color(hex: "0B1E36")],
                foreground: .white, sheen: 0.35
            )
        case "chase-sapphire-preferred":
            // Brighter sapphire blue.
            return MetalSpec(
                gradient: [Color(hex: "2E6BD8"), Color(hex: "1B4F9C"), Color(hex: "163A75")],
                foreground: .white, sheen: 0.35
            )
        case "chase-ink-business-preferred":
            // Ink black, charcoal sheen.
            return MetalSpec(
                gradient: [Color(hex: "3A4048"), Color(hex: "17191D"), Color(hex: "2B2F36")],
                foreground: .white, sheen: 0.4
            )
        case "chase-ink-business-unlimited":
            // Graphite.
            return MetalSpec(
                gradient: [Color(hex: "4A515A"), Color(hex: "22252B"), Color(hex: "3A3F47")],
                foreground: .white, sheen: 0.4
            )
        case "delta-skymiles-reserve":
            // Delta widget red.
            return MetalSpec(
                gradient: [Color(hex: "B3122E"), Color(hex: "7A0E1E"), Color(hex: "5C0A16")],
                foreground: .white, sheen: 0.35
            )
        case "robinhood-gold":
            // Champagne gold.
            return MetalSpec(
                gradient: [Color(hex: "F6D47C"), Color(hex: "D9A441"), Color(hex: "8A5E1B")],
                foreground: Color(hex: "3A2A0E"), sheen: 0.5
            )
        case "costco-anywhere-visa":
            // Costco crimson.
            return MetalSpec(
                gradient: [Color(hex: "E0394F"), Color(hex: "C8102E"), Color(hex: "8E0B20")],
                foreground: .white, sheen: 0.35
            )
        case "chase-prime-visa":
            // Prime midnight navy.
            return MetalSpec(
                gradient: [Color(hex: "1B4D7A"), Color(hex: "0F2B46"), Color(hex: "0A1C30")],
                foreground: .white, sheen: 0.35
            )
        case "sams-club-mastercard":
            // Sam's Club blue.
            return MetalSpec(
                gradient: [Color(hex: "2E86D6"), Color(hex: "0B5CAD"), Color(hex: "084A8C")],
                foreground: .white, sheen: 0.35
            )
        case "southwest-premier":
            // Southwest canyon blue.
            return MetalSpec(
                gradient: [Color(hex: "1F5FBF"), Color(hex: "0F3B8C"), Color(hex: "0A2A5E")],
                foreground: .white, sheen: 0.35
            )
        case "chase-freedom-unlimited":
            // Brushed steel blue.
            return MetalSpec(
                gradient: [Color(hex: "DCE8FA"), Color(hex: "9DB9DE"), Color(hex: "7A9CCB")],
                foreground: Color(hex: "1B2F4D"), sheen: 0.5
            )
        default:
            // Graphite fallback for user-added cards.
            return MetalSpec(
                gradient: [Color(hex: "4A515A"), Color(hex: "26292F"), Color(hex: "3A3F47")],
                foreground: .white, sheen: 0.4
            )
        }
    }
}

// MARK: - MetalCardView

/// A premium heavy-metal credit card rendering: metallic gradient, diagonal
/// sheen, hairline edge, EMV chip, and embossed-style type.
struct MetalCardView: View {
    var stableId: String
    var cardName: String
    var issuer: String
    var feeDisplay: String
    var compact: Bool = false

    init(stableId: String, cardName: String, issuer: String, feeDisplay: String, compact: Bool = false) {
        self.stableId = stableId
        self.cardName = cardName
        self.issuer = issuer
        self.feeDisplay = feeDisplay
        self.compact = compact
    }

    init(card: CardItem, compact: Bool = false) {
        self.init(
            stableId: card.stableId,
            cardName: card.canonicalName,
            issuer: card.issuer,
            feeDisplay: card.annualFeeDisplay,
            compact: compact
        )
    }

    var body: some View {
        let spec = CardMetal.spec(for: stableId)
        let radius = compact ? 10.0 : 14.0
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(
                    colors: spec.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            // Diagonal sheen — the "light across brushed metal" pass.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(spec.sheen * 0.6), location: 0),
                        .init(color: .white.opacity(0), location: 0.45),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            // Hairline machined edge.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)

            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                HStack(alignment: .top) {
                    Text(issuer.uppercased())
                        .font(compact ? .caption2 : .caption)
                        .fontWeight(.semibold)
                        .tracking(1.5)
                        .opacity(0.9)
                    Spacer()
                    ChipView()
                }
                Spacer()
                // Embossed card name: tight shadow sells the raised type.
                Text(cardName)
                    .font(compact ? .subheadline : .headline)
                    .fontWeight(.bold)
                    .lineLimit(compact ? 1 : 2)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                if !compact {
                    Text(feeDisplay)
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .padding(compact ? 10 : 16)
            .foregroundStyle(spec.foreground)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(
            color: .black.opacity(0.25),
            radius: compact ? 4 : 10,
            x: 0, y: compact ? 2 : 6
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cardName), \(issuer)")
    }
}

/// Simplified EMV chip.
struct ChipView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(
                colors: [.white.opacity(0.8), .white.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 30, height: 23)
            .overlay(
                VStack(spacing: 5) {
                    Rectangle().fill(.black.opacity(0.25)).frame(height: 1)
                    Rectangle().fill(.black.opacity(0.25)).frame(height: 1)
                }
                .padding(.horizontal, 4)
            )
    }
}

// MARK: - BentoTile

/// Apple's go-to summary container: a rounded, softly-shadowed tile on the
/// secondary grouped background with a hairline stroke.
struct BentoTile<Content: View>: View {
    var minHeight: CGFloat = 118
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(PPTheme.screenPad)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(
                PPTheme.tileBackground,
                in: RoundedRectangle(cornerRadius: PPTheme.bentoRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PPTheme.bentoRadius, style: .continuous)
                    .stroke(PPTheme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

/// Standard stat layout inside a bento tile.
struct BentoStat: View {
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Spacer(minLength: 2)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MetalCardView(
            stableId: "amex-platinum",
            cardName: "American Express Platinum Card",
            issuer: "American Express",
            feeDisplay: "$895"
        )
        .frame(width: 320)
        HStack(spacing: 12) {
            BentoTile {
                BentoStat(
                    title: "Credits used",
                    value: "7/12",
                    subtitle: "Across all cards",
                    systemImage: "checkmark.circle.fill",
                    tint: PPTheme.gold
                )
            }
            BentoTile {
                BentoStat(
                    title: "Hidden gems",
                    value: "32",
                    subtitle: "Lesser-known tricks",
                    systemImage: "lightbulb.fill",
                    tint: .yellow
                )
            }
        }
        .frame(height: 150)
    }
    .padding()
    .background(PPTheme.pageBackground)
}
