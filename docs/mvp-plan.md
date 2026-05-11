# AuraShift MVP Plan

## MVP Purpose
The MVP should prove that AuraShift can become a premium, shift-aware personal analytics and operational-planning app without overbuilding AI, scheduling, sync, or analytics infrastructure too early.

The current MVP is not a throwaway demo. It should remain small, testable, and product-real enough for internal alpha review.

## Product Direction To Preserve
- SuperShift: month-first operational planner behavior, compact shift visibility, fast daily scanning, and day-focused interactions.
- Revolut: calm premium hierarchy, strict spacing discipline, restrained surfaces, and confident data presentation.
- iOS 26: native adaptive refinement, semantic color behavior, restrained motion, and modern platform feel.
- AuraShift should synthesize these references into its own strict operational analytics product. It must not become a direct SuperShift clone, a banking clone, a glass-heavy concept app, or an AI-first product.

## Current MVP Capabilities
- Stable SwiftUI app shell with Dashboard, Statistics, Calendar, and Shifts tabs.
- One `NavigationStack` per top-level tab.
- Reusable Aura design primitives for surfaces, section headers, tokens, and premium visual rhythm.
- Local SwiftData-backed `ShiftRecord` persistence as the first narrow storage slice.
- Shifts create, edit, duplicate, delete, detail, Grouped/Flat presentation, built-in shift kinds, inline validation, explicit defaults, Today/Tomorrow shortcuts, duplicate +1 day helper, and normal-add last-shift quick-fill.
- Month-first Calendar planner grid backed by persisted shifts, with selected/today states, compact shift pills, selected-day inspector, and add-from-day through the existing Shifts add sheet.
- Dashboard current-week shift count/hours/source, next-shift anchor, operational notes, and deterministic local summary copy from persisted-shift context where available.
- Statistics current-week planned-hours and stored-shifts review from persisted shifts where available.
- `CurrentWeekShiftSummaryProvider` as the shared deterministic helper for current-week shift filtering, ordering, count, and hours.
- `AuroraSummaryShaper` as a deterministic non-AI summary shaper.
- Build hygiene and local build wrappers documented for safe repeated development.
- Manual runtime QA process and checklist exist, but the latest surfaces still need device/simulator validation.

## MVP Exit Criteria
- App launches reliably into the four-tab shell.
- Shifts CRUD, duplicate, detail, Grouped/Flat presentation, add-from-Calendar, and empty states pass manual runtime QA.
- Calendar month-first planner supports fast current/month scanning without implying unsupported scheduling behavior.
- Dashboard and Statistics present honest current-week persisted-shift summaries without implying real charts, broad analytics, or AI.
- Local SwiftData persistence survives relaunch for created/edited/deleted shifts.
- Premium UI direction is consistent across Dashboard, Statistics, Calendar, and Shifts.
- Manual runtime QA is completed across empty, in-week, out-of-week, and multi-shift states.
- Known limitations are explicit and not hidden by copy or polish.

## Next MVP Work
- Run full manual runtime QA before adding more product scope.
- Fix only confirmed runtime issues from QA.
- Clarify real-versus-fallback content if testers still read Dashboard or Statistics as broader analytics than they are.
- Choose one next product increment only after QA: either Calendar planning depth or Shifts list management clarity.

## Deferred Until After MVP Validation
- AI, generated recommendations, Foundation Models integration, cloud AI, or predictive scheduling.
- Notifications, sync, cloud backup, onboarding, settings, accounts, import/export, or cross-device state.
- Recurrence, templates, saved presets, custom shift types, colors, tags, pay-rate logic, payroll analytics, or work-type management.
- Calendar-owned edit, delete, duplicate, drag/drop, recurrence, templates, or scheduling engine.
- Search, saved filters, bulk operations, undo, archive, recovery, or complex list management.
- Broad Dashboard/Statistics analytics, charts, graphs, trends, recommendations, or persisted analytical entities.
- Repository abstractions, migration policy, or broader storage architecture before the SwiftData path requires it.
