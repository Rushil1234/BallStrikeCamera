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

    // MARK: - Foreground Read
    //
    // Background NDEF routing (truecarry:// URL) is suspended when the app is in
    // the foreground. The only way to read NFC while active is NFCNDEFReaderSession,
    // which always shows the system scanning sheet. We start a one-shot session when
    // the user opens the club picker so they can tap a tagged club instead of picking
    // from the list — the sheet dismisses automatically on success.

    private var readSession: NFCNDEFReaderSession?

    enum ReadState: Equatable {
        case idle, scanning, success, failure(String)
    }
    @Published var readState: ReadState = .idle

    func beginReading(alertMessage: String = "Or tap your NFC club to auto-select") {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        readState = .scanning
        readSession = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
        readSession?.alertMessage = alertMessage
        readSession?.begin()
    }

    func cancelRead() {
        readSession?.invalidate()
        readSession = nil
        readState = .idle
    }

    // MARK: - Read (URL routing)

    /// Called by BallStrikeCameraApp when the OS delivers a truecarry:// URL
    /// triggered by tapping an NFC-tagged club to the phone.
    /// Returns the parsed club UUID if the URL is a valid NFC club URL.
    @discardableResult
    func handleNFCURL(_ url: URL) -> UUID? {
        print("[NFC] handleNFCURL: \(url.absoluteString)")
        guard url.scheme?.lowercased() == "truecarry",
              url.host?.lowercased() == "nfc",
              let uuidString = url.pathComponents.dropFirst().first,
              let uuid = UUID(uuidString: uuidString) else {
            print("[NFC] handleNFCURL: parse failed scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")
            return nil
        }
        print("[NFC] handleNFCURL: parsed uuid=\(uuid)")
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
        let nfcError  = error as? NFCReaderError
        let cancelled = nfcError?.code == .readerSessionInvalidationErrorUserCanceled
        let firstRead = nfcError?.code == .readerSessionInvalidationErrorFirstNDEFTagRead
        Task { @MainActor in
            if session === self.readSession {
                self.readSession = nil
                if !cancelled && !firstRead { self.readState = .failure(error.localizedDescription) }
                else if cancelled           { self.readState = .idle }
                // .success path sets readSession = nil before invalidating, so we never land here
            } else if session === self.writeSession {
                self.writeSession = nil
                if !cancelled { self.writeState = .failure(error.localizedDescription) }
                else           { self.writeState = .idle }
            }
            // else: session already cleaned up (successful read/write) — ignore
        }
    }

    // NOTE: When didDetect tags: is implemented, iOS always calls it instead of
    // didDetectNDEFs. We handle both write (pendingClubId set) and read (nil) here.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession,
                                   didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        Task { @MainActor in
            let clubId = self.pendingClubId   // non-nil = write, nil = read
            session.connect(to: tag) { error in
                if let error = error {
                    session.invalidate(errorMessage: "Could not connect: \(error.localizedDescription)")
                    return
                }

                if let clubId {
                    // ---- WRITE path ----
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
                        guard let uriPayload = NFCNDEFPayload.wellKnownTypeURIPayload(string: uriString) else {
                            session.invalidate(errorMessage: "Could not create NFC record.")
                            return
                        }
                        tag.writeNDEF(NFCNDEFMessage(records: [uriPayload])) { error in
                            if let error = error {
                                session.invalidate(errorMessage: "Write failed: \(error.localizedDescription)")
                                Task { @MainActor in self.writeState = .failure(error.localizedDescription) }
                            } else {
                                session.alertMessage = "Club linked!"
                                Task { @MainActor in
                                    self.writeState = .success
                                    self.pendingClubId = nil
                                    self.writeSession = nil  // disassociate before invalidate fires
                                    session.invalidate()
                                }
                            }
                        }
                    }
                } else {
                    // ---- READ path ----
                    tag.readNDEF { message, error in
                        guard let message, error == nil else {
                            session.invalidate(errorMessage: "Could not read tag.")
                            return
                        }
                        for record in message.records {
                            if let url = record.wellKnownTypeURIPayload() {
                                Task { @MainActor in
                                    self.handleNFCURL(url)
                                    self.readState = .success
                                    self.readSession = nil
                                    session.invalidate()
                                }
                                return
                            }
                        }
                        session.invalidate(errorMessage: "No club tag found on this sticker.")
                    }
                }
            }
        }
    }

    // Only called when didDetect tags: is NOT implemented. Safety net.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession,
                                   didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let record = messages.first?.records.first,
              let url = record.wellKnownTypeURIPayload() else { return }
        Task { @MainActor in
            self.handleNFCURL(url)
            self.readState = .success
        }
    }
}
