# AuraShift Runtime QA Process

## Purpose
This document defines the lightweight runtime QA execution and issue-tracking process for the current MVP slice. It is procedural only: it does not add product behavior, product scope, UI changes, persistence changes, AI, charts, sync, notifications, onboarding, settings, templates, recurrence, or calendar editing.

Use this process with `docs/manual-qa-checklist.md`, then record results in `docs/qa-log.md`.

## Execution Order
1. Confirm the source state and build used for testing.
2. Confirm device or simulator stability before beginning the checklist.
3. Run baseline launch and tab navigation checks.
4. Run Shifts workflow checks with controlled test data.
5. Run Dashboard, Statistics, and Calendar persisted-summary checks.
6. Run current-week wording and visual consistency checks.
7. Log every failed or partial check with severity, reproducibility, and affected scenario.
8. Summarize pass/fail/partial status in `docs/qa-log.md`.

## Runtime Scenarios

### Empty State
- No persisted shifts are available in the active local store.
- Expected focus: Shifts empty state, Dashboard zero/empty persisted surfaces, Statistics zero current-week metrics, and Calendar empty current-week state.

### In-Week State
- At least one persisted shift starts inside the current week.
- Expected focus: current-week count/hours agreement across Dashboard, Statistics, Calendar, and Aurora/Dashboard copy.

### Out-of-Week State
- Persisted shifts exist, but none start inside the current week.
- Expected focus: zero-week current-week behavior without implying local data is missing entirely.

### Multi-Shift State
- Multiple persisted shifts exist, including at least two in-week records with different kinds/durations and at least one out-of-week record.
- Expected focus: ordering, grouping, Flat day headers, current-week filtering, and planned-hours totals.

## Test Data Reset Guidance
- Prefer a clean install or a cleared app container before a full QA pass.
- If starter records appear, use them only to confirm seeded-state behavior; then edit or delete them to create controlled scenarios.
- Use normal Shifts CRUD flows to create test data when possible, because this verifies real user paths and persisted updates together.
- Avoid relying on mock/fallback content as proof of persisted behavior.
- When a scenario requires no records, delete all visible local shifts and confirm the empty-state surfaces before continuing.
- When a scenario requires out-of-week-only records, edit or create shifts so every persisted start date falls outside the current week.

## Stable vs Exploratory Areas

### Stable-Gate Areas
These areas should block MVP readiness if they fail in normal use:
- App launch and tab navigation.
- Shifts add, detail, edit, delete, and duplicate flows.
- Required-field validation and Save availability.
- SwiftData persistence across relaunch.
- Current-week count/hour consistency across Dashboard, Statistics, and Calendar.
- Calendar read-only behavior.

### Exploratory Areas
These areas should be reviewed, but small copy/layout imperfections usually do not block core MVP readiness unless they create confusion or broken workflows:
- Premium visual consistency across cards, labels, and empty states.
- Dashboard broader mock/fallback sections.
- Statistics broader mock/fallback sections.
- Aurora/Dashboard copy tone, as long as it remains deterministic and non-AI.
- Spacing polish on small devices.

## Severity Classification
- `blocker`: Prevents launch, navigation to a core tab, saving/editing/deleting persisted shifts, or causes data loss/crash in a primary flow.
- `major`: Breaks an important MVP workflow or produces incorrect persisted/current-week data while the app remains usable.
- `minor`: Localized issue with copy, layout, ordering, or edge-state behavior that does not prevent task completion.
- `polish`: Visual or wording refinement that improves perceived quality but does not affect correctness or usability.

## Reproducibility
- `always`: Reproduces every time with the listed steps.
- `often`: Reproduces most of the time, but not every run.
- `intermittent`: Reproduces inconsistently; include frequency and device/simulator details.
- `once`: Seen once; keep as an observation unless it recurs or affects critical data.

## Issue Log Template
Use this shape inside `docs/qa-log.md` when a check fails or is partial:

```text
Issue:
- ID:
- Severity: blocker / major / minor / polish
- Reproducibility: always / often / intermittent / once
- Scenario: empty / in-week / out-of-week / multi-shift / general
- Area: Dashboard / Statistics / Shifts / Calendar / App shell / Docs
- Device or simulator:
- OS version:
- Build/source state:
- Steps to reproduce:
- Expected:
- Actual:
- Screenshots or notes:
- Suggested next action:
```

## Example Issue
```text
Issue:
- ID: QA-001
- Severity: major
- Reproducibility: always
- Scenario: in-week
- Area: Dashboard
- Device or simulator: iPhone 16 Pro simulator
- OS version: iOS 26.4
- Build/source state: Step 42 source, local debug build
- Steps to reproduce: Create two in-week shifts totaling 14h, open Dashboard.
- Expected: Dashboard current-week planned hours shows 14h and matches Calendar/Statistics.
- Actual: Dashboard shows 0h.
- Screenshots or notes: Not captured.
- Suggested next action: Investigate Dashboard current-week summary provider wiring.
```

Do not invent issues. Only log defects, risks, or observations that were actually seen during runtime QA.
