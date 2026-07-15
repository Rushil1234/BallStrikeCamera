import Foundation
import UIKit

/// Dev-mode real-time uploader: when enabled and signed in, EVERY analyzed capture — accepted,
/// discarded, or reposition — is zipped and uploaded straight to a "TrueCarry Frames" folder in
/// the signed-in Google Drive account, no manual export tap needed (discarded shots are exactly
/// the footage needed to debug the tracker). Complements FrameArchiveService, which is the local
/// "save everything, export a batch later" path — this one is the live, always-on-Drive path.
final class GoogleDriveUploadService: ObservableObject {
    static let shared = GoogleDriveUploadService()
    private init() {}

    static let enabledKey = "tc_dev_mode_drive_upload"
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var cachedFolderId: String?

    // MARK: - Bulk archive upload state

    struct ArchiveUploadState {
        var total: Int
        var done: Int
        var failed: Int
        var isRunning: Bool
    }

    /// Progress of the one-tap "upload the whole local frame archive" action (profile dev card).
    @MainActor @Published private(set) var archiveUpload: ArchiveUploadState?

    /// Folder names already uploaded successfully — lets a re-tap resume where it left off
    /// instead of re-sending gigabytes. Names are capture timestamps, so entries stay valid
    /// (and harmless) across archive clears.
    private static let uploadedListKey = "tc_drive_uploaded_archive_shots"

    /// Archived shots not yet uploaded to Drive.
    func pendingArchiveCount() -> Int {
        let uploaded = Set(UserDefaults.standard.stringArray(forKey: Self.uploadedListKey) ?? [])
        return FrameArchiveService.shared.shotFolders().filter { !uploaded.contains($0.lastPathComponent) }.count
    }

