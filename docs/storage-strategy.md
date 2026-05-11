# AuraShift Storage Strategy

## Current Position
- SwiftData is the selected MVP persistence path.
- Persistence currently exists only for the narrow local Shifts slice and persisted-shift-derived summaries.
- `ShiftRecord` is the first persisted entity.
- `ShiftRecordDraft` owns current creation/edit/duplicate/default/date-shortcut/reusable-values/date-shift validation and mapping.
- `ShiftRecordSeeder` owns the narrow seed-if-empty path.
- Shifts, Calendar, Dashboard, and Statistics consume persisted shift records only through narrow, explicit presentation paths.
- Dashboard and Statistics still keep broader fallback/mock-backed content until real analytics/data sources exist.
- `AppMockSnapshotProvider` remains available for fallback context outside the persisted Shifts slice.

## Why SwiftData
- AuraShift is SwiftUI-first and iOS-local for the MVP.
- The current persistence need is small: local shift records only.
- SwiftData keeps the first storage slice lightweight without introducing custom file storage, Core Data boilerplate, sync, cloud backup, or repositories before they are needed.

## Current Persisted Entity
`ShiftRecord` owns only the current source data needed by the MVP:
- id
- role/title
- location
- note
- kind
- start date
- end date / duration-derived timing

Workload summaries, statistics highlights, dashboard cards, Calendar view state, and local summary copy are derived outputs and should not be persisted as standalone entities in the current MVP.

## Current Consumers
- Shifts reads, creates, edits, duplicates, deletes, groups, and presents local `ShiftRecord` values.
- Calendar reads persisted shifts into a month-first planner grid and can start the existing Shifts add flow with a selected day prefilled.
- Dashboard derives a narrow home-screen slice from persisted shifts: next shift, this-week count, planned hours, source, operational notes, and deterministic local summary copy.
- Statistics derives narrow this-week planned-hours and stored-shift metrics from persisted shifts.
- `CurrentWeekShiftSummaryProvider` provides shared current-week count/hour behavior for Dashboard, Statistics, and Calendar.

## Boundaries
- Do not persist Dashboard, Statistics, Calendar, or Aurora view content.
- Do not make storage own display copy, card structure, tones, or layout-specific content.
- Do not introduce repositories until SwiftData usage becomes complex enough to justify a wrapper.
- Do not replace `AppMockSnapshot` with a global state framework.
- Do not use the first storage slice as a reason to add notifications, AI, onboarding, settings, migrations, sync, cloud backup, recurrence, templates, or bulk-management features.
- Keep supported shift kinds limited to `Standard`, `Early`, `Late`, and `Standby` until broader work-type management is explicitly approved.
- Keep Calendar persistence behavior limited to reading stored shifts and opening the existing Shifts add sheet with a selected day.
- Keep Dashboard and Statistics persisted-derived behavior narrow and honest.

## Deferred Storage Work
- Broader SwiftData schema design.
- Migration policy.
- Sync and cloud backup.
- Account-backed state.
- Import/export.
- Richer shift metadata such as pay rates, custom work types, colors, tags, or employer/location entities.
- Recurrence/templates/presets.
- Archive, undo, recovery, and bulk operations.
- Persisted analytics entities.
- AI-generated or recommendation history.

## Verification Status
- Earlier manual QA confirmed the initial Shifts persistence path, add flow, edit flow, delete flow, no-shift behavior, Grouped/Flat presentation, kind picker, and duplicate flow.
- Recent productization changes have primarily been build-verified and code-reviewed.
- Full manual runtime QA for the current month-first Calendar, Shifts forms/detail polish, Dashboard/Statistics summaries, and light/dark/narrow-screen behavior remains pending.

## Next Storage-Safe Step
Do not broaden storage. Run manual runtime QA first, then fix only confirmed local persistence or presentation issues.
