import SwiftUI

struct EditClubView: View {
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case add(userId: UUID)
        case edit(UserClub)
    }

    let mode: Mode
    let onSave: (UserClub) -> Void

    @State private var brand: String
    @State private var name: String
    @State private var loft: String
    @State private var type: ClubType
    @State private var expectedCarry: String
    @State private var expectedTotal: String
    @State private var isActive: Bool

    private var title: String {
        switch mode {
        case .add:  return "Add Club"
        case .edit: return "Edit Club"
        }
    }
    private var userId: UUID {
        switch mode {
        case .add(let id): return id
        case .edit(let c): return c.userId
        }
    }
    private var originalClub: UserClub? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    init(mode: Mode, onSave: @escaping (UserClub) -> Void) {
        self.mode   = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _brand         = State(initialValue: "")
            _name           = State(initialValue: "")
            _loft           = State(initialValue: "")
            _type           = State(initialValue: .iron)
            _expectedCarry  = State(initialValue: "150")
            _expectedTotal  = State(initialValue: "160")
            _isActive       = State(initialValue: true)
        case .edit(let club):
            _brand         = State(initialValue: club.brand ?? "")
            _name           = State(initialValue: club.name)
            _loft           = State(initialValue: club.loftDegrees.map { String(format: "%.1f", $0) } ?? "")
            _type           = State(initialValue: club.type)
            _expectedCarry  = State(initialValue: String(club.expectedCarryYards))
            _expectedTotal  = State(initialValue: String(club.expectedTotalYards))
            _isActive       = State(initialValue: club.isActive)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        formSection
                        if case .edit = mode { activeToggle }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(BSTheme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundColor(BSTheme.electricCyan)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Club Details")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
                BSTextField(placeholder: "Brand (e.g. Titleist)", text: $brand, icon: "tag")
                    .textInputAutocapitalization(.words)
                BSTextField(placeholder: "Name (e.g. 7 Iron, TSR3 Driver)", text: $name, icon: "figure.golf")
                    .textInputAutocapitalization(.words)
            }

            // Type picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Club Type")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ClubType.allCases, id: \.self) { t in
                            Button {
                                type = t
                            } label: {
                                Text(t.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(type == t ? .black : BSTheme.textMuted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(type == t ? BSTheme.electricCyan : BSTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(
                                        type == t ? Color.clear : BSTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loft (°)").font(.system(size: 12)).foregroundColor(BSTheme.textMuted)
                    BSTextField(placeholder: "34.0", text: $loft)
                        .keyboardType(.decimalPad)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Carry (yd)").font(.system(size: 12)).foregroundColor(BSTheme.textMuted)
                    BSTextField(placeholder: "150", text: $expectedCarry)
                        .keyboardType(.numberPad)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total (yd)").font(.system(size: 12)).foregroundColor(BSTheme.textMuted)
                    BSTextField(placeholder: "160", text: $expectedTotal)
                        .keyboardType(.numberPad)
                }
                Spacer(minLength: 0)
            }
        }
        .premiumCard()
    }

    private var activeToggle: some View {
        HStack {
            Text("Club Active")
                .font(.system(size: 15))
                .foregroundColor(BSTheme.textPrimary)
            Spacer()
            Toggle("", isOn: $isActive)
                .tint(BSTheme.electricCyan)
        }
        .premiumCard(padding: 16)
    }

    private func save() {
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLoft = loft.trimmingCharacters(in: .whitespacesAndNewlines)
        let carry = Int(expectedCarry) ?? 0
        let total = Int(expectedTotal) ?? carry
        let loftValue = Double(trimmedLoft)
        var club = originalClub ?? UserClub(
            userId: userId,
            name: trimmedName,
            type: type,
            expectedCarryYards: carry,
            expectedTotalYards: total
        )
        club.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
        club.name = trimmedName
        club.loftDegrees = trimmedLoft.isEmpty ? nil : loftValue
        club.type = type
        club.expectedCarryYards = carry
        club.expectedTotalYards = total
        club.isActive = isActive
        onSave(club)
        dismiss()
    }
}