    /// Upload every not-yet-uploaded archived shot to the "TrueCarry Frames" Drive folder,
    /// one zip per shot (same layout the live uploader produces, so replay tooling reads
    /// both identically). Sequential on purpose: bounded memory, and an interruption loses
    /// at most one shot's progress — everything already sent is skipped on the next tap.
    @MainActor
    func uploadArchive() {
        guard archiveUpload?.isRunning != true else { return }
        guard GoogleDriveAuthService.shared.isSignedIn else { return }
        let uploaded = Set(UserDefaults.standard.stringArray(forKey: Self.uploadedListKey) ?? [])
        let pending = FrameArchiveService.shared.shotFolders().filter { !uploaded.contains($0.lastPathComponent) }
        guard !pending.isEmpty else {
            archiveUpload = ArchiveUploadState(total: 0, done: 0, failed: 0, isRunning: false)
            return
        }
        archiveUpload = ArchiveUploadState(total: pending.count, done: 0, failed: 0, isRunning: true)
        // A multi-minute foreground upload dies silently if the screen sleeps mid-run.
        UIApplication.shared.isIdleTimerDisabled = true

        Task.detached(priority: .utility) {
            let fm = FileManager.default
            for shotDir in pending {
                var ok = false
                do {
                    let zipURL = fm.temporaryDirectory.appendingPathComponent(shotDir.lastPathComponent + ".zip")
                    try? fm.removeItem(at: zipURL)
                    try StoredZip.zip(directory: shotDir, to: zipURL)
                    defer { try? fm.removeItem(at: zipURL) }
                    let token = try await GoogleDriveAuthService.shared.validAccessToken()
                    let folder = try await self.folderId(token: token)
                    let localSize = (try? fm.attributesOfItem(atPath: zipURL.path)[.size] as? Int64) ?? -2
                    let remoteSize = try await Self.uploadFileResumable(zipURL, folderId: folder, token: token)
                    ok = true
                    var list = UserDefaults.standard.stringArray(forKey: Self.uploadedListKey) ?? []
                    list.append(shotDir.lastPathComponent)
                    UserDefaults.standard.set(list, forKey: Self.uploadedListKey)
                    // Free the phone ONLY after Drive confirms it holds the exact bytes we
                    // sent — a shot is never deleted on faith.
                    if remoteSize > 0 && remoteSize == localSize {
                        try? fm.removeItem(at: shotDir)
                        print("[GoogleDrive] archive upload VERIFIED (\(remoteSize) bytes) — local copy freed: \(shotDir.lastPathComponent)")
                    } else {
                        print("[GoogleDrive] archive upload ok but size unverified (local \(localSize) vs remote \(remoteSize)) — keeping local: \(shotDir.lastPathComponent)")
                    }
                } catch {
                    print("[GoogleDrive] archive upload FAILED \(shotDir.lastPathComponent): \(error)")
                }
                let succeeded = ok
                await MainActor.run {
                    self.archiveUpload?.done   += succeeded ? 1 : 0
                    self.archiveUpload?.failed += succeeded ? 0 : 1
                }
            }
            await MainActor.run {
                self.archiveUpload?.isRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    /// Auto-offload: when the dev toggle is on and shots have piled up, push the archive
    /// to Drive (verified, then locally freed) — called when a camera screen closes and
    /// when the app backgrounds, the two natural \"done hitting\" moments. Keeping the
    /// archive small is a thermal/storage win on range days.
    @MainActor
    func autoOffloadIfNeeded(minShots: Int = 5) {
        guard isEnabled, GoogleDriveAuthService.shared.isSignedIn else { return }
        guard pendingArchiveCount() >= minShots else { return }
        print("[GoogleDrive] auto-offload starting (\(pendingArchiveCount()) shots pending)")
        uploadArchive()
    }

    /// Fire-and-forget from the capture pipeline — runs off-thread and never throws into the
    /// caller; failures are logged only, so a flaky network never disrupts shot capture.
    @MainActor
    func uploadShotIfEnabled(frames: [CapturedFrame], impactIndex: Int,
                             lockedBallRect: CGRect? = nil, lockedImpactROI: CGRect? = nil) {
        guard isEnabled, GoogleDriveAuthService.shared.isSignedIn, !frames.isEmpty else { return }
        let snapshot = frames.enumerated().map { ($0.offset, $0.element.image, $0.element.timestamp) }
        let capturedAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            await self?.upload(snapshot: snapshot, impactIndex: impactIndex, capturedAt: capturedAt,
                               lockedBallRect: lockedBallRect, lockedImpactROI: lockedImpactROI)
        }
    }

    private func upload(snapshot: [(Int, UIImage, TimeInterval)], impactIndex: Int, capturedAt: Date,
                        lockedBallRect: CGRect?, lockedImpactROI: CGRect?) async {
        do {
            let zipURL = try Self.writeAndZip(snapshot: snapshot, impactIndex: impactIndex, capturedAt: capturedAt,
                                              lockedBallRect: lockedBallRect, lockedImpactROI: lockedImpactROI)
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
                                    impactIndex: Int, capturedAt: Date,
                                    lockedBallRect: CGRect?, lockedImpactROI: CGRect?) throws -> URL {
        let fm = FileManager.default
        let stamp = folderStamp(capturedAt)
        let workDir = fm.temporaryDirectory.appendingPathComponent("drive_upload_\(stamp)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        var timestamps: [[String: Any]] = []
        for (idx, image, t) in snapshot {
            let name = String(format: "frame_%03d.jpg", idx)
            if let data = image.jpegData(compressionQuality: 0.9) {
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
        // Lock state for offline live-parity replay in BallTrackingTester (same as FrameArchiveService).
        var extra: [String: Any] = ["impact_frame_index": impactIndex]
        if let r = lockedBallRect {
            extra["locked_ball_rect"] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        if let r = lockedImpactROI {
            extra["locked_impact_roi"] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        if let d = try? JSONSerialization.data(withJSONObject: extra, options: [.prettyPrinted]) {
            try d.write(to: workDir.appendingPathComponent("metadata.json"))
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

    // MARK: - Upload (resumable: no practical size cap, streams from disk)

    /// Multipart above is only rated for ~5MB payloads; archived full-shot zips can exceed
    /// that. The resumable protocol takes two requests (initiate session → PUT bytes) and
    /// `URLSession.upload(fromFile:)` streams the zip instead of loading it into memory.
    /// Returns the uploaded file's size as reported by Drive, for verification.
    @discardableResult
    private static func uploadFileResumable(_ fileURL: URL, folderId: String, token: String) async throws -> Int64 {
        var components = URLComponents(string: GoogleDriveConfig.driveUploadEndpoint)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "resumable")]
        var initReq = URLRequest(url: components.url!)
        initReq.httpMethod = "POST"
        initReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": fileURL.lastPathComponent, "parents": [folderId]
        ])
        let (_, initResp) = try await URLSession.shared.data(for: initReq)
        guard let initHTTP = initResp as? HTTPURLResponse, (200..<300).contains(initHTTP.statusCode),
              let location = initHTTP.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw GoogleDriveError.uploadFailed("resumable session init failed (status \((initResp as? HTTPURLResponse)?.statusCode ?? -1))")
        }

        var putReq = URLRequest(url: sessionURL)
        putReq.httpMethod = "PUT"
        let (putData, putResp) = try await URLSession.shared.upload(for: putReq, fromFile: fileURL)
        guard let putHTTP = putResp as? HTTPURLResponse, (200..<300).contains(putHTTP.statusCode) else {
            throw GoogleDriveError.uploadFailed("resumable upload failed (status \((putResp as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        struct Uploaded: Decodable { let id: String; let size: String? }
        if let up = try? JSONDecoder().decode(Uploaded.self, from: putData), let sz = up.size, let n = Int64(sz) {
            return n
        }
        return -1
    }

    private static func folderStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f.string(from: date)
    }
}
