import CryptoKit
import Foundation

/// The committed list of every file the bundled voice needs (plan phase 3,
/// unit 3B). `make update-model-manifest` is the only writer.
public struct ModelManifest: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int64
        public let sha256: String

        public init(path: String, size: Int64, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    public var files: [File]
    /// Paths (relative to the store directory) that FluidAudio may create in
    /// a fresh store. Any other new file fails `make offline-test`.
    public var generated: [String]
    /// Bundled voice identifiers; the first is the default.
    public var voices: [String]

    public init(files: [File], generated: [String] = [], voices: [String]) {
        self.files = files.sorted { $0.path < $1.path }
        self.generated = generated.sorted()
        self.voices = voices
    }

    public static func load(from url: URL) throws -> ModelManifest {
        try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Content hash of the file list: the store directory name for this version.
    public var contentHash: String {
        let lines = files.map { "\($0.path) \($0.size) \($0.sha256)\n" }.joined()
        return SHA256.hash(data: Data(lines.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Builds a manifest from a directory (used only by the reviewed manifest update).
    public static func scan(_ directory: URL, voices: [String], generated: [String] = []) throws -> ModelManifest {
        var files: [File] = []
        let base = directory.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            files.append(File(path: path, size: Int64(values.fileSize ?? 0), sha256: try ManifestValidator.sha256(of: url)))
        }
        return ModelManifest(files: files, generated: generated, voices: voices)
    }
}

public enum ValidationFailure: Error, Equatable, Sendable {
    case missing(String)
    case sizeMismatch(String)
    case hashMismatch(String)
}

/// Size and SHA-256 per manifest file. Fails closed on the first difference.
public enum ManifestValidator {
    public static func validate(_ directory: URL, against manifest: ModelManifest) -> ValidationFailure? {
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else { return .missing(file.path) }
            guard size.int64Value == file.size else { return .sizeMismatch(file.path) }
            guard (try? sha256(of: url)) == file.sha256 else { return .hashMismatch(file.path) }
        }
        return nil
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
