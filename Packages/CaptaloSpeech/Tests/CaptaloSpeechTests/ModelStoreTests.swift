import Foundation
import Synchronization
import Testing
@testable import CaptaloSpeech

/// Fault injection at the store's own file-operation boundary.
final class FaultyFiles: StoreFileOperations, Sendable {
    let real = SystemFileOperations()
    let diskFullAfterCopies = Mutex<Int?>(nil)
    let failMovesInto = Mutex<String?>(nil)
    let copies = Mutex(0)
    let free = Mutex<Int64?>(nil)

    func copyItem(at source: URL, to destination: URL) throws {
        let fail = diskFullAfterCopies.withLock { limit -> Bool in
            guard let remaining = limit else { return false }
            if remaining == 0 { return true }
            limit = remaining - 1
            return false
        }
        if fail { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        copies.withLock { $0 += 1 }
        try real.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        if let name = failMovesInto.withLock({ $0 }), destination.lastPathComponent == name,
           source.lastPathComponent.hasPrefix(".staging-") {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        }
        try real.moveItem(at: source, to: destination)
    }

    func freeBytes(at url: URL) -> Int64? {
        free.withLock { $0 } ?? real.freeBytes(at: url)
    }
}

/// A synthetic voice bundle written into a temporary directory.
struct Fixture {
    let base: URL
    let bundle: URL
    let root: URL
    let manifest: ModelManifest

    init(version: String = "v1") throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("captalo-store-\(UUID().uuidString)")
        bundle = base.appendingPathComponent("bundle-\(version)")
        root = base.appendingPathComponent("Models")
        try Self.write(bundle, [
            "kokoro/stage1.mlmodelc/model.bin": "stage one \(version)",
            "kokoro/vocab.json": "{\"a\": 1}",
            "kokoro/voices/af_heart.bin": String(repeating: "h", count: 512),
        ])
        manifest = try ModelManifest.scan(bundle, voices: ["af_heart"])
    }

    static func write(_ directory: URL, _ files: [String: String]) throws {
        for (path, contents) in files {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    func entries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
    }

    func corrupt(_ path: String, in directory: URL) throws {
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent(path))
    }

    func cleanup() { try? FileManager.default.removeItem(at: base) }
}

