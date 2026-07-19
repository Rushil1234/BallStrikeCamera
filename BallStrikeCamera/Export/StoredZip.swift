import Foundation

/// Minimal ZIP writer using the STORED (no compression) method. Recursively walks a directory
/// tree and preserves relative paths (so `AllFramesArchive/shot_x/frame_000.png` stays nested in
/// the archive). Dependency-free — the app already ships a flat variant in ShotExportService; this
/// one supports subfolders for batch exports.
enum StoredZip {

    enum ZipError: LocalizedError {
        case cannotCreateFile
        case insufficientSpace(needed: Int64, available: Int64)

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile:
                return "Failed to create ZIP archive"
            case let .insufficientSpace(needed, available):
                let f = ByteCountFormatter.string(fromByteCount:countStyle:)
                return "Not enough space to export: needs about \(f(needed, .file)), "
                     + "but only \(f(available, .file)) is free. Free up space and try again."
            }
        }
    }

    /// Zip every file under `directory` (recursively) into `outputURL`.
    ///
    /// NOTE: writes go through `write(contentsOf:)` (the throwing API). The legacy
    /// `write(_:)` raises an Objective-C `NSFileHandleOperationException` when the
    /// volume fills up, which Swift `try` cannot catch — that hard-crashed the app.
    /// We also pre-flight the space requirement so the common case fails cleanly.
    static func zip(directory: URL, to outputURL: URL) throws {
        let fm = FileManager.default
        let files = try enumerateFiles(under: directory)
            .sorted { $0.relativePath < $1.relativePath }

        // Pre-flight: payload + per-file local header + central directory + EOCD.
        let payload = files.reduce(Int64(0)) { sum, f in
            sum + Int64((try? f.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        let overhead = files.reduce(Int64(22)) { sum, f in
            sum + Int64(30 + 46 + (f.relativePath.utf8.count * 2))
        }
        let needed = payload + overhead
        let available = (try? outputURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? Int64.max
        if needed > available {
            throw ZipError.insufficientSpace(needed: needed, available: available)
        }

        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: outputURL.path) else { throw ZipError.cannotCreateFile }
        // Close always; also don't leave a truncated archive behind on failure.
        var completed = false
        defer {
            try? handle.close()
            if !completed { try? fm.removeItem(at: outputURL) }
        }

        var cdEntries: [(name: [UInt8], crc: UInt32, size: UInt32, offset: UInt32)] = []
        var offset: UInt32 = 0

        for file in files {
            let fileData = try Data(contentsOf: file.url)
            let nameBytes = Array(file.relativePath.utf8)
            let crc  = crc32(fileData)
            let size = UInt32(fileData.count)
            cdEntries.append((nameBytes, crc, size, offset))

            var hdr = Data()
            hdr.le(UInt32(0x04034b50))
            hdr.le(UInt16(20)); hdr.le(UInt16(0))
            hdr.le(UInt16(0))            // stored, no compression
            hdr.le(UInt16(0)); hdr.le(UInt16(0))
            hdr.le(crc); hdr.le(size); hdr.le(size)
            hdr.le(UInt16(nameBytes.count)); hdr.le(UInt16(0))
            hdr.append(contentsOf: nameBytes)

            try handle.write(contentsOf: hdr)
            try handle.write(contentsOf: fileData)
            offset += UInt32(hdr.count) + size
        }

        let cdStart = offset
        var cdSize: UInt32 = 0
        for e in cdEntries {
            var cd = Data()
            cd.le(UInt32(0x02014b50))
            cd.le(UInt16(20)); cd.le(UInt16(20))
            cd.le(UInt16(0)); cd.le(UInt16(0))
            cd.le(UInt16(0)); cd.le(UInt16(0))
            cd.le(e.crc); cd.le(e.size); cd.le(e.size)
            cd.le(UInt16(e.name.count))
            cd.le(UInt16(0)); cd.le(UInt16(0))
            cd.le(UInt16(0)); cd.le(UInt16(0))
            cd.le(UInt32(0)); cd.le(e.offset)
            cd.append(contentsOf: e.name)
            try handle.write(contentsOf: cd)
            cdSize += UInt32(cd.count)
        }

        var eocd = Data()
        eocd.le(UInt32(0x06054b50))
        eocd.le(UInt16(0)); eocd.le(UInt16(0))
        eocd.le(UInt16(cdEntries.count)); eocd.le(UInt16(cdEntries.count))
        eocd.le(cdSize); eocd.le(cdStart)
        eocd.le(UInt16(0))
        try handle.write(contentsOf: eocd)
        completed = true
    }

    // MARK: - Helpers

    private struct FileEntry { let url: URL; let relativePath: String }

    private static func enumerateFiles(under root: URL) throws -> [FileEntry] {
        let fm = FileManager.default
        let base = root.standardizedFileURL.path
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [FileEntry] = []
        for case let url as URL in en {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            var rel = url.standardizedFileURL.path
            if rel.hasPrefix(base) { rel = String(rel.dropFirst(base.count)) }
            rel = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
            out.append(FileEntry(url: url, relativePath: rel))
        }
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1 }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { ptr in
            for byte in ptr { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        self += Data(bytes: &v, count: MemoryLayout<T>.size)
    }
}
