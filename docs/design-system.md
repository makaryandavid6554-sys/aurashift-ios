# AuraShift Design System Direction

## Principles
- Strict.
- Minimal.
- Premium.
- Banking-inspired cleanliness.
- Month-first operational clarity.
- No unnecessary glow.
- Restrained animation.
- Reusable components before one-off styling.

## Product Reference Direction
- SuperShift: month-first operational planner behavior, fast shift visibility, compact schedule scanning, and day-focused interactions.
- Revolut: premium hierarchy, calm confidence, strict spacing discipline, and clean operational UI.
- iOS 26: modern native feel, semantic adaptive colors, restrained material usage, and smooth visual rhythm.
- AuraShift should synthesize these references into a premium operational planner for variable-income workers; it should not become a direct SuperShift copy, bank app, glass-heavy concept UI, or AI-first product.

## Visual Character
AuraShift should feel precise, calm, and credible. Layouts should use generous but efficient spacing, strong typographic hierarchy, subtle contrast, and deliberate emphasis instead of decorative effects.

## Current Implemented Baseline
- `AuraTheme` provides baseline tokens for background, surfaces, text hierarchy, accent usage, spacing, corner radius, and subtle card shadow.
- `AuraCard` is the reusable surface primitive for premium containers.
- `AuraSectionHeader` is the shared heading primitive for structured module sections.
- App shell chrome uses existing Aura background/surface tokens and a minimal `TabView`.
- Dashboard, Statistics, Calendar, and Shifts share a restrained card, section, metric, and operational-row language.
- Calendar is now the primary month-first planning surface, not the older weekly/list hybrid.
- Shifts rows, Calendar selected-day records, and Shift Detail share the same planner-record language: time/duration first, role-led hierarchy, compact kind, secondary location, contained notes, and restrained borders.
- Add/Edit/Duplicate shift forms use compact headers, clear record/time/note sections, contained Calendar-origin context, explicit helper actions, and local validation rows.

## Surface Guidance
- Dashboard should prioritize current-week context, next shift, local source clarity, and deterministic local summaries before broader analytics.
- Statistics should present current-week stored-shift review honestly and avoid chart-like or AI-like claims until real calculations exist.
- Calendar should stay month-first, compact, readable, and operational. It may show stored shift presence and a selected-day inspector, but it must not imply unsupported scheduling behavior.
- Shifts should feel like a daily operational command center while preserving the existing narrow CRUD and detail paths.

## Copy And Tone
- Prefer concrete, grounded labels: `This week`, `Planned hours`, `Stored shifts`, `Next shift`, `Local`, and `Empty`.
- Avoid user-facing prototype language such as `sample`, `placeholder`, `shell`, `deferred`, or implementation-heavy explanations.
- Do not imply AI, recommendations, scheduling automation, charts, or broad analytics unless those capabilities actually exist.

## Design Guardrails
- Do not introduce UI that feels gamified, playful, or casual.
- Do not rely on glow, excessive glass, or decorative gradients to create premium feel.
- Do not let one-off screen styling bypass shared tokens and components.
- Prefer small local alignment fixes over broad component rewrites until repetition is stable across real screens.
- Keep Calendar month cells calm and dense enough for quick scanning: clear day number, compact shift presence, muted neighboring month days, restrained selected/today emphasis, and readable light/dark behavior.
- Keep Calendar selected-day inspectors anchored, compact, summary-led, readable for empty/single/multi-shift days, and free of edit/delete/duplicate controls unless explicitly added later.
- Keep Shifts forms and detail surfaces planner-native and operational without adding hidden behavior, new fields, saved preferences, or new navigation paths.
- Keep Dashboard and Statistics visually useful without pretending to be mature analytics surfaces before broader calculations exist.
