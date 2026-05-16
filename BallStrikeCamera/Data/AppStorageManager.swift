import Foundation

/// Manages all file paths under Documents/BallStrike/users/<userId>/
enum AppStorageManager {

    static let rootFolder = "BallStrike"

    // MARK: - Root Directories

    static func userRoot(for userId: UUID) -> URL {
        documents
            .appendingPathComponent(rootFolder)
            .appendingPathComponent("users")
            .appendingPathComponent(userId.uuidString)
    }

    static var globalRoot: URL {
        documents.appendingPathComponent(rootFolder)
    }

    // MARK: - Per-User Subdirectories

    static func profileDir(userId: UUID)         -> URL { userRoot(for: userId).appendingPathComponent("profile") }
    static func clubsDir(userId: UUID)           -> URL { userRoot(for: userId).appendingPathComponent("clubs") }
    static func shotsDir(userId: UUID)           -> URL { userRoot(for: userId).appendingPathComponent("shots") }
    static func rangeSessionsDir(userId: UUID)   -> URL { userRoot(for: userId).appendingPathComponent("sessions/range") }
    static func simSessionsDir(userId: UUID)     -> URL { userRoot(for: userId).appendingPathComponent("sessions/sim") }
    static func roundsDir(userId: UUID)          -> URL { userRoot(for: userId).appendingPathComponent("rounds") }
    static func feedDir(userId: UUID)            -> URL { userRoot(for: userId).appendingPathComponent("feed") }
    static func compositeDir(userId: UUID)       -> URL { userRoot(for: userId).appendingPathComponent("media/composites") }
    static func shotFramesDir(userId: UUID, shotId: UUID) -> URL {
        userRoot(for: userId)
            .appendingPathComponent("media/shotFrames")
            .appendingPathComponent(shotId.uuidString)
    }
    static func courseCacheDir(userId: UUID)     -> URL { userRoot(for: userId).appendingPathComponent("courseCache") }
    static func globalCourseCacheDir()           -> URL { globalRoot.appendingPathComponent("courseCache") }

    // MARK: - Auth

    static var authDir: URL { globalRoot.appendingPathComponent("auth") }
    static var usersIndexFile: URL { authDir.appendingPathComponent("users.json") }
    static var currentSessionFile: URL { authDir.appendingPathComponent("session.json") }

    // MARK: - Helpers

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func ensureUserDirectories(userId: UUID) {
        let dirs: [URL] = [
            profileDir(userId: userId),
            clubsDir(userId: userId),
            shotsDir(userId: userId),
            rangeSessionsDir(userId: userId),
            simSessionsDir(userId: userId),
            roundsDir(userId: userId),
            feedDir(userId: userId),
            compositeDir(userId: userId),
            courseCacheDir(userId: userId),
            authDir,
        ]
        dirs.forEach { ensureDirectory($0) }
    }

    // MARK: - JSON encode/decode helpers

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func save<T: Codable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomicWrite)
    }

    static func load<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    static func loadAll<T: Codable>(_ type: T.Type, from dir: URL) throws -> [T] {
        ensureDirectory(dir)
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return urls.compactMap { try? load(type, from: $0) }
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
