import Foundation
import Synchronization

/// File operations the store performs. The system implementation is used in
/// production; tests inject failures (disk full, a failed rename) at this
/// owned boundary.
public protocol StoreFileOperations: Sendable {
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func freeBytes(at url: URL) -> Int64?
}

public struct SystemFileOperations: StoreFileOperations {
    public init() {}

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func freeBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

public enum StoreError: Error, Equatable, Sendable {
    /// The app bundle's voice files fail validation: "Reinstall Cáptalo".
    case bundleInvalid(ValidationFailure)
    /// Not enough free space: "Cáptalo needs N MB free to install its voice."
    case installFailed(needBytes: Int64)
    /// The installed version is damaged but still in use; repair runs after release.
    case damagedButLeased
    case activationFailed(String)
}

/// In-process reader leases on store version directories (one consumer
/// process per store root, so leases never cross processes).
public final class LeaseRegistry: Sendable {
    private let counts = Mutex<[String: Int]>([:])

    public init() {}

    public final class Lease: Sendable {
        public let directory: URL
        private let registry: LeaseRegistry
        private let released = Mutex(false)

        init(directory: URL, registry: LeaseRegistry) {
            self.directory = directory
            self.registry = registry
        }

        public func release() {
            let first = released.withLock { done -> Bool in
                defer { done = true }
                return !done
            }
            if first { registry.end(directory) }
        }

        deinit { release() }
    }

    public func lease(_ directory: URL) -> Lease {
        counts.withLock { $0[Self.key(directory), default: 0] += 1 }
        return Lease(directory: directory, registry: self)
    }

    public func isLeased(_ directory: URL) -> Bool {
        counts.withLock { ($0[Self.key(directory)] ?? 0) > 0 }
    }

    fileprivate func end(_ directory: URL) {
        counts.withLock { counts in
            let key = Self.key(directory)
            counts[key] = max((counts[key] ?? 1) - 1, 0)
            if counts[key] == 0 { counts[key] = nil }
        }
    }

    static func key(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
}

/// An exclusive lock on a file, held until released or the process exits.
public final class FileLock: Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Blocks until the lock is free (activation).
    public static func acquire(_ url: URL) throws -> FileLock {
        try open(url, nonBlocking: false)!
    }

    /// Returns nil when another holder has it (consumer lock).
    public static func tryAcquire(_ url: URL) throws -> FileLock? {
        try open(url, nonBlocking: true)
    }

    private static func open(_ url: URL, nonBlocking: Bool) throws -> FileLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw StoreError.activationFailed("cannot open \(url.lastPathComponent): errno \(errno)") }
        if flock(fd, LOCK_EX | (nonBlocking ? LOCK_NB : 0)) != 0 {
            let error = errno
            close(fd)
            if nonBlocking, error == EWOULDBLOCK { return nil }
            throw StoreError.activationFailed("cannot lock \(url.lastPathComponent): errno \(error)")
        }
        return FileLock(descriptor: fd)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// The versioned voice store (plan phase 3, review R6 and V2-6): validated
/// staging, atomic activation, quarantine-and-replace repair with rollback,
/// reader leases and retention of current, previous and leased versions.
/// Every write stays under `root`.
public final class ModelStore: Sendable {
    public static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.thecreativetoken.captalo/Models", isDirectory: true)

    public let root: URL
    public let leases: LeaseRegistry
    private let files: StoreFileOperations

    public init(root: URL = ModelStore.defaultRoot, leases: LeaseRegistry = LeaseRegistry(), files: StoreFileOperations = SystemFileOperations()) {
        self.root = root.standardizedFileURL
        self.leases = leases
        self.files = files
    }

    public var lockURL: URL { root.appendingPathComponent(".lock") }
    public var consumerLockURL: URL { root.appendingPathComponent(".consumer.lock") }
    private var currentURL: URL { root.appendingPathComponent("current") }
    private var previousURL: URL { root.appendingPathComponent("previous") }

    public func directory(for hash: String) -> URL {
        root.appendingPathComponent(hash, isDirectory: true)
    }

    /// The active version, if `current` names one that validates.
    public func currentDirectory(for manifest: ModelManifest) -> Result<URL, ValidationFailure>? {
        guard let hash = readMarker(currentURL), hash == manifest.contentHash else { return nil }
        let directory = directory(for: hash)
        if let failure = ManifestValidator.validate(directory, against: manifest) { return .failure(failure) }
        return .success(directory)
    }

