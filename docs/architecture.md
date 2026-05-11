# AuraShift Architecture

## Top-Level Structure

### App
Application entry point, lifecycle, root navigation, model-container setup, and high-level composition.

### Core
Cross-cutting foundations such as environment setup, constants, app configuration, and shared infrastructure that should not belong to a specific feature.

### DesignSystem
Reusable visual tokens, components, layout rules, and styling primitives shared across the product.

### Models
Pure domain models and value types used across features and services.

### Services
Business-facing service interfaces and implementations, including future analytics preparation, insight engines, and AI orchestration boundaries.

### Storage
Local persistence entities, seed data, mapping, and app-level storage integration.

### Features
Feature modules grouped by product area: Dashboard, Statistics, Calendar, Shifts, and future Trends/Insights surfaces.

### Shared
Reusable utilities and non-UI helpers that do not justify a dedicated feature module.

### Resources
Assets, localized strings, configuration resources, and static data files.

### Tests
Unit tests, mapping tests, service tests, and later UI tests where real logic warrants coverage.

## Project Configuration
- Project generation is defined in `project.yml`.
- `AuraShift.xcodeproj` is generated from `project.yml` using XcodeGen.
- The project currently contains two targets: `AuraShift` and `AuraShiftTests`.

## Current App Entry Flow
- `AuraShiftApp` installs a SwiftData model container for `ShiftRecord`.
- `AuraShiftApp` launches `AppRootView`.
- `AppRootView` owns a minimal `TabView`.
- Dashboard tab: `NavigationStack` -> `DashboardRootView`.
- Statistics tab: `NavigationStack` -> `StatisticsRootView`.
- Calendar tab: `NavigationStack` -> `CalendarRootView`.
- Shifts tab: `NavigationStack` -> `ShiftsRootView`.

## Storage Boundary
- `AuraShift/Storage/ShiftRecord.swift` is the first persisted SwiftData entity.
- `ShiftRecord` currently owns only local shift source data needed by the MVP.
- `ShiftRecordDraft` owns creation/edit/duplicate/default/date-shortcut/reusable-values/date-shift validation and mapping for the current Shifts forms.
- `ShiftRecordSeeder` owns the narrow seed-if-empty path.
- SwiftData entities should be mapped into UI-facing domain/content values before reaching feature views.
- Dashboard, Statistics, Calendar, and Shifts derive their display state from persisted records or fallback providers; they do not persist feature card content.

## Shared Deterministic Helpers
- `CurrentWeekShiftSummaryProvider` filters persisted `ShiftRecord` values into the current week, sorts them deterministically, counts shifts, totals hours, and formats hours text.
- Dashboard, Statistics, and Calendar use `CurrentWeekShiftSummaryProvider` for consistent current-week count/hour behavior.
- `AuroraSummaryShaper` is a deterministic, non-AI summary shaper used for local summary copy.
- These helpers are not an analytics engine, repository layer, AI layer, or global state-management system.

## Dashboard Data Flow
- Dashboard models live in `AuraShift/Models/Dashboard`.
- Fallback/mock dashboard content lives in `AuraShift/Features/Dashboard/DashboardMockDataProvider.swift`.
- `DashboardRootView` reads local `ShiftRecord` values with SwiftData.
- `DashboardStoredShiftContentProvider` maps stored shifts into the narrow persisted-derived home surface: next-shift anchor, current-week count, planned hours, source, operational notes, and local summary copy.
- Broader Dashboard metrics and activity areas remain fallback/mock-backed until real data sources exist.

## Statistics Data Flow
- Statistics models live in `AuraShift/Models/Statistics`.
- Fallback/mock statistics content lives in `AuraShift/Features/Statistics/StatisticsMockDataProvider.swift`.
- `StatisticsRootView` reads local `ShiftRecord` values with SwiftData.
- `StatisticsStoredShiftContentProvider` maps stored shifts into narrow current-week stored-shift and planned-hours metrics.
- Broader period summary, highlights, distribution/readout, charts, and analytics remain deferred.

## Calendar Data Flow
- Calendar feature code lives in `AuraShift/Features/Calendar`.
- `CalendarRootView` reads local `ShiftRecord` values with SwiftData.
- Calendar is now month-first: it renders a 6-week / 7-day grid with neighboring month days, selected/today states, compact shift presence, and a selected-day inspector.
- Calendar can open the existing Shifts add sheet with the selected day prefilled.
- Calendar persists nothing independently; saving still flows through the existing Shifts add path and SwiftData `ShiftRecord` model context.
- Calendar does not own edit, delete, duplicate, drag/drop, recurrence, templates, notifications, sync, onboarding, settings, AI, or a scheduling engine.

## Shifts Data Flow
- Shifts models live in `AuraShift/Models/Shifts`.
- Fallback/mock shifts content lives in `AuraShift/Features/Shifts/ShiftsMockDataProvider.swift`.
- `ShiftsRootView` reads stored shifts with SwiftData.
- `ShiftsStoredContentProvider` maps stored records into `ShiftsContent`.
- `ShiftsStoredRecordGrouper` owns Upcoming/Past grouping, Flat chronological ordering, and Flat day-header grouping.
- `ShiftsAddShiftSheet`, `ShiftsEditShiftSheet`, and `ShiftRecordDetailView` own the current narrow create/edit/duplicate/delete/detail interaction surfaces.
- No Shifts repository exists yet because the current SwiftData path remains simple enough to keep local.

## Local Build Tooling
- `scripts/build-local.sh` and `scripts/test-local.sh` are the conservative local wrappers for repeated Codex build cycles.
- Both wrappers call `scripts/cleanup-lite.sh` before execution.
- `scripts/run-local-xcode.sh` builds from a temporary workspace copy under `${TMPDIR}/aurashift-runner-workspaces` by default and removes that copy automatically on exit.
- `.aura-local` remains the project-local location for runner logs and test result bundles.
- The runner excludes heavy or disposable folders from temporary copies, including `.aura-local`, `DerivedData`, `build`, `.build`, `Pods`, `Packages`, `*.xcresult`, and `xcuserdata`.
- `scripts/deep-clean.sh` exists for manual recovery only and must not run automatically.

## Test Target
- `AuraShiftTests` uses the root `Tests` folder.
- Tests should stay focused on deterministic logic, storage/draft mapping, grouping, summary helpers, and provider behavior.
- Do not add meaningless tests only to increase volume.

## Architectural Rules
- Prefer SwiftUI for rendering and composition.
- Use MVVM only where it improves clarity and testability.
- Keep business logic out of views.
- Keep models and services framework-light where possible.
- Add capabilities by extending modules, not rewriting the shell.
- Keep persistence boundaries narrow and explicit.
- Keep future AI behind service boundaries and out of views.
- Avoid repository, protocol, routing, analytics-engine, or state-management abstractions until real pressure justifies them.
