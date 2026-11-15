import CaptaloCore
import Foundation

extension CaptaloAppState {
    /// The read-selection shortcut (plan phase 2). The press records its
    /// source at once; capture and the stop gesture run in the request coordinator.
    func speakSelection() {
        guard accessibility.isProcessTrusted() else {
            accessibilityPermissionGranted = false
            updateStatus("Accessibility access required")
            onAccessibilityPermissionRequired?()
            return
        }
        accessibilityPermissionGranted = true
        if !isCaptureProbeActive, !canSpeak {
            updateStatus("Kokoro needs to be installed")
            if kokoroInstallationState == .downloadRequired { onKokoroDownloadRequired?() }
            return
        }
        let capture = self.capture
        let accessibility = self.accessibility
        let requests = self.requests
        #if DEBUG
        let probe = captureProbe
        #endif
        // The source is read off the main actor: a hung app cannot block the UI.
        Task.detached {
            guard let source = accessibility.currentSource() else { return }
            await requests.submit(kind: .selection, source: source) { token in
                let started = ContinuousClock.now
                #if DEBUG
                let outcome = if let probe {
                    await probe.measure(token) { await capture.capture(token) }
                } else {
                    await capture.capture(token)
                }
                #else
                let outcome = await capture.capture(token)
                #endif
                var layer: CaptureLayerKind?
                var characters = 0
                if case let .text(text, captured) = outcome { layer = captured; characters = text.count }
                PrivacyLog.record(.capture(kind: .selection, outcome: .init(outcome), layer: layer,
                                           characters: characters, elapsed: started.duration(to: .now)))
                if outcome == .permissionMissing {
                    await MainActor.run { CaptaloAppState.shared.refreshAccessibilityPermission() }
                }
                return outcome
            }
        }
    }

    var isCaptureProbeActive: Bool {
        #if DEBUG
        captureProbe != nil
        #else
        false
        #endif
    }

    /// Starts the inherited speech for a promoted session. Returns at once.
    func beginReading(_ text: String, token: SessionToken) {
        recordWords(in: text)
        let spokenText = applyingPronunciationRules(to: text)
        updateStatus("Generating audio")
        let requests = self.requests
        Task {
            guard await requests.isCurrent(token) else { return }
            do {
                try await speech.speak(
                    text: spokenText,
                    session: token.sessionGeneration,
                    onFirstAudio: { firstAudio in
                        Task { @MainActor in
                            guard await requests.isCurrent(token) else { return }
                            CaptaloAppState.shared.latestFirstAudio = firstAudio
                            CaptaloAppState.shared.finishDictationSession()
                            CaptaloAppState.shared.startDictationSession()
                            CaptaloAppState.shared.updateStatus("Speaking - first audio \(firstAudio.short)")
                        }
                    },
                    onError: { error in
                        Task { @MainActor in
                            guard await requests.isCurrent(token) else { return }
                            CaptaloAppState.shared.updateStatus("Playback error: \(error.localizedDescription)")
                        }
                    },
                    onPlaybackFinished: {
                        Task {
                            guard await requests.sessionFinished(token) else { return }
                            await MainActor.run {
                                CaptaloAppState.shared.finishDictationSession()
                                CaptaloAppState.shared.isPaused = false
                                CaptaloAppState.shared.updateStatus("Finished")
                            }
                        }
                    }
                )
            } catch {
                updateStatus("Could not speak: \(error.localizedDescription)")
            }
        }
    }

    func stopSpeaking() {
        finishDictationSession()
        Task { await requests.stopSession() }
        isPaused = false
        updateStatus("Stopped")
    }

    func togglePause() {
        Task {
            let paused = await speech.togglePause()
            isPaused = paused
            updateStatus(paused ? "Paused" : "Speaking")
        }
    }

    func jumpSection(by offset: Int) {
        Task {
            do {
                updateStatus(offset < 0 ? "Going to previous section..." : "Going to next section...")
                try await speech.jumpSection(
                    by: offset,
                    onFirstAudio: { firstAudio in
                        Task { @MainActor in
                            CaptaloAppState.shared.latestFirstAudio = firstAudio
                            CaptaloAppState.shared.finishDictationSession()
                            CaptaloAppState.shared.startDictationSession()
                            CaptaloAppState.shared.updateStatus("Speaking - first audio \(firstAudio.short)")
                        }
                    },
                    onError: { error in
                        Task { @MainActor in
                            CaptaloAppState.shared.updateStatus("Playback error: \(error.localizedDescription)")
                        }
                    },
                    onPlaybackFinished: {
                        Task { @MainActor in
                            CaptaloAppState.shared.finishDictationSession()
                            CaptaloAppState.shared.isPaused = false
                            CaptaloAppState.shared.updateStatus("Finished")
                        }
                    }
                )
            } catch {
                updateStatus("Could not change section: \(error.localizedDescription)")
            }
        }
    }

    func startDictationSession() {
        dictationSessionStartedAt = .now
    }

    func finishDictationSession() {
        guard let started = dictationSessionStartedAt else { return }

        totalDictationSeconds += started.duration(to: .now).seconds
        dictationSessionStartedAt = nil
        UserDefaults.standard.set(totalDictationSeconds, forKey: DefaultsKey.totalDictationSeconds)
    }
}
