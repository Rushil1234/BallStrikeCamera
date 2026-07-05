import Foundation
import UIKit

/// Dev-mode real-time uploader: when enabled and signed in, every ACCEPTED shot (one that passed
/// the plausibility check in CameraController — not a discarded false trigger) is zipped and
/// uploaded straight to a "TrueCarry Frames" folder in the signed-in Google Drive account, no
/// manual export tap needed. Complements FrameArchiveService, which is the local "save everything,
/// export a batch later" path — this one is the live, always-on-Drive path.
final class GoogleDriveUploadService {
    static let shared = GoogleDriveUploadService()
    private init() {}

    static let enabledKey = "tc_dev_mode_drive_upload"
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var cachedFolderId: String?

    /// Fire-and-forget from the capture pipeline — runs off-thread and never throws into the
    /// caller; failures are logged only, so a flaky network never disrupts shot capture.
    @MainActor
    func uploadShotIfEnabled(frames: [CapturedFrame], impactIndex: Int) {
        guard isEnabled, GoogleDriveAuthService.shared.isSignedIn, !frames.isEmpty else { return }
        let snapshot = frames.enumerated().map { ($0.offset, $0.element.image, $0.element.timestamp) }
        let capturedAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            await self?.upload(snapshot: snapshot, impactIndex: impactIndex, capturedAt: capturedAt)
        }
    }

    private func upload(snapshot: [(Int, UIImage, TimeInterval)], impactIndex: Int, capturedAt: Date) async {
        do {
            let zipURL = try Self.writeAndZip(snapshot: snapshot, impactIndex: impactIndex, capturedAt: capturedAt)
            defer { try? FileManager.default.removeItem(at: zipURL) }
            let token = try await GoogleDriveAuthService.shared.validAccessToken()
            let folder = try await folderId(token: token)
            try await Self.uploadFile(zipURL, folderId: folder, token: token)
            print("[GoogleDrive] uploaded \(zipURL.lastPathComponent)")
        } catch {
            print("[GoogleDrive] upload failed: \(error)")
        }
    }

    // MARK: - Local zip (mirrors FrameArchiveService's per-shot layout: PNGs + timestamps.json)

    private static func writeAndZip(snapshot: [(Int, UIImage, TimeInterval)],
                                    impactIndex: Int, capturedAt: Date) throws -> URL {
        let fm = FileManager.default
        let stamp = folderStamp(capturedAt)
        let workDir = fm.temporaryDirectory.appendingPathComponent("drive_upload_\(stamp)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var timestamps: [[String: Any]] = []
        for (idx, image, t) in snapshot {
            let name = String(format: "frame_%03d.png", idx)
            if let data = image.pngData() {
                try data.write(to: workDir.appendingPathComponent(name))
            }
            timestamps.append(["frame_index": idx, "timestamp": t])
        }
        let meta: [String: Any] = [
            "captured_at": ISO8601DateFormatter().string(from: capturedAt),
            "frame_count": snapshot.count,
            "impact_frame_index": impactIndex,
            "timestamps": timestamps
        ]
        if let d = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try d.write(to: workDir.appendingPathComponent("timestamps.json"))
        }

        let zipURL = fm.temporaryDirectory.appendingPathComponent("shot_\(stamp).zip")
        try? fm.removeItem(at: zipURL)
        try StoredZip.zip(directory: workDir, to: zipURL)
        return zipURL
    }

    // MARK: - Drive folder (find-or-create, cached for the process lifetime)

    private func folderId(token: String) async throws -> String {
        if let cachedFolderId { return cachedFolderId }
        if let found = try await Self.findFolder(token: token) {
            cachedFolderId = found
            return found
        }
        let created = try await Self.createFolder(token: token)
        cachedFolderId = created
        return created
    }

    private static func findFolder(token: String) async throws -> String? {
        var components = URLComponents(string: GoogleDriveConfig.driveFilesEndpoint)!
        let escapedName = GoogleDriveConfig.uploadFolderName.replacingOccurrences(of: "'", with: "\\'")
        components.queryItems = [
            URLQueryItem(name: "q", value:
                "name = '\(escapedName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleDriveError.uploadFailed("folder lookup failed")
        }
        struct FileList: Decodable { struct F: Decodable { let id: String }; let files: [F] }
        return try JSONDecoder().decode(FileList.self, from: data).files.first?.id
    }

    private static func createFolder(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: GoogleDriveConfig.driveFilesEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": GoogleDriveConfig.uploadFolderName,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleDriveError.uploadFailed("folder create failed")
        }
        struct Created: Decodable { let id: String }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    // MARK: - Upload (multipart: JSON metadata part + binary zip part)

    private static func uploadFile(_ fileURL: URL, folderId: String, token: String) async throws {
        let metadata: [String: Any] = ["name": fileURL.lastPathComponent, "parents": [folderId]]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let fileData = try Data(contentsOf: fileURL)

        let boundary = "TrueCarryBoundary\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        var components = URLComponents(string: GoogleDriveConfig.driveUploadEndpoint)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GoogleDriveError.uploadFailed("file upload failed (status \(status))")
        }
    }

    private static func folderStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f.string(from: date)
    }
}
