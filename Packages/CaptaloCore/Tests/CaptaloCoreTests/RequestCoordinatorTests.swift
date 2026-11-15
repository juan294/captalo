import Testing
@testable import CaptaloCore

@Suite struct RequestCoordinatorTests {
    @Test func rapidPressesOnlyLastResolves() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let gate = Gate()
        let first = await coordinator.submit(coordinator.reservePress(), kind: .selection, source: sourceA) { _ in
            await gate.wait(); return .text("first", layer: .accessibility)
        }
        let second = await coordinator.submit(coordinator.reservePress(), kind: .selection, source: sourceA) { _ in
            await gate.wait(); return .text("second", layer: .accessibility)
        }
        await gate.open()
        await coordinator.waitForIdle()
        #expect(first != second)
        #expect(log.events == ["start 1:second"])
    }

    @Test func newInputDoesNotTouchPlayingSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let token = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(token, .text("reading", layer: .accessibility))
        let gate = Gate()
        _ = await coordinator.submit(coordinator.reservePress(), kind: .region, source: sourceB) { _ in await gate.wait(); return .cancelled }
        // The pending input exists, but the session is untouched until it resolves.
        #expect(log.events == ["start 1:reading"])
        #expect(await coordinator.currentSession != nil)
        await gate.open()
        await coordinator.waitForIdle()
        #expect(log.events == ["start 1:reading"])
    }

    @Test func textOutcomePromotesAndStopsOldSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(one, .text("one", layer: .accessibility)) == .promoted(SessionToken(sessionGeneration: 1)))
        let two = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(two, .text("two", layer: .menuCopy)) == .promoted(SessionToken(sessionGeneration: 2)))
        #expect(log.events == ["start 1:one", "stop 1:one", "start 2:two"])
    }

    @Test func stopGestureStopsSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(one, .text("same", layer: .accessibility))
        // Same captured text again: stop.
        let two = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(two, .text("same", layer: .accessibility)) == .stopped)
        #expect(await coordinator.currentSession == nil)
        // Confirmed empty selection while playing: stop.
        let three = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(three, .text("other", layer: .accessibility))
        let four = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(four, .nothingSelected) == .stopped)
        #expect(log.events == ["start 1:same", "stop 1:same", "start 2:other", "stop 2:other"])
        // Nothing selected while idle: silence, nothing to stop.
        let five = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(five, .nothingSelected) == .unchanged)
    }

    @Test func failedInputLeavesSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(one, .text("keep", layer: .accessibility))
        let outcomes: [CaptureOutcome] = [
            .failed(.ownershipUncertain), .unsupported(.modifiersHeld), .permissionMissing, .cancelled,
            .failed(.restoreFailed), .failed(.ocrTimedOut),
        ]
        for outcome in outcomes {
            let token = await coordinator.beginInput(kind: .selection, source: sourceA)
            #expect(await coordinator.resolve(token, outcome) == .unchanged)
        }
        // A region press never stops a reading, even with nothing found.
        let region = await coordinator.beginInput(kind: .region, source: sourceA)
        #expect(await coordinator.resolve(region, .nothingSelected) == .unchanged)
        #expect(log.events == ["start 1:keep"])
    }

    @Test func delayedOldResultIsDropped() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let old = await coordinator.beginInput(kind: .selection, source: sourceA)
        let new = await coordinator.beginInput(kind: .selection, source: sourceA)
        #expect(await coordinator.resolve(old, .text("late", layer: .accessibility)) == .dropped)
        #expect(await coordinator.resolve(new, .text("fresh", layer: .accessibility)) == .promoted(SessionToken(sessionGeneration: 1)))
        #expect(log.events == ["start 1:fresh"])
    }

    @Test func staleSessionCallbackDropped() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(one, .text("one", layer: .accessibility))
        let two = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(two, .text("two", layer: .accessibility))
        let stale = SessionToken(sessionGeneration: 1)
        // A session's own finish callback reaches the coordinator.
        #expect(await coordinator.isCurrent(stale) == false)
        #expect(await coordinator.sessionFinished(stale) == false)
        #expect(await coordinator.currentSession == SessionToken(sessionGeneration: 2))
        #expect(await coordinator.sessionFinished(SessionToken(sessionGeneration: 2)) == true)
        #expect(await coordinator.currentSession == nil)
    }

    @Test func sessionFinishCallbackEndsOnlyItsOwnSession() async {
        let finishers = FinisherBox()
        let coordinator = RequestCoordinator { token, content, finished in
            finishers.append(finished)
            return RecordingSession(name: "\(token.sessionGeneration):\(content.plainText)", log: EventLog())
        }
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(one, .text("one", layer: .accessibility))
        let two = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(two, .text("two", layer: .accessibility))
        #expect(await finishers.call(0) == false) // stale: session 1 was replaced
        #expect(await coordinator.currentSession == SessionToken(sessionGeneration: 2))
        #expect(await finishers.call(1) == true)
        #expect(await coordinator.currentSession == nil)
    }

    @Test func sampleAlwaysReplacesAndNeverStops() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        await coordinator.play(text: "Sample.")
        await coordinator.play(text: "Sample.")
        #expect(log.events == ["start 1:Sample.", "stop 1:Sample.", "start 2:Sample."])
    }

    @Test func manualStopStopsOnlyTheSession() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let one = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(one, .text("one", layer: .accessibility))
        let pending = await coordinator.beginInput(kind: .selection, source: sourceA)
        await coordinator.stopSession()
        #expect(await coordinator.currentSession == nil)
        #expect(await coordinator.isCurrent(pending))
        #expect(log.events == ["start 1:one", "stop 1:one"])
    }

    /// Promote A suspends while the old session stops; promote B wins in the
    /// meantime. A must never start, and B must not be stopped by A.
    @Test func interleavedPromotionsNeverStartAStaleHandle() async {
        let log = EventLog()
        let gate = Gate()
        let coordinator = RequestCoordinator { token, content, _ in
            GatedSession(name: "\(token.sessionGeneration):\(content.plainText)", log: log, stopGate: content == .text("old") ? gate : nil)
        }
        let first = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(first, .text("old", layer: .accessibility))
        let a = await coordinator.beginInput(kind: .region, source: sourceA)
        let promoteA = Task { await coordinator.resolve(a, .document([.paragraph("A")])) }
        try? await Task.sleep(for: .milliseconds(20))
        let b = await coordinator.beginInput(kind: .region, source: sourceA)
        _ = await coordinator.resolve(b, .document([.paragraph("B")]))
        await gate.open()
        _ = await promoteA.value
        #expect(!log.events.contains("start 2:A"))
        #expect(log.events.last == "start 3:B")
        #expect(!log.events.contains("stop 3:B"))
        #expect(await coordinator.currentSession == SessionToken(sessionGeneration: 3))
    }

    @Test func quitLetsOpenCleanupFinish() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let playing = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(playing, .text("playing", layer: .accessibility))
        let copySent = Gate()
        let release = Gate()
        _ = await coordinator.submit(coordinator.reservePress(), kind: .selection, source: sourceA) { _ in
            // Models a clipboard transaction after Copy: its cleanup ignores cancellation.
            await Task {
                await copySent.open()
                await release.wait()
                log.append("cleanup done")
            }.value
            return .text("copied", layer: .menuCopy)
        }
        await copySent.wait()
        let shutdown = Task { await coordinator.shutdown() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!log.events.contains("cleanup done"))
        await release.open()
        await shutdown.value
        // Cleanup finished before shutdown returned; the copied text was discarded; the session stopped.
        #expect(log.events == ["start 1:playing", "cleanup done", "stop 1:playing"])
    }
}

