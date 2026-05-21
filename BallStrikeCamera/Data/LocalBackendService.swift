import Foundation
import CryptoKit

// MARK: - Local JSON-file implementation of AppBackend

final class LocalBackendService: AppBackend {

    // MARK: Auth

    func currentUser() async throws -> AppUser? {
        guard let session = try? AppStorageManager.load(StoredSession.self, from: AppStorageManager.currentSessionFile) else { return nil }
        let users = loadUsersIndex()
        return users.first { $0.id == session.userId }
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        var users = loadUsersIndex()
        guard let idx = users.firstIndex(where: { $0.email.lowercased() == email.lowercased() }) else {
            throw BackendError.userNotFound
        }
        let stored = try loadStoredCredential(userId: users[idx].id)
        guard stored.passwordHash == hashPassword(password) else {
            throw BackendError.wrongPassword
        }
        users[idx].rememberedLogin = true
        saveUsersIndex(users)
        try saveSession(userId: users[idx].id)
        return users[idx]
    }

    func createAccount(name: String, email: String, password: String) async throws -> AppUser {
        var users = loadUsersIndex()
        guard !users.contains(where: { $0.email.lowercased() == email.lowercased() }) else {
            throw BackendError.emailAlreadyExists
        }
        let user = AppUser(name: name, email: email, rememberedLogin: true)
        users.append(user)
        saveUsersIndex(users)
        try saveStoredCredential(StoredCredential(userId: user.id, passwordHash: hashPassword(password)))
        try saveSession(userId: user.id)
        AppStorageManager.ensureUserDirectories(userId: user.id)
        let profile = UserProfile(userId: user.id, displayName: name)
        try await saveUserProfile(profile)
        for club in UserClub.defaultBag(userId: user.id) {
            try await saveClub(club)
        }
        return user
    }

    func continueAsGuest() async throws -> AppUser {
        var users = loadUsersIndex()
        if let existing = users.first(where: { $0.isGuest }) {
            try saveSession(userId: existing.id)
            return existing
        }
        let guest = AppUser(name: "Guest", email: "guest@local", isGuest: true, rememberedLogin: true)
        users.append(guest)
        saveUsersIndex(users)
        try saveSession(userId: guest.id)
        AppStorageManager.ensureUserDirectories(userId: guest.id)
        let profile = UserProfile(userId: guest.id, displayName: "Guest")
        try await saveUserProfile(profile)
        for club in UserClub.defaultBag(userId: guest.id) {
            try await saveClub(club)
        }
        return guest
    }

    func signOut() async throws {
        try? FileManager.default.removeItem(at: AppStorageManager.currentSessionFile)
    }

    // MARK: Profile

