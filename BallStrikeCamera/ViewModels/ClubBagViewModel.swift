import Foundation

@MainActor
final class ClubBagViewModel: ObservableObject {

    @Published var clubs: [UserClub] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            clubs = try await backend.loadClubs(userId: userId)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addClub(_ club: UserClub) async {
        do {
            try await backend.saveClub(club)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateClub(_ club: UserClub) async {
        do {
            try await backend.saveClub(club)
            if let idx = clubs.firstIndex(where: { $0.id == club.id }) {
                clubs[idx] = club
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteClub(id: UUID) async {
        do {
            try await backend.deleteClub(clubId: id, userId: userId)
            clubs.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        clubs.move(fromOffsets: source, toOffset: destination)
        for (i, var club) in clubs.enumerated() {
            club.sortOrder = i
            Task { await updateClub(club) }
        }
    }
}
