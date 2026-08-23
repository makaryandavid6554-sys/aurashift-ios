# AuraShift MVP Plan

## MVP Purpose
The MVP should prove that AuraShift can become a premium, shift-aware personal analytics and operational-planning app without overbuilding AI, scheduling, sync, or analytics infrastructure too early.

The current MVP is not a throwaway demo. It should remain small, testable, and product-real enough for internal alpha review.

## Accelerated Delivery Strategy
- Build complete user-facing vertical slices instead of numbered micro-steps.
- Each milestone should include the necessary UI, data flow, persistence integration, focused tests, build verification, and canonical documentation update.
- Prioritize core operational workflows over repeated visual-only polish passes.
- Keep architecture clean, but do not introduce abstractions without a current product need.
- Manual QA should gate milestone completion and MVP release readiness, not interrupt every small implementation edit.
- Development reports should contain only the delivered outcome, verification result, and genuine remaining risk.

## Product Direction To Preserve
- Legacy AuraShift / MoneyTracker is now the primary product UX reference. Use it as a blueprint for Today-first workflow, month calendar behavior, anchored day popovers, quick actions, shift editing, statistics rings, goals, and Aurora surfaces; do not copy old code blindly or rewrite the new app from scratch.
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
- Dashboard Today/Daily operational home derived from existing persisted `ShiftRecord` values: no-shift, upcoming, active/current, completed, today count, planned hours, a shift-first Today quick action, and local Calendar/Shifts bridge copy.
- Statistics current-week planned-hours and stored-shifts review from persisted shifts where available.
- `CurrentWeekShiftSummaryProvider` as the shared deterministic helper for current-week shift filtering, ordering, count, and hours.
- `AuroraSummaryShaper` as a deterministic non-AI summary shaper.
- Build hygiene and local build wrappers documented for safe repeated development.
- Manual runtime QA process and checklist exist, but the latest surfaces still need device/simulator validation.

## MVP Exit Criteria
- App launches reliably into the four-tab shell.
- Shifts CRUD, duplicate, detail, Grouped/Flat presentation, add-from-Calendar, and empty states pass manual runtime QA.
- Calendar month-first planner supports fast current/month scanning without implying unsupported scheduling behavior.
- Dashboard presents an honest Today/Daily persisted-shift summary plus a shift-only add action, and Statistics presents an honest current-week persisted-shift summary without implying real charts, broad analytics, or AI.
- Local SwiftData persistence survives relaunch for created/edited/deleted shifts.
- Premium UI direction is consistent across Dashboard, Statistics, Calendar, and Shifts.
- Light and Dark mode work with the curated AuraShift accent presets without hardcoded theme colors or broken semantic contrast.
- Manual runtime QA is completed across empty, in-week, out-of-week, and multi-shift states.
- Known limitations are explicit and not hidden by copy or polish.

## Next MVP Work
- Complete the Today + Calendar operational workflow as one milestone: selected day, anchored day popover, useful day summary, shift preview, and fast shift creation through the existing SwiftData path.
- Establish semantic theme tokens and curated accent selection as part of that milestone so Today, Calendar, Shifts, navigation, and later Statistics share one adaptive color system.
- Stabilize the resulting cross-surface flow across Dashboard, Calendar, and Shifts with focused automated checks and one runtime QA pass.
- Add quick-action structure incrementally: shift first, then expense/income/event only after the data model and UX boundaries are explicitly defined.
- Upgrade Statistics from narrow stored-shift metrics toward legacy-style rings and financial analytics only after income/expense models exist.
- Restore Goals and Aurora later as dedicated product surfaces, not as MVP blockers.

## Deferred Until After MVP Validation
- Heavy AI, generated recommendations, Foundation Models integration, cloud AI, or predictive scheduling.
- Notifications, sync, cloud backup, onboarding, settings, accounts, import/export, or cross-device state.
- Recurrence, templates, saved presets, custom shift types, colors, tags, pay-rate logic, payroll analytics, or work-type management until the restored Today/Calendar flow is stable.
- Calendar-owned edit, delete, duplicate, drag/drop, recurrence, templates, or scheduling engine until the anchored day-popover and quick-action path is validated.
- Search, saved filters, bulk operations, undo, archive, recovery, or complex list management.
- Broad Dashboard/Statistics analytics, charts, graphs, trends, recommendations, goals, or persisted analytical entities until the transaction/financial domain is introduced deliberately.
- Repository abstractions, migration policy, or broader storage architecture before the SwiftData path requires it.
- Arbitrary RGB/hex theme editing, per-screen palettes, and user-authored color systems.
