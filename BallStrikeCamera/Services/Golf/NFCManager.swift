import CoreNFC
import Foundation
import Combine

// MARK: - NFCManager
//
// Handles two NFC flows:
//
// 1. WRITE (setup): User taps "Set Up NFC Tag" in EditClubView.
//    Opens a foreground NFCNDEFReaderSession and writes a URI record
//    (truecarry://nfc/{club-uuid-lowercase}) to the physical sticker.
//
// 2. READ (always-on via URL routing): The sticker's URI triggers iOS's
//    background NDEF routing. The system delivers it to this app via
//    BallStrikeCameraApp.onOpenURL, which calls handleNFCURL(_:).
//    Publishes `lastScannedClubId` — observers react silently.
//
// URL scheme "truecarry" must be registered in Info.plist.

@MainActor
final class NFCManager: NSObject, ObservableObject {

    static let shared = NFCManager()

    // MARK: Published state

    /// The UUID of the club last detected by an NFC tap. Nil until first tap.
    @Published var lastScannedClubId: UUID?

    /// Write-session state surfaced to the setup UI.
    enum WriteState: Equatable {
        case idle, scanning, success, failure(String)
    }
    @Published var writeState: WriteState = .idle

    // MARK: Private

    private var writeSession: NFCNDEFReaderSession?
    private var pendingClubId: UUID?

    private override init() { super.init() }

    // MARK: - Write

    /// Starts an NFC write session. The user holds their phone to the sticker;
    /// on success `writeState` becomes `.success` and the tag is now paired.
    func beginWriting(clubId: UUID) {
        guard NFCNDEFReaderSession.readingAvailable else {
            writeState = .failure("NFC is not available on this device.")
            return
        }
        pendingClubId = clubId
        writeState = .scanning
        writeSession = NFCNDEFReaderSession(
            delegate: self, queue: .main, invalidateAfterFirstRead: false)
        writeSession?.alertMessage = "Hold your iPhone near the NFC sticker on your club."
        writeSession?.begin()
    }

    func cancelWrite() {
        writeSession?.invalidate()
        writeSession = nil
        writeState = .idle
        pendingClubId = nil
    }

    // MARK: - Read (URL routing)

    /// Called by BallStrikeCameraApp when the OS delivers a truecarry:// URL
    /// triggered by tapping an NFC-tagged club to the phone.
    /// Returns the parsed club UUID if the URL is a valid NFC club URL.
    @discardableResult
    func handleNFCURL(_ url: URL) -> UUID? {
        // Expected format: truecarry://nfc/{club-uuid}
        guard url.scheme?.lowercased() == "truecarry",
              url.host?.lowercased() == "nfc",
              let uuidString = url.pathComponents.dropFirst().first,
              let uuid = UUID(uuidString: uuidString) else { return nil }
        lastScannedClubId = uuid
        return uuid
    }

    // MARK: - Helpers

    static func nfcURL(for clubId: UUID) -> String {
        "truecarry://nfc/\(clubId.uuidString.lowercased())"
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCManager: NFCNDEFReaderSessionDelegate {

    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession,
                                   didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        // Code 200 = user cancelled — not a real error
        guard nfcError?.code != .readerSessionInvalidationErrorUserCanceled else {
            Task { @MainActor in self.writeState = .idle }
            return
        }
        Task { @MainActor in
            self.writeState = .failure(error.localizedDescription)
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession,
                                   didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not used — writing uses didDetect tags
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession,
                                   didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        Task { @MainActor in guard let clubId = self.pendingClubId else { return }
            session.connect(to: tag) { error in
                if let error = error {
                    session.invalidate(errorMessage: "Could not connect: \(error.localizedDescription)")
                    return
                }
                tag.queryNDEFStatus { status, _, error in
                    guard error == nil else {
                        session.invalidate(errorMessage: "Could not read tag.")
                        return
                    }
                    guard status != .notSupported else {
                        session.invalidate(errorMessage: "This tag doesn't support writing.")
                        return
                    }

                    let uriString = NFCManager.nfcURL(for: clubId)
                    guard let uriPayload = NFCNDEFPayload.wellKnownTypeURIPayload(
                        string: uriString) else {
                        session.invalidate(errorMessage: "Could not create NFC record.")
                        return
                    }
                    let message = NFCNDEFMessage(records: [uriPayload])

                    tag.writeNDEF(message) { error in
                        if let error = error {
                            session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                            Task { @MainActor in
                                self.writeState = .failure(error.localizedDescription)
                            }
                        } else {
                            session.alertMessage = "NFC tag linked to \(self.pendingClubId?.uuidString ?? "club")!"
                            session.invalidate()
                            Task { @MainActor in
                                self.writeState = .success
                            }
                        }
                    }
                }
            }
        }
    }
}
