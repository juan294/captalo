# Step 1 — Freeze the control and the selected instruction

Start from the [amendment](../2026-11-21-explain-qualification-recovery.md) and the request builder at `Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainCandidate.swift:17` on `ef075b2`. One integration owner handles the Swift builder, probe and freeze command sequentially because their byte contracts are shared.

1. Save the current OpenAI configuration and reproduce the entire ordered request set from the frozen Swift serializer. Bind a read-only control preparation to its configuration digest, fixture digest and request-set digest. When a variant becomes current, default freeze/prepare must still reproduce the original control, including the old target in the user message. Keep the Anthropic configuration and all its request bytes identical.
2. For the OpenAI treatment, assemble common fidelity rules, one depth clause and one style clause. Keep actors, limits, unknowns, prerequisites and remote exceptions. Describe comparisons as illustrations and preserve the instruction to distinguish observations from causes. The only variable across the control and this treatment is the instruction design and its corresponding numeric target where the legacy floor conflicts with Middle. Pin endpoint, model, revision, decoding options, output limit, streaming flags, order, sources, profiles and fact sheets.
3. Count source words with the existing whitespace rule at `Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainInput.swift:40`. Use the parent plan’s 50%, 40% and 75% soft targets with rounding up and a floor of 20. For Middle compute a strict maximum of source words minus one and clamp the advisory target to it. Count the entire answer including its analogy. Give the maximum as a trusted integer. Keep source and listener profile in encoded user data. The trusted prompt may contain only reviewed fixed text, validated enum selections and derived integer counts.
4. Prepare the optional example variant before any generation or unblinding. Add one short, signalled metaphor from an unrelated synthetic topic only to the Metaphors clause. All other requests must match the selected instruction byte for byte. Record the difference in request-set identity. Have an independent reader check that no source, answer, unusual phrase or distinctive fact pattern from the corpus, historical calibration or held-out passages was reused. Use the existing fixture custodian for the held-out overlap check so the prompt author receives only a pass or a disqualification.
5. Version the assembly rules, ordered clause text and example as applicable. Freeze deterministic configuration bytes, fixture digest, every serialized request digest and ordered request-set digest. Reuse the product serializer through `Packages/CaptaloCore/Sources/ExplainQualificationProbe/main.swift:18` and `Scripts/explain-candidate:36`. A change to a clause, an option or an example must invalidate the corresponding candidate. Preserve the old fixed-string configuration format for historical verification.

```text
@ instruction(input, variant) -> trusted instruction and encoded input
pre: validated source and profile, known depth and style
do:
  1. compute the advisory target for the selected depth
  2. compute the Middle maximum and clamp its advisory target
  3. emit the common rules and the selected clauses with their budgets
  4. emit source and profile in the user message
br: example variant and Metaphors selected -> include the frozen illustration
fail: one-word Middle treatment -> local recovery before dispatch
```

**Automated acceptance.** Add red tests before editing the builder. Exercise all 12 depth/style pairs, repeated serialization, quoted prompt-like source/profile text, tabs/newlines, empty input, 1, 2, 20, 31, 40, 3,000 and 3,001 words. Check that a 31-word Middle passage specifies a maximum of 30 and a 40-word passage specifies 39. Check both sources of numeric guidance agree on tiny passages. Compare control and Anthropic snapshots with the originals. Verify that tampering with a serialized body, including one outside the six-case subset, changes or invalidates its identity. Run independent review, repair, simplify and sequential `make verify` at the exact commit.

**Human acceptance.** Read the actual wire instructions for a short Middle Metaphors request and a long Simple Plain request. Confirm the active instruction contains only the requested settings and the common constraints, and that the unrelated example was checked before use. Record the candidate hashes and full check result for Step 2. This accepts the experiment inputs only.