@Suite struct ReadingIdentityTests {
    @Test func sameCapturedTextTogglesStop() async {
        #expect(ReadingIdentity(capturedText: "a b") == ReadingIdentity(capturedText: "a b"))
        #expect(ReadingIdentity(capturedText: "a b") != ReadingIdentity(capturedText: "a  b"))
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        for _ in 0..<2 {
            let token = await coordinator.beginInput(kind: .selection, source: sourceA)
            _ = await coordinator.resolve(token, .text("Toggle me.", layer: .accessibility))
        }
        #expect(log.events == ["start 1:Toggle me.", "stop 1:Toggle me."])
    }
}

/// VAL-01: a press reserves its order when the shortcut fires; the source
/// lookup runs afterwards and can finish in any order.
@Suite struct PressOrderTests {
    /// Lookup A blocks, press B completes, then A's lookup finishes. B stays
    /// current; A runs no capture (no Copy, speech or overlay work).
    @Test(arguments: [InputKind.selection, .region])
    func lateLookupOfOlderPressHasNoEffect(kindA: InputKind) async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let a = coordinator.reservePress()
        let lookupA = Gate()
        let pressA = Task {
            await lookupA.wait()
            return await coordinator.submit(a, kind: kindA, source: sourceA) { _ in
                log.append("capture A"); return kindA == .region ? .document([.paragraph("A")]) : .text("A", layer: .accessibility)
            }
        }
        let b = coordinator.reservePress()
        let tokenB = await coordinator.submit(b, kind: .selection, source: sourceB) { _ in
            log.append("capture B"); return .text("B", layer: .accessibility)
        }
        await coordinator.waitForIdle()
        await lookupA.open()
        let tokenA = await pressA.value
        await coordinator.waitForIdle()
        #expect(tokenA == nil)
        #expect(log.events == ["capture B", "start 1:B"])
        #expect(await coordinator.currentSession == SessionToken(sessionGeneration: 1))
        if let tokenB { #expect(await coordinator.isCurrent(tokenB)) } else { Issue.record("press B was rejected") }
    }

    /// Two presses on the playing text: the newer one stops the reading, and
    /// the older one's late lookup must not start it again.
    @Test func twoPressesOnSameTextStopOnce() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let playing = await coordinator.beginInput(kind: .selection, source: sourceA)
        _ = await coordinator.resolve(playing, .text("same", layer: .accessibility))
        let a = coordinator.reservePress()
        let b = coordinator.reservePress()
        _ = await coordinator.submit(b, kind: .selection, source: sourceA) { _ in .text("same", layer: .accessibility) }
        await coordinator.waitForIdle()
        _ = await coordinator.submit(a, kind: .selection, source: sourceA) { _ in .text("same", layer: .accessibility) }
        await coordinator.waitForIdle()
        #expect(log.events == ["start 1:same", "stop 1:same"])
        #expect(await coordinator.currentSession == nil)
    }

    /// A reservation supersedes the pending input at once, before its own lookup ends.
    @Test func reservationSupersedesPendingInput() async {
        let log = EventLog()
        let coordinator = makeCoordinator(log: log)
        let gate = Gate()
        let pending = await coordinator.submit(coordinator.reservePress(), kind: .selection, source: sourceA) { _ in
            await gate.wait(); return .text("old", layer: .accessibility)
        }
        _ = coordinator.reservePress()
        if let pending { #expect(await coordinator.isCurrent(pending) == false) } else { Issue.record("first press was rejected") }
        await gate.open()
        await coordinator.waitForIdle()
        #expect(log.events.isEmpty)
    }
}
