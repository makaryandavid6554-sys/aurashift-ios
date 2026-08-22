# AuraShift Codex Rules

## Working Rules
- Work in complete product milestones, not artificial micro-steps.
- Implement the full requested slice end-to-end when it is safe: code, integration, verification, and canonical documentation.
- Prefer momentum and a working user-facing result over incremental presentation-only polish.
- Treat GitHub-backed markdown in `docs/` as the app-repo source of truth for implementation reality.
- Do not rely on separate local-only documentation assumptions.
- Do not treat a plan change as complete until the affected `docs/` files are updated in the GitHub repository.
- Do not rewrite architecture without approval.
- Explain risky changes before applying them.
- Keep progress and final reports concise: outcome, verification, and real blockers only.
- Do not add business logic inside SwiftUI views.
- Prefer reusable structures over one-off shortcuts.
- Preserve a clean, premium product direction.

## Delivery Discipline
- Start from the requested user-facing result and change all necessary layers in one coherent milestone.
- Do not split straightforward work into separate analysis, scaffold, polish, and cleanup steps.
- Make reasonable implementation decisions without stopping for minor clarification when product direction and existing architecture provide enough context.
- Run focused tests during implementation and one proportionate build/test verification at milestone completion.
- Update `docs/current-status.md` after completed milestones, not after every minor edit.
- Update `docs/mvp-plan.md`, `docs/backlog.md`, and other canonical docs only when scope, priorities, architecture, or product direction actually changes.
- Any plan or roadmap change must be synchronized to GitHub before it is considered complete.
- Do not create temporary step-history notes, verbose implementation diaries, or repetitive status entries.

## Change Discipline
- Avoid uncontrolled rewrites.
- Allow focused refactoring when it removes a real blocker or makes the whole milestone simpler.
- Preserve working behavior outside the milestone scope.
- Call out risks, assumptions, and missing project wiring explicitly.
- Preserve the smaller canonical documentation set in `docs/README.md`.