    func saveUserProfile(_ profile: UserProfile) async throws {
        let dir = AppStorageManager.profileDir(userId: profile.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(profile, to: dir.appendingPathComponent("profile.json"))
    }

    func loadUserProfile(userId: UUID) async throws -> UserProfile? {
        let url = AppStorageManager.profileDir(userId: userId).appendingPathComponent("profile.json")
        return try? AppStorageManager.load(UserProfile.self, from: url)
    }

    // MARK: Clubs

    func saveClub(_ club: UserClub) async throws {
        let dir = AppStorageManager.clubsDir(userId: club.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(club, to: dir.appendingPathComponent("\(club.id.uuidString).json"))
    }

    func deleteClub(clubId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.clubsDir(userId: userId).appendingPathComponent("\(clubId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func loadClubs(userId: UUID) async throws -> [UserClub] {
        let clubs = try AppStorageManager.loadAll(UserClub.self, from: AppStorageManager.clubsDir(userId: userId))
        return clubs.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: Shots

    func saveShot(_ shot: SavedShot) async throws {
        let dir = AppStorageManager.shotsDir(userId: shot.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(shot, to: dir.appendingPathComponent("\(shot.id.uuidString).json"))
    }

    func loadShots(userId: UUID) async throws -> [SavedShot] {
        let shots = try AppStorageManager.loadAll(SavedShot.self, from: AppStorageManager.shotsDir(userId: userId))
        return shots.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteShot(shotId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.shotsDir(userId: userId).appendingPathComponent("\(shotId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Range Sessions

    func saveRangeSession(_ session: PracticeSession) async throws {
        let dir = AppStorageManager.rangeSessionsDir(userId: session.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(session, to: dir.appendingPathComponent("\(session.id.uuidString).json"))
    }

    func deleteRangeSession(sessionId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.rangeSessionsDir(userId: userId).appendingPathComponent("\(sessionId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func loadRangeSessions(userId: UUID) async throws -> [PracticeSession] {
        let sessions = try AppStorageManager.loadAll(PracticeSession.self, from: AppStorageManager.rangeSessionsDir(userId: userId))
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Sim Sessions

    func saveSimSession(_ session: SimSession) async throws {
        let dir = AppStorageManager.simSessionsDir(userId: session.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(session, to: dir.appendingPathComponent("\(session.id.uuidString).json"))
    }

    func deleteSimSession(sessionId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.simSessionsDir(userId: userId).appendingPathComponent("\(sessionId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func loadSimSessions(userId: UUID) async throws -> [SimSession] {
        let sessions = try AppStorageManager.loadAll(SimSession.self, from: AppStorageManager.simSessionsDir(userId: userId))
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Course Rounds

    func saveRound(_ round: CourseRound) async throws {
        let dir = AppStorageManager.roundsDir(userId: round.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(round, to: dir.appendingPathComponent("\(round.id.uuidString).json"))
    }

    func deleteCourseRound(roundId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.roundsDir(userId: userId).appendingPathComponent("\(roundId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func loadCourseRounds(userId: UUID) async throws -> [CourseRound] {
        let rounds = try AppStorageManager.loadAll(CourseRound.self, from: AppStorageManager.roundsDir(userId: userId))
        return rounds.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: Feed

    func saveFeedPost(_ post: FeedPost) async throws {
        let dir = AppStorageManager.feedDir(userId: post.userId)
        AppStorageManager.ensureDirectory(dir)
        try AppStorageManager.save(post, to: dir.appendingPathComponent("\(post.id.uuidString).json"))
    }

    func deleteFeedPost(postId: UUID, userId: UUID) async throws {
        let url = AppStorageManager.feedDir(userId: userId).appendingPathComponent("\(postId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    func loadFeed(userId: UUID) async throws -> [FeedPost] {
        let posts = try AppStorageManager.loadAll(FeedPost.self, from: AppStorageManager.feedDir(userId: userId))
        return posts.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Private helpers

    private struct StoredSession: Codable {
        var userId: UUID
        var createdAt: Date = Date()
    }

    private struct StoredCredential: Codable {
        var userId: UUID
        var passwordHash: String
    }

    private func saveSession(userId: UUID) throws {
        AppStorageManager.ensureDirectory(AppStorageManager.authDir)
        try AppStorageManager.save(StoredSession(userId: userId), to: AppStorageManager.currentSessionFile)
    }

    private func loadUsersIndex() -> [AppUser] {
        AppStorageManager.ensureDirectory(AppStorageManager.authDir)
        return (try? AppStorageManager.load([AppUser].self, from: AppStorageManager.usersIndexFile)) ?? []
    }

    private func saveUsersIndex(_ users: [AppUser]) {
        try? AppStorageManager.save(users, to: AppStorageManager.usersIndexFile)
    }

    private func credentialFile(userId: UUID) -> URL {
        AppStorageManager.authDir.appendingPathComponent("\(userId.uuidString)_cred.json")
    }

    private func loadStoredCredential(userId: UUID) throws -> StoredCredential {
        try AppStorageManager.load(StoredCredential.self, from: credentialFile(userId: userId))
    }

    private func saveStoredCredential(_ cred: StoredCredential) throws {
        try AppStorageManager.save(cred, to: credentialFile(userId: cred.userId))
    }

    private func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
