# AuraShift QA Log

This is the compact canonical QA status for the current AuraShift MVP slice. It replaces the previous long step-by-step historical QA log so ongoing development can rely on a smaller, current, GitHub-ready source of truth.

Use `docs/manual-qa-checklist.md` for scenario coverage and `docs/runtime-qa-process.md` for severity, reproducibility, and issue logging.

## Current QA Status
- Latest known build verification: Step 72 ran `./scripts/build-local.sh` successfully.
- Latest implementation area needing runtime QA: Add/Edit/Duplicate Shift sheet productization.
- Manual runtime QA for the full current MVP slice remains pending.
- Simulator/device runtime confidence should not be claimed until the manual checklist is executed.

## Recently Verified By Build / Code Review
- Step 72: Add/Edit/Duplicate sheet productization preserved existing CRUD, Calendar selected-day prefill, Calendar `onSave`, SwiftData insert/update paths, persistence schema, recurrence/templates, AI, notifications/settings/sync/onboarding, and routing behavior.
- Step 71: Shift Detail productization preserved edit, duplicate, delete, confirmation, persistence, and navigation behavior.
- Step 70: Shifts rows were aligned with Calendar record language while preserving Grouped/Flat modes and existing detail navigation.
- Step 69: Calendar selected-day stored-shift rows were polished without adding Calendar edit/delete/duplicate behavior.
- Step 68: Calendar selected-day island action hierarchy was refined without changing Calendar non-editing scope.
- Step 67: Calendar save-to-selected-day continuity was refined while preserving the existing Shifts add path.
- Step 66: Calendar selected-day popover was productized into a day inspector without adding scheduling behavior.
- Step 65: Calendar month cells were polished around the SuperShift/Revolut/iOS26 direction without adding behavior.
- Step 63 and Step 64: Month-first Calendar foundation and header/navigation were build-verified.

## Previously Runtime-Confirmed Core Paths
- Shifts opened with starter records.
- Starter records did not duplicate on relaunch.
- Add flow saved a new shift and preserved it across relaunch.
- Dashboard and Statistics reflected the early persisted shift-derived slices.
- Read-only persisted shift detail path worked.
- Minimal edit and delete flows worked.
- No-shift behavior for Shifts, Dashboard, and Statistics worked.
- Grouped/Flat presentation control worked.
- Shift kind picker path worked.
- Minimal duplicate flow worked.

## Pending Manual Runtime QA
- Add, Edit, Duplicate, and Calendar-origin Add sheet hierarchy, helper actions, validation, Save disabled state, save/cancel behavior, light/dark contrast, and narrow-screen readability.
- Shift Detail header hierarchy, time/duration/kind clarity, note treatment, action hierarchy, delete confirmation, edit/duplicate/delete availability, light/dark contrast, and narrow-screen readability.
- Shifts row density, Grouped/Flat ergonomics, long role/location text, note truncation, detail tap affordance, and consistency with Calendar records.
- Calendar month-first grid with empty, populated, selected, today, neighboring-month, and multi-shift days.
- Calendar selected-day inspector placement, multi-shift scrolling, note wrapping, Add shift selected-day prefill, save return, cancel behavior, and unchanged non-editing scope.
- Dashboard home-screen hierarchy, next-shift prominence, current-week summary clarity, deterministic local summary tone, light/dark contrast, and narrow-screen wrapping.
- Statistics current-week hierarchy, metric usefulness, scope readability, no-chart presentation, light/dark contrast, and narrow-screen wrapping.
- Cross-surface product language around `This week`, `Planned hours`, `Stored shifts`, `Local`, and empty states.
- Full empty / in-week / out-of-week / multi-shift scenario pass from `docs/manual-qa-checklist.md`.

## Known QA Risks
- Current status relies heavily on build verification and code review for recent UI/productization steps.
- CoreSimulator instability has previously blocked full automated simulator execution.
- The workspace folder does not currently contain `.git` metadata in this local environment, so git-based app-repo verification may be limited locally.

## Issue Log Template

### Date
- YYYY-MM-DD

### Build / Scope
- Describe the build, branch, device/simulator, or step under test.

### Checks Performed
- List manual checks or automated tests run.
- Reference the scenario pass from `docs/manual-qa-checklist.md` where applicable.

### Result
- Pass / Fail / Partial

### Issues Found
- List defects, regressions, or unexpected behavior.
- Severity: `blocker`, `major`, `minor`, or `polish`.
- Reproducibility: `always`, `often`, `intermittent`, or `once`.

### Follow-Up
- Note the next action or linked fix step.
