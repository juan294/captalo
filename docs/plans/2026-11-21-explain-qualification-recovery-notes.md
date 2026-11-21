# Explain qualification recovery implementation

## Step 1 — Request variants

The integration owner merged the accepted local plan at f74063d into the retained implementation worktree at 1b9bed8. No project implementation overlay was present. The product builder, probe, freeze/check/prepare command and regression tests now reproduce all 83 adult requests for each variant. The OpenAI control (193ac7aa) and Anthropic (7fd44755) match their historical bytes. Selected (f36de885) and example (462eda34) differ only on Metaphors rows. Full identities are the SHA-256 of each checked-in candidate file.

The independent fixture reader rejected an eight-word source paired with a longer example. The replacement describes a shuttle and bobbin and shortens its 19-word source to 13 words. The reader checked topic, distinctive wording and fact overlap against the corpus, held-out material, calibration and prior answers. A second reviewer checked actual legal Middle Metaphors and long Simple Plain wire requests and all four ordered request sets. The review identified three missing regression assertions. The repaired suite checks exclusive clauses for each of 12 settings, corruption of pilot and nonpilot wire bytes, and one-word recovery through the probe. The independent follow-up approved the repairs.

Red evidence for the missing variant API and missing candidate snapshots is retained under the worktree's ignored .local/recovery-* logs. The first green attempt exposed an escaped interpolation in the test expectation. Correcting it produced four passing Swift tests. The simplify pass reused the existing serializer and word counts, checked naming and removed duplicate freeze-test invocations. Verification covers synthetic requests and local code only. Juan retains the listening verdict. The integration owner retains the worktree and its earlier raw evidence through qualification.

## Deviations

The canonical OpenAI snapshot continues to represent the historical control. Candidate preparation emits two additional named snapshots. This lets existing tools and archived evidence continue to resolve the old identity while the comparison is pending.
