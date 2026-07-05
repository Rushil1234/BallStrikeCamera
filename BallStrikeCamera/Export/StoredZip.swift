import Foundation

/// Minimal ZIP writer using the STORED (no compression) method. Recursively walks a directory
/// tree and preserves relative paths (so `AllFramesArchive/shot_x/frame_000.png` stays nested in
/// the archive). Dependency-free — the app already ships a flat variant in ShotExportService; this
/// one supports subfolders for batch exports.
enum StoredZip {

    enum ZipError: LocalizedError {
        case cannotCreateFile
        var errorDescription: String? { "Failed to create ZIP archive" }
    }

    /// Zip every file under `directory` (recursively) into `outputURL`.
    static func zip(directory: URL, to outputURL: URL) throws {
        let fm = FileManager.default
        let files = try enumerateFiles(under: directory)
            .sorted { $0.relativePath < $1.relativePath }

        if fm.fileExists(atPath: outputURL.path) { try fm.removeItem(at: outputURL) }
        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: outputURL.path) else { throw ZipError.cannotCreateFile }
        defer { try? handle.close() }

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

            handle.write(hdr)
            handle.write(fileData)
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
            handle.write(cd)
            cdSize += UInt32(cd.count)
        }

        var eocd = Data()
        eocd.le(UInt32(0x06054b50))
        eocd.le(UInt16(0)); eocd.le(UInt16(0))
        eocd.le(UInt16(cdEntries.count)); eocd.le(UInt16(cdEntries.count))
        eocd.le(cdSize); eocd.le(cdStart)
        eocd.le(UInt16(0))
        handle.write(eocd)
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
