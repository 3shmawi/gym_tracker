# Designs

Approved specs for big features, one file per feature:
`docs/designs/<feature>.md`. Each one is drafted with `/egm:egm-draft`,
reviewed with `/egm:egm-review` and approved before any code is written
(`CLAUDE.md` → "Design before code for big features").

Keep a spec as the record of what was decided and why. When the feature
changes later, update its `docs/features/<feature>.md`; run
`/egm:egm-drift-report` to find docs that no longer match the code.
