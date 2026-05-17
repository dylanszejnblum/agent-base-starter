# `skills/pyme-admin-core/` — M2

The PyME Admin Core skill bundle that gets baked into the Hermes image.

Status: **not started.** Spec lives in the strategy vault at:

- `../../../agent-consultancy/PyME Admin Core — MVP Skill Stack.md`
- `../../../agent-consultancy/PyME Admin Core — Skill Specs v0.md`

## How this will be wired

Two options under consideration:

1. **Vendor** — copy the skill bundle into this directory. Simple, slow to update.
2. **Submodule** — add as a git submodule pointing to a separate skill-bundle repo. Cleaner, more work per change.

Decision deferred to M2. Until then this directory holds only the README + a `.gitkeep` so the path exists in the layout.

The PRD specifies the image is tagged as `<hermes-ver>-<bundle-ver>` — both halves must come from version-controlled source.
