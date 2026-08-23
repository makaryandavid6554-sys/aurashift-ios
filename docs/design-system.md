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
- Legacy AuraShift / MoneyTracker is the primary UX blueprint for product behavior: Today-first operational flow, month calendar, anchored day popover, quick actions, shift editing, statistics rings, goals, and Aurora. Restore patterns intentionally through the new architecture; do not copy legacy code or its heavier visual glass treatment blindly.
- SuperShift: month-first operational planner behavior, fast shift visibility, compact schedule scanning, and day-focused interactions.
- Revolut: premium hierarchy, calm confidence, strict spacing discipline, and clean operational UI.
- iOS 26: modern native feel, semantic adaptive colors, restrained material usage, and smooth visual rhythm.
- AuraShift should synthesize these references into a premium operational planner for variable-income workers; it should not become a direct SuperShift copy, bank app, glass-heavy concept UI, or AI-first product.

## Visual Character
AuraShift should feel precise, calm, and credible. Layouts should use generous but efficient spacing, strong typographic hierarchy, subtle contrast, and deliberate emphasis instead of decorative effects.

## Adaptive Theme And Color Personalization
- AuraShift follows the system Light/Dark appearance by default; neither mode is secondary.
- The user can choose a curated product accent without changing information hierarchy or data meaning.
- MVP accent presets: Citron, Graphite, Emerald, Cobalt, and Signal Orange.
- Accent color applies to primary actions, active navigation, selected dates, progress emphasis, and controlled decorative highlights.
- Semantic colors remain stable across themes: success, warning, destructive, neutral, and category/data-series colors must not be remapped by the chosen accent.
- All screens must use semantic theme tokens rather than hardcoded Light-only, Dark-only, or accent-specific colors.
- Contrast, disabled states, charts, calendar selection, and anchored popovers must remain readable for every supported accent in Light and Dark mode.
- Arbitrary RGB/hex color selection is deferred until the curated presets prove insufficient.

## Current Implemented Baseline
- `AuraTheme` provides baseline tokens for background, surfaces, text hierarchy, accent usage, spacing, corner radius, and subtle card shadow.
- `AuraCard` is the reusable surface primitive for premium containers.
- `AuraSectionHeader` is the shared heading primitive for structured module sections.
- App shell chrome uses existing Aura background/surface tokens, explicit tab metadata, and a minimal `TabView` with one `NavigationStack` per surface.
- Dashboard, Statistics, Calendar, and Shifts share a restrained card, section, metric, and operational-row language.
- Calendar is now the primary month-first planning surface, not the older weekly/list hybrid.
- Calendar month cells use compact one-line shift pills, restrained selected/today emphasis, muted neighboring-month records, and tight but breathable weekday/cell spacing for faster repeated scanning.
- Shifts rows, Calendar selected-day records, and Shift Detail share the same planner-record language: time/duration first, role-led hierarchy, compact kind, secondary location, contained notes, and restrained borders.
- Add/Edit/Duplicate shift forms use compact headers, clear record/time/note sections, contained Calendar-origin context, explicit helper actions, and local validation rows.
- Step 73 tightened cross-surface continuity by aligning stored-shift copy between Dashboard, Calendar, Shifts, and Shift Detail, and by making the standard/standby kind color treatment match across Calendar records, Shifts rows, and Shift Detail.
- Step 74 tightened Calendar operational density without changing month-first behavior or adding new scheduling controls.
- Step 75 restored breathing balance after the density pass with softer grid separation, clearer selected/today hierarchy, and more readable compact record pills.
- Dashboard now uses a legacy-inspired `Today` framing with shift-first daily state, a single primary add-shift action, compact local metrics, and restrained Calendar/Shifts bridge copy.
- Step 77 tightened top-level shell continuity with calmer shared tab/navigation chrome.

## Surface Guidance
- Dashboard should remain a legacy-inspired Today/Daily operational home: current-day shift state, compact day summary, one honest shift-first action, and planner continuity without becoming a second Calendar or implying income/expense/goal functionality before those domains exist.
- Statistics should eventually restore the legacy ring-led financial analytics language, but only after the new app has deliberate income/expense models and real calculations.
- Calendar should stay month-first, compact, readable, and operational. It should move toward the legacy anchored day-popover pattern for day previews, summaries, and quick actions without implying unsupported scheduling behavior.
- Shifts should feel like a daily operational command center while preserving the existing narrow CRUD and detail paths.

## Copy And Tone
- Prefer concrete, grounded labels: `This week`, `Planned hours`, `Stored shifts`, `Next shift`, `Local`, and `Empty`.
- Avoid user-facing prototype language such as `sample`, `placeholder`, `shell`, `deferred`, or implementation-heavy explanations.
- Do not imply AI, recommendations, scheduling automation, charts, or broad analytics unless those capabilities actually exist.

## Design Guardrails
- Do not introduce UI that feels gamified, playful, or casual.
- Do not rely on glow, excessive glass, or decorative gradients to create premium feel, even when restoring legacy flows.
- Do not let one-off screen styling bypass shared tokens and components.
- Do not apply the selected accent to every surface. Keep backgrounds, text hierarchy, semantic statuses, and dense analytics neutral and predictable.
- Do not allow user accent selection to recolor destructive actions, warnings, success states, or data categories into ambiguous meanings.
- Keep top-level navigation calm and native: stable tabs, consistent inline titles, shared background/surface chrome, and no decorative shell effects.
- Prefer small local alignment fixes over broad component rewrites until repetition is stable across real screens.
- Keep Calendar month cells calm and dense enough for quick scanning: clear compact day number, one-line shift presence, readable multi-shift stacking, muted neighboring month days, restrained but legible selected/today emphasis, and readable light/dark behavior.
- Keep Calendar selected-day inspectors anchored, compact, summary-led, readable for empty/single/multi-shift days, and free of edit/delete/duplicate controls unless explicitly added later.
- Prefer the legacy anchored day-popover behavior over separate heavy sheets for common day scanning and quick actions, but implement it incrementally and with the new restrained visual language.
- Keep stored shift objects visually consistent across Dashboard anchors, Calendar islands, Shifts rows, and Shift Detail. Kind labels and colors should not drift by surface.
- Keep Shifts forms and detail surfaces planner-native and operational without adding hidden behavior, new fields, saved preferences, or new navigation paths.
- Keep Dashboard planner-aware without turning it into a second Calendar. It may summarize today's shift state and local day totals, but dense day/month scanning belongs to Calendar.
- Keep Dashboard quick actions narrow and real. Show shift actions backed by existing persistence first; do not display fake income, expense, event, goal, or AI actions before those domains exist.
- Keep Dashboard and Statistics visually useful without pretending to be mature analytics surfaces before broader calculations exist.
