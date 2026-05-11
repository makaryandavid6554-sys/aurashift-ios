# AuraShift

AuraShift is a SwiftUI iOS app for shift-aware personal statistics, operational planning, trend context, and future AI-assisted recommendations.

## Current Product Direction
- Month-first calendar planning inspired by SuperShift.
- Calm premium hierarchy and data confidence inspired by Revolut.
- Native adaptive refinement aligned with modern iOS behavior.
- Local-first MVP discipline with clear separation between real persisted data, deterministic summaries, and future AI.

## Current MVP
- Four top-level tabs: Dashboard, Statistics, Calendar, and Shifts.
- Local SwiftData-backed `ShiftRecord` persistence.
- Month-first Calendar planner with a 6-week / 7-day grid, selected-day inspector, and add-from-day flow through the existing Shifts add sheet.
- Shifts CRUD, duplicate, detail, Grouped/Flat presentation, and compact helper actions.
- Narrow current-week summaries on Dashboard and Statistics.
- Deterministic local summary shaping through `AuroraSummaryShaper`.

## Source Of Truth
- Canonical implementation and roadmap docs live in `docs/`.
- GitHub-backed markdown in this repository is the source of truth for product direction, current status, and implementation reality.
- Plan changes are not considered complete until the relevant `docs/` files are updated in GitHub.

## Key Docs
- `docs/current-status.md`
- `docs/mvp-plan.md`
- `docs/backlog.md`
- `docs/project-context.md`
- `docs/codex-rules.md`

## Current Priorities
- Finish manual runtime QA for the current MVP surfaces.
- Fix only confirmed runtime issues before adding new product scope.
- Preserve the month-first planner direction and premium adaptive presentation across light and dark mode.
