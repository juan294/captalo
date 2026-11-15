import CaptaloCore
import Foundation

extension CaptaloAppState {
    /// The read-selection shortcut (plan phase 2). The press records its
    /// source at once; trust, capture and the stop gesture run in the coordinators.
    func speakSelection() {
        if !isCaptureProbeActive, !canSpeak {
            updateStatus("Kokoro needs to be installed")
            if kokoroInstallationState == .downloadRequired { onKokoroDownloadRequired?() }
            return
        }
        let capture = selectionCapture
        let accessibility = self.accessibility
        let requests = self.requests
        // The source is read off the main actor: a hung app cannot block the UI.
        // Without Accessibility trust there is no source; the coordinator then
        // returns .permissionMissing before any layer runs.
        Task.detached {
            let source = accessibility.currentSource() ?? InputSource(pid: 0, bundleID: nil, focusedElement: nil)
            await requests.submit(kind: .selection, source: source) { token in
                let outcome = await capture(token)
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
    func beginReading(_ session: SpeechPlaybackSession) {
        recordWords(in: session.text)
        let spokenText = applyingPronunciationRules(to: session.text)
        updateStatus("Generating audio")
        let requests = self.requests
        let token = session.token
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
                            guard await session.finished() else { return }
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
