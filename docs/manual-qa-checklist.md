# AuraShift Manual QA Checklist

## Scope
This checklist covers the current MVP slice: Dashboard, Statistics, month-first Calendar, Shifts CRUD/detail/forms, persisted local shifts, deterministic local summaries, and light/dark/narrow-screen presentation.

Use this with `docs/runtime-qa-process.md`, then record real findings in `docs/qa-log.md`.

## Setup
- Run AuraShift from Xcode on a stable iOS simulator or physical device.
- Prefer a clean install or known local store before a full pass.
- Test light mode, dark mode, and a narrow-screen device class if available.
- Use four scenario states where possible: empty store, one in-week shift, multiple in-week shifts, and out-of-week-only shifts.

## Core App
- App launches without crash.
- Top-level tabs are visible and ordered: Dashboard, Statistics, Calendar, Shifts.
- Each tab keeps its own navigation state through a `NavigationStack`.
- Tab and navigation chrome remain calm and readable in light and dark mode.

## Shifts
- Empty state does not show mock shifts as local records.
- Add shift opens from the Shifts toolbar.
- Blank add defaults are understandable and editable.
- `Today` and `Tomorrow` shortcuts update only the draft day.
- `Use last shift values` appears only when a reusable persisted source exists and preserves the current draft start date/time.
- Role and Location validation keeps Save unavailable when invalid.
- New shifts save and appear immediately.
- Existing shifts open detail from Grouped and Flat modes.
- Edit updates role, location, kind, start, duration, and note.
- Duplicate opens a prefilled add-style sheet and saves as a new record without changing the source.
- Duplicate `Move start +1 day` changes only the copied draft start date.
- Delete shows confirmation, cancel preserves the record, confirm removes it.
- Grouped mode separates Upcoming and Past correctly.
- Flat mode shows chronological rows under day headers.
- Long role/location/note text remains readable and does not break layout.

## Calendar
- Calendar opens as the month-first planner grid, not the old weekly/list surface.
- Month header, previous/next controls, and Today control are clear.
- Today and selected-day states are visually distinct.
- Neighboring month days are readable but subdued.
- Empty days, single-shift days, and multi-shift days are understandable.
- Shift pills remain compact and readable.
- Selecting a day opens the selected-day inspector.
- Inspector shows date context, shift count/hours, and stored-shift rows where applicable.
- Empty-day Add shift opens the existing Shifts add sheet with the selected day prefilled.
- Populated-day Add another shift remains quieter than inspection content.
- Saving from Calendar-origin Add returns to refreshed selected-day context.
- Cancel does not imply that a shift was created.
- Calendar does not expose edit, delete, duplicate, drag/drop, recurrence, templates, notifications, sync, settings, onboarding, AI, or scheduling-engine behavior.

## Dashboard
- Dashboard shows honest current-week shift count, planned hours, source, and next-shift context where persisted data exists.
- Empty or out-of-week states show clear zero/local values without pretending mock data is persisted.
- Local deterministic summary copy does not imply AI or recommendations.
- Broader fallback sections remain calm and do not overclaim analytics maturity.
- Layout remains readable in light/dark/narrow-screen review.

## Statistics
- Statistics shows current-week planned hours and stored-shift count where persisted data exists.
- Empty or out-of-week states show clear zero/local values.
- Surface does not imply charts, graphs, recommendations, AI, or broad analytics that do not exist.
- Review highlights and scope/readout copy remain grounded and readable.
- Layout remains readable in light/dark/narrow-screen review.

## Cross-Surface Consistency
- `This week`, `Planned hours`, `Stored shifts`, `Next shift`, `Local`, and `Empty` language is used consistently.
- Calendar records, Shifts rows, and Shift Detail feel like the same object language.
- Add/Edit/Duplicate sheets feel consistent with Shifts rows and Calendar-origin context.
- No user-facing copy describes the product as a prototype, sample, placeholder, or implementation shell.

## Intentionally Unsupported
- AI or generated recommendations.
- Notifications.
- Sync or cloud backup.
- Onboarding and settings.
- Recurrence, templates, saved presets, or custom work types.
- Calendar-owned edit/delete/duplicate.
- Drag/drop scheduling.
- Search, complex filters, bulk operations, undo, archive, or recovery.
- Broad Dashboard/Statistics analytics and charts.
