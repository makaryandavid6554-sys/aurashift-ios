# AuraShift AI Strategy

## Future AI Role
AI is intended to extend AuraShift from descriptive analytics into guided interpretation and recommendation. It is a future capability layer, not an MVP dependency.

## Target AI Use Cases
- Trend analysis across user statistics.
- Personalized recommendations based on patterns and behavior shifts.
- Schedule or work-pattern suggestions.
- Natural-language explanations of changes in the user’s metrics.
- Practical next-step summaries that are easier to act on than raw data alone.

## MVP Position
- The MVP should prepare architectural boundaries for AI-related services.
- The MVP should not depend on real AI integration to deliver value.
- Early insight behavior should use deterministic local logic where possible.
- MVP insight direction is local, rule-based, statistical/template-driven, and explainable.
- Do not add heavy LLM code, Foundation Models integration, or cloud AI to the repo during MVP.
- Step 9 introduced `AuroraSummaryShaper` as a non-AI, rule-based summary layer over the shared mock snapshot.
- Step 38 connected that same deterministic shaper to the shared current-week persisted shift summary for one Dashboard workload insight line.
- Step 39 aligned that copy with the rest of the app around persisted shifts and planned hours for this week.
- Step 53 reframed Dashboard's Aurora presentation as a local rule-based summary so the home screen does not imply AI, recommendations, or model-backed analysis.
- Step 55 keeps `AuroraSummaryShaper` as the internal deterministic shaper name, but the Dashboard UI presents the output as `Local` / `Schedule summary` to avoid implying AI or a branded assistant behavior.
- Current dashboard summary output is deterministic and partly persisted-derived for current-week shift count/planned hours, but it is still not AI-generated or a real analytics/recommendation system.

## Architectural Preparation
- Keep AI behind service interfaces.
- Future provider path should remain staged: `RuleBasedInsightsProvider` -> `OnDeviceAIProvider` -> `CloudAIProvider`.
- Introduce provider boundaries only when real insight logic requires them; do not create a framework before the deterministic local path needs it.
- Preserve structured data models so future prompts and inference inputs are reliable.
- Separate generated explanations from source metrics and deterministic insights.
- Design the UI so AI cards or summaries can be added without reworking the navigation shell.
- Keep deterministic shaping separate from future AI service boundaries so it remains testable and useful without network or model dependencies.
- Keep current-week persisted shift summary copy rule-based, narrow, and plainly labeled; do not promote it into a recommendation engine or model-backed feature.
- Keep Dashboard home-screen Local summary copy grounded in stored shifts or local schedule context; avoid language that suggests live AI inference.

## Product Constraints
- AI outputs must support trust, clarity, and usefulness.
- Recommendations must never obscure the underlying data.
- Future AI features should be explainable, optional, and easy to verify.
- Until real AI exists, copy should remain restrained and explicitly grounded in local, persisted, or deterministic context.
