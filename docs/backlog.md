# AuraShift Backlog

## Now
- Run the full manual runtime QA pass for Dashboard, Statistics, Calendar, and Shifts.
- Validate Add/Edit/Duplicate sheet productization on a stable simulator or physical device.
- Preserve `AuroraSummaryShaper` as deterministic, local, non-AI output.
- Keep documentation consolidated around the canonical docs listed in `docs/README.md`.

## Next
- Fix only confirmed runtime QA issues before adding broader scope.
- Decide one next product increment after QA: Calendar planning depth or Shifts list management clarity.
- Keep bulk deletion, undo/recovery, and archive flows out until the narrow delete path proves stable.
- Keep Shifts presentation controls restrained; do not turn the list mode into search, complex filters, saved preferences, or a calendar workflow.
- Keep shift kind restrained to the built-in values; do not turn it into work-type management, custom colors/tags, or pay-rate logic.
- Keep duplication restrained; do not turn it into recurrence, templates, saved presets, or calendar workflows.
- Move broader Dashboard and Statistics analytics toward persisted-derived context later, after the narrow source paths prove stable.
- Stabilize simulator-side test execution separately from product code if automated runtime testing remains unreliable.

## Later
- Broader Dashboard and Statistics analytics derived from persisted shift context.
- Work-type management only after the current built-in kind path proves useful.
- Recurrence, templates, or saved presets only after the one-record duplicate path proves useful.
- Shift archive, undo, or bulk management after the narrow delete path is stable.
- Deterministic trend insight expansion.
- AI service boundary design and mock recommendation flows.
- QA expansion, tests, and release preparation.

## Rejected / Risky
- Large feature builds before the app shell and structure are stable.
- Embedding business logic directly inside SwiftUI views.
- Repository abstractions before the SwiftData path is complex enough to need them.
- Premature AI integration without clear service boundaries.
- Rewriting architecture midstream without explicit approval.
