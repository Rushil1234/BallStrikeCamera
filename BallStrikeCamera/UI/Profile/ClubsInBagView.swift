import SwiftUI

struct ClubsInBagView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm: ClubBagViewModel
    @State private var showAddClub = false
    @State private var editingClub: UserClub? = nil
    @State private var isEditMode = false
    private let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId = userId
        _vm = StateObject(wrappedValue: ClubBagViewModel(userId: userId, backend: backend))
    }

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            Group {
                if vm.isLoading {
                    ProgressView()
                        .tint(BSTheme.electricCyan)
                } else if vm.clubs.isEmpty {
                    emptyState
                } else {
                    clubList
                }
            }
        }
        .navigationTitle("Clubs in Bag")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                    }
                }
                .foregroundColor(BSTheme.textMuted)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button(isEditMode ? "Done" : "Edit") {
                        isEditMode.toggle()
                    }
                    .foregroundColor(BSTheme.electricCyan)
                    Button { showAddClub = true } label: {
                        Image(systemName: "plus")
                            .foregroundColor(BSTheme.electricCyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddClub) {
            EditClubView(mode: .add(userId: userId)) { newClub in
                Task { await vm.addClub(newClub) }
            }
        }
        .sheet(item: $editingClub) { club in
            EditClubView(mode: .edit(club)) { updated in
                Task { await vm.updateClub(updated) }
            }
        }
        .task { await vm.load() }
    }

    private var clubList: some View {
        List {
            ForEach(vm.clubs) { club in
                ClubRow(club: club)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onTapGesture { editingClub = club }
            }
            .onMove { vm.move(from: $0, to: $1) }
            .onDelete { idxs in
                for idx in idxs {
                    let id = vm.clubs[idx].id
                    Task { await vm.deleteClub(id: id) }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.golf")
                .font(.system(size: 48))
                .foregroundColor(BSTheme.textMuted)
            Text("No clubs yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(BSTheme.textPrimary)
            Text("Tap + to add clubs to your bag.")
                .font(.system(size: 14))
                .foregroundColor(BSTheme.textMuted)
            Button { showAddClub = true } label: {
                Text("Add Clubs")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(BSTheme.electricCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Club Row

private struct ClubRow: View {
    let club: UserClub

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BSTheme.fairwayGreen.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: club.type.icon)
                    .font(.system(size: 16))
                    .foregroundColor(BSTheme.fairwayGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(club.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                if let brand = club.brand?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !brand.isEmpty {
                    Text(brand)
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textSecondary)
                }
                Text(detailText)
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(BSTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
        .padding(.vertical, 3)
    }

    private var detailText: String {
        var parts = [club.type.rawValue]
        if let loft = club.loftDegrees {
            parts.append(String(format: "%.1f° loft", loft))
        }
        parts.append("\(club.expectedCarryYards) yd carry")
        parts.append("\(club.expectedTotalYards) yd total")
        return parts.joined(separator: " · ")
    }
}
