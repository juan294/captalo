# Enroll, preview and delete a personal voice

In the Voice pane, offer My own voice on supported Macs. Explain that it is for the user's own English voice, give the verified download size before starting, and state where recording and processing happen. Consent precedes the download. Request microphone access only when Record is pressed. Add the microphone usage description and the audio-input entitlement for the recording process, and verify them on the signed app. Keep the recorder in the host so the helper needs no microphone access.

Record the displayed fixed prompt in a calm reading voice for about 20 seconds. Convert to 24 kHz mono. Allow replay and re-recording after an empty, clipped or interrupted take. The user confirms they read the displayed prompt. Store its exact text or immutable version with the clip. Use a different preview sentence to let the user judge the result. Give draft playback to the existing request coordinator and audio sink in this phase. Stop, a new reading or dismissal invalidates the preview and its late PCM. Accept makes the profile active. Cancelling a draft leaves the prior selection intact. The existing built-in sample action selects its voice immediately, so implement draft preview independently. [Current selection and sample](../../../Captalo/App/CaptaloAppStateVoice.swift#L44)

```
@ acceptDraft(draft, currentProfile) -> activeProfile
pre: explicit consent, complete recording, successful preview
do:
  1. validate the draft and immutable transcript
  2. write a complete private profile on the same volume
  3. replace the active profile atomically
  4. discard the superseded personal data and update the voice selection
fail: interrupted commit -> recover a complete accepted profile on relaunch
```

Keep weights separate from the profile. Display explicit download progress, cancellation and retry. Reserve space for the actual staged and installed bytes. Check expected names, byte counts and digests from an app-pinned manifest before publishing the directory. On relaunch recover only a valid completed install. Keep the profile and draft under nonsynced application support with private directory and file permissions (0700/0600) and backup exclusion. Discard incomplete recording drafts after cancellation or a crash. Delete my voice stops active work, releases conditioning and removes personal files and partial drafts. The UI states whether the public model remains and offers removal of that download. Deleting a voice restores the saved built-in choice for future requests.

**Automated acceptance.** Use installer fixtures with injected network, space, corruption and concurrent setup failures. Simulate two profiles, a failed replacement, restart and deletion while a preview is queued. Test Stop and starting a built-in read during preview. Inspect permissions, backup exclusion, cleanup and logs with synthetic markers. Cover successful retry and denial recovery for each state. Render the Voice pane for setup, recording, preview, ready and recoverable errors. Run make verify.

**Native acceptance.** Exercise the signed menu-bar app's microphone prompt, denial, settings recovery and a short consenting take. Confirm the previous working voice survives cancellation. Listen to the preview before accepting. The owner chooses when to provide their own recording.

**Work split.** [batch-eligible] The public model installer and fixture tests can proceed independently of recording, profile storage and their tests. Integrate the UI after both contracts are tested.
