# AuraShift Codex Rules

## Working Rules
- One step at a time.
- Keep changes small and safe.
- Update documentation after every meaningful step.
- Treat GitHub-backed markdown in `docs/` as the app-repo source of truth for implementation reality.
- Do not rely on separate local-only documentation assumptions.
- Do not treat a plan change as complete until the affected `docs/` files are updated in the GitHub repository.
- Do not rewrite architecture without approval.
- Explain risky changes before applying them.
- Every response must include documentation updates.
- Do not add business logic inside SwiftUI views.
- Prefer reusable structures over one-off shortcuts.
- Preserve a clean, premium product direction.

## Step Discipline
- Each step should have a clear purpose.
- Each step should leave the repository in a more structured state.
- Each step should update `docs/current-status.md` and any other affected documentation.
- Any step that changes product direction, implementation scope, or roadmap phase must also update the GitHub repository copies of those docs before the step is considered complete.
- Do not create temporary step-history notes when a canonical doc update is enough.

## Change Discipline
- Avoid uncontrolled rewrites.
- Prefer additive evolution over structural churn.
- Call out risks, assumptions, and missing project wiring explicitly.
- Preserve the smaller canonical documentation set in `docs/README.md`.
