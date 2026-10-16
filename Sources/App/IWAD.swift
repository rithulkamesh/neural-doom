import Foundation

enum IWADValidator {
    static func error(for url: URL) -> String? {
        guard url.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.int64Value >= 12,
              let file = try? FileHandle(forReadingFrom: url) else {
            return "IWAD is missing or unreadable: \(url.path)"
        }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 12), header.count == 12,
              String(data: header.prefix(4), encoding: .ascii) == "IWAD" else {
            return "The selected file is not a Doom IWAD."
        }
        func word(_ offset: Int) -> Int64 {
            let b = Array(header)
            return Int64(UInt32(b[offset]) | UInt32(b[offset+1]) << 8 |
                         UInt32(b[offset+2]) << 16 | UInt32(b[offset+3]) << 24)
        }
        let count = word(4), directory = word(8)
        guard count > 0, count < 100_000, directory >= 12,
              directory + count * 16 <= size.int64Value else {
            return "The IWAD directory is damaged or incomplete."
        }
        return nil
    }
}
