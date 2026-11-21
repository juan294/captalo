# Blind Explain review

Read only this guide, RUBRIC.md and your packet. Complete your judgment before discussing answers with anyone else. Work from the displayed source and fact sheet. Apply the frozen rubric to every factual claim. Record all required fact indices, including conditions and exceptions. Shortening an answer cannot excuse changing who acted, what caused an event or what the source leaves unknown.

Read the answer aloud or silently as spoken words. Choose the style you actually recognize: plain (literal explanation), examples (illustrative hypothetical instance), metaphors (explicit likeness), picture (an imagined scene) or indeterminate. A faithful answer may omit a requested illustration. The expected setting is private until the judgment is recorded.

Return a JSON object with a distinct opaque reviewer identifier in reviewer and an array in votes. For every assigned label copy label, item_sha256 and answer_sha256 exactly. Set verdict to pass, fail or uncertain. Set ambiguous and near_verbatim to booleans. Partition the zero-based fact indices between covered_facts and missing_facts. Put the style in perceived_style. Use reason for the source-grounded explanation of a failure, uncertainty or ambiguity. An empty reason is allowed on a clear pass.

If appointed as the third reader, review only the disputed labels independently from the two original readers. Use the same vote format and also provide a nonempty literal source_quote and a reason for each judgment. If you cannot settle a factual dispute, record uncertain. If you cannot recognize the style, record indeterminate. Keep quotes, reasons and reviewer identifiers inside the private review directory.
