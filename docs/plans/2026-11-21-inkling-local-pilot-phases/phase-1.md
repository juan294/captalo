# Phase 1. Freeze and rehearse the six-case experiment

**Entry.** An implementation request covers this phase. One local owner implements the experiment under Scripts with a single command, proposed name `Scripts/explain-inkling-pilot`, and a discoverable Python test under Scripts/tests. Use dependency injection for synthetic token events and clocks so the rehearsal works without Python MLX, weights, credentials or audio hardware. Reuse the existing verifier and blinding helpers where their contracts fit. Keep one run directory and one manifest. The owner accepts the rehearsal before the hardware run.

## Freeze the candidate

- Checkpoint `thinkingmachines/Inkling-2-Mini@ed40e7da625f594fc9c4990f5f66be24873c22d7`. The main tensor file is 19,526,019,168 bytes with SHA-256 `65e60f51aa1284d4fb022584908c315270334d991828bb774af60584523539d1`. Freeze the revision’s model index, configs, tokenizer and chat template. Use native mixed precision, three fixed passes, original weights, one process and text input. Disable tools, speculative decoding, image processing and cross-case context reuse. [Pinned model metadata](https://huggingface.co/api/models/thinkingmachines/Inkling-2-Mini/revision/ed40e7da625f594fc9c4990f5f66be24873c22d7?blobs=true)
- Runtime `jundot/mlx-lm@0c4c99192230f1943dd468d297f0b8a64ae7b7c2`, the original-weight implementation in upstream draft PR 2086. Before inference lock the compatible Python, mlx, tokenizer and dependency versions and record their artifact hashes, OS and architecture. Use shipped kernel selection. Review this specific source before installing it into an isolated environment. [Pinned MLX runtime](https://github.com/jundot/mlx-lm/tree/0c4c99192230f1943dd468d297f0b8a64ae7b7c2)
- Use greedy decoding, reasoning effort `none` (0.0), and the selected builder’s 4,096 generated-token ceiling including reasoning. Verify the actual rendered effort in the prompt. These settings favor a repeatable low-latency trial. The model may still reason internally. Record token IDs for prompt hashing and count reasoning tokens without writing their text. [Official template](https://huggingface.co/thinkingmachines/Inkling-2-Mini/blob/ed40e7da625f594fc9c4990f5f66be24873c22d7/chat_template.jinja) · [Historical token budget and request fields](../../../Packages/CaptaloCore/Sources/CaptaloCore/Explain/ExplainCandidate.swift#L67)

## Reproduce the requests

Run `Scripts/explain-candidate prepare` locally. Its preparation can serialize all adult fixtures. Select only the six ordered IDs below for generation, reading `openai-selected/prepared.json` from its ignored output. Validate each body against the Sol manifest’s **base_request_sha256**, which binds it to Terra’s selected input. Sol’s own wire hash includes its different model and effort. Preserve the exact UTF-8 content of `instructions` as the system message and `input` as the user message. Send neither provider metadata nor case IDs, expected facts, old answers or reviewer labels to Inkling. Hash the new rendered prompt and token sequence separately. [Prepare output](../../../Scripts/explain-candidate#L78) · [Six-row manifest](../../../Qualification/Explain/model-pilots/sol-selected-six-v1.json#L1)

| Order | Case ID | Source words |
| --- | --- | ---: |
| 1 | main-email-middle-metaphors | 33 |
| 2 | main-legal-middle-metaphors | 40 |
| 3 | main-textbook-simple-plain | 46 |
| 4 | main-minutes-middle-metaphors | 31 |
| 5 | main-handover-middle-metaphors | 32 |
| 6 | main-document3000-simple-plain | 3,000 |

Bind fixture manifest `4376d4b02fb5e80627fcf7342e5b9c0658c1c4d0ee8237cb9f52163bf6e480d3`, selected config `f36de885b0d86b415ae368406b83612e047a6322570e4e82c89c151a1a742d36`, and review guide `b39c30e448953ccf4cd68c9654b0a04f5722fe9f01aa2ae4e82c08eeead4aec0`. Verify the 3,000-word input reaches tokenization in full and fits with the output budget. Preserve start, middle and end exceptions for the reviewers.

```text
@ preparePilot(selectedBodies, priorManifest) -> orderedPreview
pre: fixture, configuration and guide digests match
do:
  1. validate the six IDs, order and base wire hashes
  2. parse each body and preserve both message strings
  3. compute the candidate identity from the pinned inputs and sampling contract
  4. emit the preview with settings, sizes and provenance
fail: duplicate, extra pilot row or mismatched content -> name the offending row
```

**Automated acceptance.** Include fixtures for wrong variant, reordered or duplicate IDs, wrong wire hash, omitted end of the long passage, implicit default effort, swapped roles and accidentally including the fact sheet. Replay final-only and thinking-then-final streams across token boundaries. Test that ordinary text resembling a control label stays text, premature EOF cannot count as EOS, and thinking/tool tokens cannot enter answers or the timer. With fabricated answers rehearse the complete blind join and threshold decisions in Phase 3. Exercise the stuck-state recoveries in the main plan. Run targeted tests and then sequential `make verify` on the exact implementation candidate.

**Manual acceptance.** An independent reviewer checks one prepared short Metaphors request and the long Plain request against the Swift builder and manifest. Confirm the preview identifies all six and states the download size. The phase has one implementation unit because serializer, stream and review checks share the experiment contract. Report the frozen preview and first-failure evidence.
