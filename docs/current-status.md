# Current Status

## Current Step
GitHub documentation source-of-truth restoration.

This is an infrastructure/documentation-only step. No Swift source, Xcode project configuration, persistence behavior, app navigation, or product functionality was changed.

## Current Product State
- AuraShift is a SwiftUI iOS app for shift-aware personal statistics, operational planning, trend context, and future AI-assisted recommendations.
- The app currently exposes four top-level tabs: Dashboard, Statistics, Calendar, and Shifts.
- The active product direction is a SuperShift + Revolut + iOS 26 hybrid: month-first operational planning, calm premium hierarchy, native adaptive refinement, and strict avoidance of playful or overloaded UI.
- Calendar is now month-first, using a 6-week / 7-day planner grid with neighboring month days, selected/today states, compact shift pills, and a selected-day inspector.
- Shifts is the strongest current workflow surface, with local SwiftData-backed create, edit, duplicate, delete, detail, Grouped/Flat presentation, and add-from-Calendar support.
- Dashboard and Statistics have narrow current-week persisted-shift summaries plus fallback/mock-backed broader content.
- Deterministic local summary copy exists through `AuroraSummaryShaper`; it is not AI.

## Canonical Documentation State
- `docs/README.md` now defines the canonical app-repo documentation set and source-of-truth rule.
- `docs/README.md` and `docs/codex-rules.md` now explicitly require plan/status changes to be reflected in the GitHub repository before a step is considered complete.
- `docs/current-status.md`, `docs/architecture.md`, `docs/mvp-plan.md`, `docs/design-system.md`, `docs/ai-strategy.md`, `docs/storage-strategy.md`, `docs/build-hygiene.md`, `docs/manual-qa-checklist.md`, `docs/runtime-qa-process.md`, `docs/qa-log.md`, `docs/project-context.md`, `docs/backlog.md`, and `docs/codex-rules.md` are the surviving app-repo docs.
- The former UX readiness checkpoint was removed because it was a Step 50 snapshot; its durable conclusions are now represented in current status, MVP plan, QA docs, and design-system guardrails.
- Historical step-by-step QA noise was consolidated from `docs/qa-log.md` into a compact current QA status and recent checkpoint summary.

## Implementation Status
- Project generation is defined in `project.yml`; `AuraShift.xcodeproj` is generated with XcodeGen.
- `AuraShiftApp` installs a SwiftData model container for `ShiftRecord`.
- `AppRootView` owns the minimal `TabView` shell with one `NavigationStack` per top-level surface.
- Local persisted shift records live in `AuraShift/Storage/ShiftRecord.swift`.
- Draft creation/edit/duplicate behavior is owned by `ShiftRecordDraft` and the Shifts add/edit sheets.
- Current-week persisted-shift count/hour behavior is shared through `CurrentWeekShiftSummaryProvider`.
- Calendar reads persisted shifts directly and remains calendar-planner-facing, not a full scheduling engine.
- Dashboard and Statistics consume only narrow persisted-derived shift summaries; broader analytics remain deferred.

## Tests / Verification Status
- No build was run for this documentation-only step because no Swift, Xcode, script, or project files were changed.
- Documentation verification was performed by auditing markdown files under `docs/`, reviewing headings and product-direction references, and checking for obsolete references after cleanup.
- GitHub repository documentation verification is part of this step because the app plan is expected to be pulled from GitHub rather than local-only docs.
- Prior implementation state records indicate `./scripts/build-local.sh` passed for Step 72.
- Manual runtime QA remains required before internal alpha confidence.

## Known Issues
- The workspace folder does not currently contain its own `.git` repository metadata in this local environment.
- Manual runtime QA is still pending for the latest Shifts form productization, Shift Detail polish, Shifts/Calendar record parity, Calendar month-first interactions, Dashboard/Statistics scanability, and light/dark/narrow-screen behavior.
- Dashboard and Statistics remain intentionally narrow and partially fallback/mock-backed.
- Calendar is month-first and add-capable through the existing Shifts sheet, but still has no Calendar-owned edit, delete, duplicate, drag/drop, recurrence, templates, notifications, sync, onboarding, settings, AI, or scheduling engine.
- Shifts has local CRUD and helper flows, but no recurrence, templates, saved presets, custom work types, pay-rate logic, search, complex filters, bulk operations, undo, archive, sync, or migration policy beyond the initial local schema.
- `Use last shift values` treats "last" as the persisted record with the latest `startDate`, not the most recently created record.

## Next Recommended Step
Run the manual runtime QA pass from `docs/manual-qa-checklist.md` using `docs/runtime-qa-process.md`, then record real findings in `docs/qa-log.md`.