@Suite(.serialized) struct ModelStoreTests {
    @Test func freshInstallActivatesAtomically() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(active == store.directory(for: f.manifest.contentHash))
        #expect(store.currentDirectory(for: f.manifest) == .success(active))
        #expect(!f.entries().contains { $0.hasPrefix(".staging-") })
        #expect(ManifestValidator.validate(active, against: f.manifest) == nil)
    }

    @Test func interruptedStagingIsRemovedAndRetried() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try Fixture.write(f.root.appendingPathComponent(".staging-crashed"), ["partial": "x"])
        let store = ModelStore(root: f.root)
        try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(!f.entries().contains(".staging-crashed"))
        #expect(store.currentDirectory(for: f.manifest) != nil)
    }

    @Test func corruptExistingHashIsQuarantinedAndReplaced() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        try f.corrupt("kokoro/vocab.json", in: active)
        #expect(store.currentDirectory(for: f.manifest) == .failure(.sizeMismatch("kokoro/vocab.json")))
        try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(store.currentDirectory(for: f.manifest) == .success(active))
        #expect(!f.entries().contains { $0.hasPrefix(".quarantine-") })
    }

    @Test func failedReplacementRollsBackQuarantine() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let files = FaultyFiles()
        let store = ModelStore(root: f.root, files: files)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        try f.corrupt("kokoro/vocab.json", in: active)
        files.failMovesInto.withLock { $0 = f.manifest.contentHash }
        #expect(throws: StoreError.self) { try store.activate(from: f.bundle, manifest: f.manifest) }
        // The previous (damaged) files are back in place; no staging or quarantine is left.
        #expect(FileManager.default.fileExists(atPath: active.appendingPathComponent("kokoro/vocab.json").path))
        #expect(!f.entries().contains { $0.hasPrefix(".staging-") || $0.hasPrefix(".quarantine-") })
    }

    @Test func loneQuarantineRestoredAfterCrash() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        // Crash between "move to quarantine" and "move staging in".
        let quarantine = f.root.appendingPathComponent(".quarantine-\(f.manifest.contentHash)-crash")
        try FileManager.default.moveItem(at: active, to: quarantine)
        try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(store.currentDirectory(for: f.manifest) == .success(active))
        #expect(!f.entries().contains { $0.hasPrefix(".quarantine-") })
    }

    @Test func leasedStoreIsNotQuarantinedOrReclaimed() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        let lease = store.leases.lease(active)
        try f.corrupt("kokoro/vocab.json", in: active)
        #expect(throws: StoreError.damagedButLeased) { try store.activate(from: f.bundle, manifest: f.manifest) }
        #expect(FileManager.default.fileExists(atPath: active.path))
        lease.release()
        try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(store.currentDirectory(for: f.manifest) == .success(active))
    }

    @Test func upgradeDuringPlaybackActivatesForNextReading() throws {
        let v1 = try Fixture(version: "v1"); defer { v1.cleanup() }
        let v2Bundle = v1.base.appendingPathComponent("bundle-v2")
        try Fixture.write(v2Bundle, ["kokoro/stage1.mlmodelc/model.bin": "stage one v2", "kokoro/vocab.json": "{\"a\": 2}"])
        let v2 = try ModelManifest.scan(v2Bundle, voices: ["af_heart"])
        let store = ModelStore(root: v1.root)
        let old = try store.activate(from: v1.bundle, manifest: v1.manifest)
        let lease = store.leases.lease(old)  // the playing reading
        let new = try store.activate(from: v2Bundle, manifest: v2)
        #expect(store.currentDirectory(for: v2) == .success(new))
        #expect(FileManager.default.fileExists(atPath: old.path))
        lease.release()
        #expect(ManifestValidator.validate(old, against: v1.manifest) == nil)
    }

    @Test func retentionKeepsCurrentPreviousAndLeased() throws {
        let f = try Fixture(version: "v0"); defer { f.cleanup() }
        var manifests: [ModelManifest] = []
        var bundles: [URL] = []
        for version in 0..<4 {
            let bundle = f.base.appendingPathComponent("b\(version)")
            try Fixture.write(bundle, ["kokoro/vocab.json": "{\"v\": \(version)}"])
            bundles.append(bundle)
            manifests.append(try ModelManifest.scan(bundle, voices: ["af_heart"]))
        }
        let store = ModelStore(root: f.root)
        let d0 = try store.activate(from: bundles[0], manifest: manifests[0])
        let d1 = try store.activate(from: bundles[1], manifest: manifests[1])
        let lease = store.leases.lease(d1)
        let d2 = try store.activate(from: bundles[2], manifest: manifests[2])
        let d3 = try store.activate(from: bundles[3], manifest: manifests[3])
        let kept = Set(f.entries().filter(ModelStore.isHash))
        #expect(kept == [d1.lastPathComponent, d2.lastPathComponent, d3.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: d0.path))
        lease.release()
    }

    /// VAL-07: install A, install B, damage B, upgrade to C. The outgoing
    /// current (B) fails validation, so it never becomes the rollback version:
    /// valid A stays previous and damaged B is reclaimed.
    @Test func damagedOutgoingVersionNeverReplacesValidPrevious() throws {
        let f = try Fixture(version: "a"); defer { f.cleanup() }
        var versions: [(bundle: URL, manifest: ModelManifest)] = []
        for name in ["a", "b", "c"] {
            let bundle = f.base.appendingPathComponent("version-\(name)")
            try Fixture.write(bundle, ["kokoro/vocab.json": "{\"version\": \"\(name)\"}", "kokoro/voices/af_heart.bin": name])
            versions.append((bundle, try ModelManifest.scan(bundle, voices: ["af_heart"])))
        }
        let store = ModelStore(root: f.root)
        let a = try store.activate(from: versions[0].bundle, manifest: versions[0].manifest)
        let b = try store.activate(from: versions[1].bundle, manifest: versions[1].manifest)
        try f.corrupt("kokoro/vocab.json", in: b)
        let c = try store.activate(from: versions[2].bundle, manifest: versions[2].manifest)
        #expect(Set(f.entries().filter(ModelStore.isHash)) == [a.lastPathComponent, c.lastPathComponent])
        #expect(ManifestValidator.validate(a, against: versions[0].manifest) == nil)
        #expect(store.currentDirectory(for: versions[2].manifest) == .success(c))
        // A later healthy upgrade still promotes the valid outgoing version (C) and reclaims A.
        let dBundle = f.base.appendingPathComponent("version-d")
        try Fixture.write(dBundle, ["kokoro/vocab.json": "{\"version\": \"d\"}"])
        let d = try store.activate(from: dBundle, manifest: try ModelManifest.scan(dBundle, voices: ["af_heart"]))
        #expect(Set(f.entries().filter(ModelStore.isHash)) == [c.lastPathComponent, d.lastPathComponent])
    }

    /// N4: an unreadable manifest record is rewritten at the next activation,
    /// so its version can still become the rollback version.
    @Test func unreadableManifestRecordIsRewritten() throws {
        let f = try Fixture(version: "a"); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let a = try store.activate(from: f.bundle, manifest: f.manifest)
        let record = f.root.appendingPathComponent(".manifests/\(f.manifest.contentHash).json")
        try Data("not a manifest".utf8).write(to: record)
        try store.activate(from: f.bundle, manifest: f.manifest) // the next launch
        #expect(try ModelManifest.load(from: record) == f.manifest)
        let bBundle = f.base.appendingPathComponent("version-b")
        try Fixture.write(bBundle, ["kokoro/vocab.json": "{\"version\": \"b\"}"])
        let b = try store.activate(from: bBundle, manifest: try ModelManifest.scan(bBundle, voices: ["af_heart"]))
        #expect(Set(f.entries().filter(ModelStore.isHash)) == [a.lastPathComponent, b.lastPathComponent])
    }

    @Test func damagedStoreRefusesBeforeEngine() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        try f.corrupt("kokoro/voices/af_heart.bin", in: active)
        // The production path: no bundle to repair from, so the damaged store is refused.
        let setup = VoiceSetup(store: store, manifest: f.manifest)
        #expect(await setup.prepare(bundleModels: nil) == .state(.damaged))
        await #expect(throws: KokoroSynthesizer.StartError.notStarted) {
            _ = try await setup.synthesizer.synthesize("x", voice: "af_heart", speed: 1)
        }
    }

    @Test func repairReinstallsFromBundle() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        try FileManager.default.removeItem(at: active.appendingPathComponent("kokoro/vocab.json"))
        #expect(store.currentDirectory(for: f.manifest) == .failure(.missing("kokoro/vocab.json")))
        try store.activate(from: f.bundle, manifest: f.manifest)
        #expect(store.currentDirectory(for: f.manifest) == .success(active))
        // A repair from a bundle that itself fails validation is reported as such ("Reinstall Cáptalo").
        try f.corrupt("kokoro/vocab.json", in: active)
        try f.corrupt("kokoro/vocab.json", in: f.bundle)
        #expect(throws: StoreError.bundleInvalid(.sizeMismatch("kokoro/vocab.json"))) {
            try store.activate(from: f.bundle, manifest: f.manifest)
        }
    }

    @Test func secondConsumerCannotTakeStoreLock() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let first = try FileLock.tryAcquire(store.consumerLockURL)
        #expect(first != nil)
        #expect(try FileLock.tryAcquire(store.consumerLockURL) == nil)
        withExtendedLifetime(first) {}
    }

    /// Blocker regression (phase 3 review): a second instance must take the
    /// consumer lock before any repair, quarantine or reclaim, and must
    /// leave the first instance's store untouched.
    @Test func secondConsumerCannotRepairOrReclaim() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let store = ModelStore(root: f.root)
        let active = try store.activate(from: f.bundle, manifest: f.manifest)
        try f.corrupt("kokoro/vocab.json", in: active)
        let firstInstance = try #require(try FileLock.tryAcquire(store.consumerLockURL))
        let before = f.entries()
        let second = VoiceSetup(store: ModelStore(root: f.root), manifest: f.manifest)
        #expect(await second.prepare(bundleModels: f.bundle) == .secondInstance)
        #expect(f.entries() == before)
        #expect(store.currentDirectory(for: f.manifest) == .failure(.sizeMismatch("kokoro/vocab.json")))
        withExtendedLifetime(firstInstance) {}
    }

    @Test func diskFullReportsNeededSpaceAndLeavesNoStaging() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let files = FaultyFiles()
        files.diskFullAfterCopies.withLock { $0 = 1 }
        let store = ModelStore(root: f.root, files: files)
        let need = f.manifest.totalBytes + f.manifest.totalBytes / 10
        #expect(throws: StoreError.installFailed(needBytes: need)) { try store.activate(from: f.bundle, manifest: f.manifest) }
        #expect(!f.entries().contains { $0.hasPrefix(".staging-") })
        // The free-space check fails before any copy.
        files.diskFullAfterCopies.withLock { $0 = nil }
        files.free.withLock { $0 = 10 }
        #expect(throws: StoreError.installFailed(needBytes: need)) { try store.activate(from: f.bundle, manifest: f.manifest) }
        #expect(files.copies.withLock { $0 } == 1)
    }

    @Test func concurrentActivateInstallsOnce() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let files = FaultyFiles()
        let store = ModelStore(root: f.root, files: files)
        let bundle = f.bundle
        let manifest = f.manifest
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { _ = try? store.activate(from: bundle, manifest: manifest) }
            }
        }
        #expect(files.copies.withLock { $0 } == manifest.files.count)
        #expect(store.currentDirectory(for: manifest) != nil)
    }

    @Test func fetchScriptRejectsBytesNotMatchingManifest() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(ManifestValidator.validate(f.bundle, against: f.manifest) == nil)
        // Same size, different bytes: only the hash can catch it.
        let path = "kokoro/voices/af_heart.bin"
        try Data(String(repeating: "x", count: 512).utf8).write(to: f.bundle.appendingPathComponent(path))
        #expect(ManifestValidator.validate(f.bundle, against: f.manifest) == .hashMismatch(path))
    }
}