    /// Installs (if needed) and activates `manifest` from `source`, the app bundle's copy.
    @discardableResult
    public func activate(from source: URL, manifest: ModelManifest) throws -> URL {
        if let failure = ManifestValidator.validate(source, against: manifest) {
            throw StoreError.bundleInvalid(failure)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lock = try FileLock.acquire(lockURL)
        defer { withExtendedLifetime(lock) {} }

        recoverInterruptedWork()
        let hash = manifest.contentHash
        let target = directory(for: hash)
        if FileManager.default.fileExists(atPath: target.path),
           ManifestValidator.validate(target, against: manifest) == nil {
            try setCurrent(hash)
            reclaim(keeping: hash)
            return target
        }

        let need = manifest.totalBytes + manifest.totalBytes / 10
        if let free = files.freeBytes(at: root), free < need {
            throw StoreError.installFailed(needBytes: need)
        }
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            for file in manifest.files {
                try files.copyItem(at: source.appendingPathComponent(file.path), to: staging.appendingPathComponent(file.path))
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            if (error as NSError).isDiskFull { throw StoreError.installFailed(needBytes: need) }
            throw StoreError.activationFailed("copy failed: \((error as NSError).code)")
        }
        if let failure = ManifestValidator.validate(staging, against: manifest) {
            try? FileManager.default.removeItem(at: staging)
            throw StoreError.bundleInvalid(failure)
        }

        if FileManager.default.fileExists(atPath: target.path) {
            // Damaged version: quarantine it, then move the staged copy in.
            guard !leases.isLeased(target) else {
                try? FileManager.default.removeItem(at: staging)
                throw StoreError.damagedButLeased
            }
            let quarantine = root.appendingPathComponent(".quarantine-\(hash)-\(UUID().uuidString)", isDirectory: true)
            try files.moveItem(at: target, to: quarantine)
            do {
                try files.moveItem(at: staging, to: target)
            } catch {
                try? files.moveItem(at: quarantine, to: target)
                try? FileManager.default.removeItem(at: staging)
                throw StoreError.activationFailed("replacement failed; the previous files were restored")
            }
        } else {
            do {
                try files.moveItem(at: staging, to: target)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw StoreError.activationFailed("activation move failed")
            }
        }
        try setCurrent(hash)
        reclaim(keeping: hash)
        return target
    }

    /// Removes staging leftovers and resolves lone quarantines after a crash.
    private func recoverInterruptedWork() {
        for entry in entries() {
            let name = entry.lastPathComponent
            if name.hasPrefix(".staging-") {
                try? FileManager.default.removeItem(at: entry)
            } else if name.hasPrefix(".quarantine-"), let hash = Self.quarantineHash(name) {
                let target = directory(for: hash)
                if FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: entry)
                } else {
                    try? files.moveItem(at: entry, to: target)
                }
            }
        }
    }

    /// Keeps current, the most recent previous valid version and every leased version.
    private func reclaim(keeping current: String) {
        let previous = readMarker(previousURL)
        for entry in entries() {
            let name = entry.lastPathComponent
            let isVersion = Self.isHash(name)
            let isLeftover = name.hasPrefix(".staging-") || name.hasPrefix(".quarantine-")
            guard isVersion || isLeftover else { continue }
            if isVersion, name == current || name == previous || leases.isLeased(entry) { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func setCurrent(_ hash: String) throws {
        let old = readMarker(currentURL)
        if let old, old != hash, FileManager.default.fileExists(atPath: directory(for: old).path) {
            try writeMarker(old, to: previousURL)
        }
        try writeMarker(hash, to: currentURL)
    }

    private func writeMarker(_ value: String, to url: URL) throws {
        let temporary = root.appendingPathComponent(".\(url.lastPathComponent)-\(UUID().uuidString)")
        try Data((value + "\n").utf8).write(to: temporary)
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw StoreError.activationFailed("cannot write \(url.lastPathComponent)")
        }
    }

    private func readMarker(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func entries() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }

    static func isHash(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    static func quarantineHash(_ name: String) -> String? {
        let parts = name.dropFirst(".quarantine-".count)
        let hash = String(parts.prefix(64))
        return isHash(hash) ? hash : nil
    }
}

extension NSError {
    var isDiskFull: Bool {
        (domain == NSCocoaErrorDomain && code == NSFileWriteOutOfSpaceError)
            || (domain == NSPOSIXErrorDomain && code == Int(ENOSPC))
            || (underlyingErrors.contains { ($0 as NSError).isDiskFull })
    }
}
