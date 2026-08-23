# AuraShift Backlog

## Now
- Use legacy AuraShift / MoneyTracker as the primary UX blueprint for the next product steps without copying code or rewriting the new app.
- Deliver the Today + Calendar operational workflow as one complete milestone: selected day, month context, anchored day popover, day summary, shift preview, and fast shift creation.
- Add the adaptive semantic theme foundation with Light/Dark support and curated Citron, Graphite, Emerald, Cobalt, and Signal Orange accents.
- Verify the milestone across Dashboard, Calendar, and Shifts with focused tests, one build, and one runtime QA pass.
- Preserve `AuroraSummaryShaper` as deterministic, local, non-AI output.
- Keep documentation consolidated around the canonical docs listed in `docs/README.md`.

## Next
- Add quick actions incrementally in this order: shift, expense, income, event. Each needs explicit model/storage boundaries before implementation.
- Preserve and refine current Shifts CRUD while adapting the form flow toward the legacy operational speed and clarity.
- Introduce income/expense domain only after the quick-action UX boundary is clear.
- Upgrade Statistics toward legacy-style rings and financial analytics after income/expense data exists.
- Add Goals as a later product surface once financial data and statistics are stable.
- Keep bulk deletion, undo/recovery, and archive flows out until the narrow delete path proves stable.
- Keep Shifts presentation controls restrained; do not turn the list mode into search, complex filters, saved preferences, or a calendar workflow.
- Keep shift kind restrained to the built-in values; do not turn it into work-type management, custom colors/tags, or pay-rate logic.
- Keep duplication restrained; do not turn it into recurrence, templates, saved presets, or calendar workflows.
- Move broader Dashboard and Statistics analytics toward persisted-derived context later, after the narrow source paths prove stable.
- Stabilize simulator-side test execution separately from product code if automated runtime testing remains unreliable.

## Later
- Aurora / AI surfaces as local deterministic insight surfaces first, then future provider-backed intelligence only after the core data flows are stable.
- More / Settings / App lock / Export / Widgets as reference-backed later surfaces, not near-term blockers.
- Broader Dashboard and Statistics analytics derived from persisted shift, income, and expense context.
- Work-type management only after the current built-in kind path proves useful.
- Recurrence, templates, or saved presets only after the one-record duplicate path proves useful.
- Shift archive, undo, or bulk management after the narrow delete path is stable.
- Deterministic trend insight expansion.
- AI service boundary design and mock recommendation flows.
- QA expansion, tests, and release preparation.
- Arbitrary RGB/hex accent creation only if curated presets do not cover real user needs.

## Rejected / Risky
- Artificial micro-step development that produces repeated reports without a complete user-facing result.
- Large unrelated feature batches that mix multiple product domains in one milestone.
- Copying legacy MoneyTracker code directly into the new app.
- Rewriting the new SwiftUI/SwiftData architecture to match the legacy CoreData implementation.
- Embedding business logic directly inside SwiftUI views.
- Repository abstractions before the SwiftData path is complex enough to need them.
- Premature AI integration without clear service boundaries.
- Rewriting architecture midstream without explicit approval.
- Recoloring semantic statuses or every UI surface from one user-selected accent.
