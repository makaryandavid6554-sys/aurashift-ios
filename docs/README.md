# AuraShift Documentation

This folder is the canonical GitHub-ready documentation set for the AuraShift app repository.

## Source of Truth
- GitHub-backed markdown in this repository is the source of truth for implementation reality.
- Local editors, Obsidian, and chat summaries are editing or coordination layers only.
- If a local note conflicts with these docs, verify against this repository, current code, and explicit user instructions before acting.
- Changes to product direction, implementation scope, roadmap phase, or current status are not complete until the corresponding `docs/` files are updated in the GitHub repository.
- If local documentation and GitHub diverge, treat GitHub as stale and restore sync before continuing to use it as the source of truth.

## Canonical Docs
- `current-status.md`: current implementation state, verification status, known issues, and next safe step.
- `architecture.md`: current app structure, module boundaries, data flow, build tooling, and architectural rules.
- `mvp-plan.md`: current MVP scope, roadmap phases, exit criteria, and deferred work.
- `design-system.md`: premium UI direction, product reference direction, implemented visual language, and guardrails.
- `ai-strategy.md`: deterministic local insight boundaries and future AI-provider direction.
- `storage-strategy.md`: SwiftData persistence boundaries, current stored-shift scope, and deferred storage work.
- `build-hygiene.md`: lightweight cleanup, local build/test wrappers, and manual deep-clean policy.
- `manual-qa-checklist.md`: runtime QA scenarios for the current MVP slice.
- `runtime-qa-process.md`: QA execution process, severity, reproducibility, and issue-log template.
- `qa-log.md`: compact current QA status and recent verification checkpoints.
- `project-context.md`: stable product context and non-negotiable direction.
- `backlog.md`: current Now / Next / Later / Risky backlog framing.
- `codex-rules.md`: development-loop rules for Codex work in this repo.

## Consolidation Rule
Keep this set small. Prefer updating the canonical docs above over adding temporary notes, step-by-step history files, or overlapping planning snapshots.

## Sync Rule
- Always update GitHub repository docs when the plan changes.
- At minimum, plan-affecting work must update `docs/current-status.md` and `docs/mvp-plan.md`.
- Update `docs/backlog.md`, `docs/project-context.md`, `docs/architecture.md`, `docs/design-system.md`, or other canonical docs whenever the same change affects roadmap framing, product direction, architecture, or UI rules.
- A Codex step that changes plan or product direction is not done until the GitHub repo reflects those doc changes.
