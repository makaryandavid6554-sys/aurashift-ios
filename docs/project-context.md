# AuraShift Project Context

## What AuraShift Is
AuraShift is an iOS SwiftUI app for shift-aware personal statistics, operational planning, trend context, and future AI-assisted recommendations.

The product should feel strict, clean, premium, and useful. It is closer to a modern analytics or finance-grade operational tool than a playful lifestyle tracker.

## Product Identity
- Month-first operational planner direction inspired by SuperShift.
- Calm premium hierarchy and data confidence inspired by Revolut.
- Native adaptive refinement inspired by iOS 26.
- Local-first MVP discipline.
- Clear distinction between real persisted data, deterministic local summaries, and future AI.

## Target User
- Shift-based or variable-schedule workers who need fast clarity around upcoming work, planned hours, and schedule rhythm.
- Users who value calm operational insight over gamification.
- Users who may later benefit from trend explanations, recommendations, and schedule-aware intelligence.

## MVP Boundaries
- Stable SwiftUI app shell.
- Dashboard, Statistics, Calendar, and Shifts surfaces.
- Local SwiftData-backed shifts as the first persisted source.
- Month-first Calendar planner backed by stored shifts.
- Narrow current-week summaries on Dashboard and Statistics.
- Deterministic local summary shaping, not AI.
- Manual QA discipline before broader feature expansion.

The MVP does not require live AI, cloud sync, notifications, onboarding, settings, recurrence, templates, broad analytics, or full scheduling automation.

## Long-Term Direction
- Richer shift and work-pattern analytics.
- Trend tracking across schedule, workload, recovery, and consistency.
- Explainable local insight generation.
- Optional future AI-assisted recommendations.
- Provider path for AI should remain staged: deterministic/rule-based first, on-device later, cloud only if justified.

## What Must Not Be Broken
- Small-step development discipline.
- Clear separation between SwiftUI views, domain values, storage entities, deterministic helpers, and future services.
- SwiftData boundaries around `ShiftRecord`.
- Honest product copy that does not imply unsupported AI, scheduling, charting, or recommendation behavior.
- Premium visual direction.
- GitHub-backed docs as the source of truth for implementation reality.
