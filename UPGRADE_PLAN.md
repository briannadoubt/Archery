# Archery Macro Upgrade Plan

## Goals
- Ship a macro-first SwiftUI architecture that is production-ready, strongly typed, and DI-friendly.
- Keep generated code readable, testable, snapshot-covered, and portable across Apple platforms.

## Global Decisions
- Platforms: support iOS, iPadOS, macOS, Mac Catalyst, watchOS, visionOS via `#if os(...)`; min SDK v26; Swift 6.2; Xcode 26.
- Scope: v1 targets CRUD/content SaaS (list/detail/search, forms/wizards, auth/onboarding, settings, light checkout/payments, notifications); excludes real-time collab, heavy media editing, low-latency chat/voice/video, AR/3D/games.
- Formatting: pretty-printed output; formatter step available.
- Package layout: single SwiftPM package with multiple products (runtime, macros, tooling/CLI) and granular libraries.
- DI stance: AppShell auto-registers annotated types; optional container merge + patch hooks; `@DIManual` opt-outs.
- Providers: first-class adapters—analytics (Segment/Amplitude/GA4), push (APNs + Firebase), payments (StoreKit 2 + Stripe), auth (OIDC/Sign in with Apple); thin defaults + adapter points.
- Security/PII: mandatory redaction; secrets only from secure storage; CI secret scanning; opt-out flags test-only.
- Schema/config: canonical YAML/JSON schema (entities/routes/tokens/providers) with optional Swift DSL overlay; versioned schema, breaking changes require version bump + migration notes.
- Tokens: accept Figma/Style Dictionary and pure-Swift manifest; both emit the same DesignTokens outputs.
- Testing posture: mandatory macro snapshots, nav-graph validity, MainActor/a11y lint, smoke UITest of shell; opt-in property/fuzz/record-replay/perf benches. CI blocks on mandatory.
- Performance budgets: cold start <300 ms on baseline A-series, <16 ms/frame @60 fps, memory <150 MB for sample app; enforced in CI with opt-out flags.
- Telemetry: tooling/CLI telemetry off by default; opt-in anonymous error/usage only; no PII.
- Licensing: Apache-2.0; generated templates include disclosure placeholders but no auto-telemetry.
- Distribution: SwiftPM plugin + Homebrew tap; projects pin tool version; majors ~6 months, support last two minors.
- Crash reporting: adapter points only; no bundled reporter.
- Data/export: scaffold export/delete flows; default log/analytics retention 30 days.
- Compliance/regional: residency tags per repo; validation to prevent cross-residency writes.
- Governance: breaking macro/schema changes require lightweight RFC + approver signoff; minors can add non-breaking features.

## Priority Order (Suggested)
- Core runtime: EnvContainer, KeyValueStore, Repository, ObservableViewModel.
- DI/View scaffolding: ViewModelBound, AppShell, Navigation & Deep Links.
- Data + policy: Networking & Errors, Persistence, Auth & Security, Offline & Sync.
- Experience: Design System, Accessibility/Localization, Forms, Widgets/Intents, Interop.
- Quality: Tooling/DX, Testing & CI, Performance, Observability, Benchmarking, Compliance.
- Productization: Full App Generation, Configuration/Branding, Monetization, Developer Portal.
- Release: Rollout steps and migration hygiene.

## 1. KeyValueStore — DONE
- Codable-backed async/throwing get/set with default values.
- Namespaced keys + migration hooks (old→new key mapping).
- Change notifications via AsyncStream.
- Auto-generated mock/in-memory store for tests and previews.
- Done when: generated store compiles in sample app, migration path tested, snapshots cover namespacing/defaults.

## 2. Repository — DONE
- Generate protocol + live/mock implementations; DI initializer.
- Error normalization into RepositoryError with source context.
- Optional caching + in-flight request coalescing.
- Tracing hooks (duration, errors) behind a flag.
- Child-repo factory helpers for shared DI shape.
- Done when: live + mock compile, caching/coalescing toggles tested, normalized errors snapshot-tested.

## 3. ObservableViewModel — DONE
- Enforce @MainActor + Resettable; synthesize onAppear/onDisappear hooks.
- Auto-cancel tracked tasks via CancelableTask; optional load() auto-call.
- State-machine scaffolding: loading/success/error helpers.
- Debounce/throttle utilities for inputs.
- Done when: annotations enforced; auto-cancel tested; state-machine snapshots generated.

## 4. ViewModelBound — DONE
- DI: inject repos/stores from EnvContainer or factory closure; fail-fast if missing.
- Option to use @StateObject for identity preservation.
- Generated previews with mock repos + seeded data.
- Optional .task { await vm.load() } wrapper when load() exists.
- Done when: generated view compiles; previews build with mocks; load() wrapper verified by snapshot.

## 5. AppShell (new macro) — DONE
- Root TabView + per-tab NavigationStacks with typed Route enums.
- Declarative sheets/fullScreen covers/window scenes from annotations.
- Auto DI registration (hybrid model); accepts container merge + patch closures; `@DIManual` opt-outs.
- Previews for each tab with mock data.
- Done when: sample app boots with generated shell; routes type-safe; per-tab previews render.

## 6. Tooling & DX - DONE
- Diagnostics: warn on missing @MainActor for VMs, non-async repo APIs, or KeyValueStore cases without associated values.
- Snapshot tests for macro output; fixtures per macro shape.
- SwiftPM plugin/CLI task to regenerate snapshots and run tests.
- Done when: CLI regenerates snapshots + runs tests in CI; diagnostics show in Xcode; fixtures stable.

## 7. Runtime Glue — DONE (EnvContainer + DI wiring)
- Lightweight EnvContainer for registration/lookup of repositories/stores.
- Shared types: LoadState<Value>, AlertState, CancelableTask manager.
- Minimal logging interface consumed by generated tracing hooks.
- Done when: EnvContainer used by generated code; shared types adopted; logging hook exercised in tests.

## 8. Networking & Errors - DONE
- APIClient macro: async/await, retry/backoff, caching, configurable decoding strategies.
- Shared AppError type with user-facing messaging + logging/analytics hooks (redaction mandatory).
- Request/response fixtures + snapshot tests; toggleable network stubs for previews.
- Done when: APIClient scaffolds compile with retries/caching toggles; AppError surfaces user copy; fixtures drive snapshots.

## 9. Persistence - DONE
- SwiftData/Core Data/SQLite gateway macro with migrations + preview seeds (choose one backend for v1 demo).
- @AppStorage/@SceneStorage wrappers for lightweight settings.
- Keychain helper for secrets/tokens with mockable interface.
- Done when: one persistent backend demoed end-to-end; migrations tested; keychain mocked in tests.

## 10. Navigation & Deep Links - DONE
- Typed deep-link router: URL → Route enums; notification/shortcut handoff.
- Persist/restore navigation stacks across launches.
- Guarded routes for auth/entitlements; error surfaces for blocked navigation.
- Done when: deep-link fixtures navigate correctly; state restoration verified; guarded routes tested.

## 11. Design System & Theming - DONE
- DesignTokens macro: colors/typography/spacing from Figma/Style Dictionary or Swift manifest.
- Environment-driven light/dark/high-contrast variants; semantic color enforcement.
- Preview catalog sweeps token combinations per component.
- Done when: token import regenerates themes; previews cover light/dark/high-contrast; semantic colors enforced by lint.

## 12. Accessibility & Localization - DONE
- Diagnostics for missing accessibility labels, Dynamic Type escapes, contrast.
- String extraction + pseudo-localization preview macro; RTL snapshot lane; default locales en + pseudo + RTL run.
- API to attach accessibility metadata to generated views.
- Done when: a11y lint passes; pseudo/RTL snapshots generated; missing label checks fail CI.

## 13. Widgets, Intents, Background ✅ DONE
- Shared model macro emitting App Intents, Widget timelines, Live Activities stubs.
- Background task scheduler wrappers with testing doubles.
- Timeline/intent fixtures for snapshots and previews.
- Done when: widget + intent targets compile; timeline fixtures snapshot-tested; background tasks mocked.

## 14. Analytics & Feature Flags ✅ DONE
- Event schema macro with compile-time checking + provider adapters (Segment/Amplitude/GA4).
- Feature-flag wrapper with local overrides and typed gates for previews/tests.
- Redaction helpers for PII in logs/analytics payloads.
- Done when: event schema generates adapters; flags override in previews/tests; redaction verified.

## 15. Testing & CI ✅ DONE
- Mandatory: macro snapshots, nav-graph validity, MainActor/a11y lint, smoke UITest of shell.
- Optional (recommended): property tests, fuzzing, record/replay harness, perf benches.
- Compatibility suite against N-1/N-2 runtime/tooling.
- GitHub Actions workflow for lint/test/snapshot; secret scanning (gitleaks/trufflehog); perf budgets enforced.
- Done when: CI matrix green; fixture drift detected; compatibility suite passes; perf budgets enforced with opt-outs logged.

## 16. Performance & Stability
- Instruments-friendly trace points; optional signposts.
- Memory warning hooks + load-shedding helpers in VMs/repos.
- View diff tracking to flag unnecessary re-renders.
- Done when: perf suite runs; signposts visible in Instruments; diff tracking highlights regressions.

## 17. Documentation & Examples
- Sample app showing KeyValueStore/Repository/ViewModelBound/AppShell end-to-end across supported platforms.
- Doc comment emission for generated APIs; docs site generated from schema/macros.
- Recipes for auth gate, paginated list, validated form.
- Done when: sample app builds; docs generated; recipes runnable.

## 18. Auth & Security
- Route/repo annotations for auth requirements; generated guards/denied states.
- Token refresh scaffolding with PKCE/nonce helpers; pluggable auth providers.
- Secure logging defaults + redaction; jailbreak/debug detection hooks.
- Done when: guarded routes enforced; refresh flow exercised; redaction tested in logs.

## 19. Offline & Sync
- Offline-first cache with conflict policies (LWW + server-merge hooks).
- Mutation queue with background replay; connectivity-aware UI signals.
- Sync diagnostics surfaces in previews/tests.
- Done when: offline mutation queue passes tests; conflicts resolved per policy; connectivity indicators demonstrated.

## 20. Forms & Validation
- Form macro: field models, validation rules, keyboard/accessory behaviors.
- Error presentation helpers; focus management utilities.
- Preview seeds for invalid and edge cases.
- Done when: generated form renders with validation errors; focus utilities tested; edge-case previews exist.

## 21. Modularity & Build
- Feature-module templates with shared contracts; forbid cross-feature imports beyond contracts (linted).
- Build-time flags to toggle macro outputs; size/perf budgets enforced in CI (build time, symbols).
- Incremental/sharded codegen; CI caching to keep builds fast.
- Done when: feature modules compile independently; flags gate outputs; CI fails on budget violations.

## 22. Interop
- Bridges for UIKit/AppKit hosting; Share/ActivityView wrappers.
- Coexistence patterns for SwiftData + Core Data; migration aids.
- Compatibility shims for older OS baselines where macros emit alternates.
- Done when: hosting controllers work; dual persistence pattern demoed; shims compile for old targets.

## 23. Observability Ops
- Crash fingerprint enrichment and breadcrumb pipeline hooks.
- Sampled telemetry exporters; correlation IDs flowing through repos/VMs; cardinality guards.
- Vendor-neutral OTel export + sample dashboards; no vendor-locked alerts by default.
- Done when: correlation IDs span request → VM → view logs; exporters configurable; sampling enforced.

## 24. Release & Migration
- Changelog generator for macro shape changes; deprecation annotations.
- Migration scripts/templates for breaking updates; codemods; @available fix-its where possible.
- PR checklist covering snapshots, docs, accessibility, localization, security.
- Done when: changelog auto-generated in CI; migration template used; PR checklist enforced.

## 25. Full App Generation
- Schema ingest DSL/JSON for entities/routes/permissions → generates repos, VMs, nav graph, fixtures.
- Screen archetype templates (list/detail, wizard, form, dashboard) auto-selected from schema hints; preview bundles.
- Design token importer; localization hooks; faker-based seeds + scenarios.
- Workflow recipes: auth, onboarding, payments, notifications opt-in, pagination with provider toggles.
- Policy/guard layer: roles/entitlements/feature flags applied to routes/actions.
- Provider catalog adapters; quality gates (snapshots, nav validity, dependency health, a11y lints, dead-route detection).
- Release pipeline: Fastlane/TestFlight/App Store lanes; asset/icon pipeline.
- Ops telemetry: turnkey logging/metrics/export with correlation IDs; baseline dashboards.
- Extensibility: partial template overrides + escape hatches for custom SwiftUI.
- Safety rails: PII redaction defaults, secret scanning for generated configs, compliance checklist toggles.
- Done when: given a schema + tokens + provider config, a runnable app target builds with passing tests and previews.

## 26. Configuration & Environments
- Hierarchical config (build-time + runtime) with type-safe access and env overrides.
- Per-target variants (prod/stage/dev/demo) and runtime remote-config merge.
- Secrets handling and validation; config diff detection with safe fallbacks.
- Done when: env-specific builds succeed; remote-config merge tested; secrets validated/redacted in logs.

## 27. Branding & White-Label
- Brand-specific theme/asset bundles; app icon/name/package ID switching.
- Per-brand feature toggles and capability gating.
- Multi-target build pipeline templates for white-label outputs.
- Done when: two brand targets build with distinct assets/icons; feature toggles differ per brand; pipeline produces branded artifacts.

## 28. Monetization
- StoreKit 2 scaffolding: products, entitlements, subscription status observers.
- Paywall/upsell templates; entitlement-aware UI states.
- Receipt validation hooks; sandbox/TestFlight preview seeds.
- Done when: sandbox purchases succeed; entitlement state drives UI; paywall snapshots generated.

## 29. End-to-End & Fuzz Testing
- UI tests for critical flows; navigation graph fuzzing.
- Property-based tests for state machines and load states (opt-in).
- Record/replay harness for API stubs; deterministic previews.
- Done when: UITest bundle passes; fuzzing catches bad routes; record/replay used in CI (when enabled).

## 30. Benchmarking
- Microbench harness for EnvContainer lookup, repo caching, rendering hotspots.
- Perf budgets enforced in CI; Instruments template configs.
- Perf snapshot comparisons across macro revisions.
- Done when: perf suite runs in CI; regressions fail build; Instruments template documented.

## 31. Compliance & Privacy
- Data retention policies, export/delete flows, consent templates.
- PII/secret scanning for generated configs/assets; redaction enforcement.
- Audit log hooks for security-sensitive actions; residency tags validation.
- Done when: export/delete flows demoed; secret scan passes; residency validation enforced.

## 32. Developer Portal
- Docs site generator from schema/macros with live previews of generated flows.
- Changelog auto-generation from schema/macro changes.
- Onboarding checklist and API reference pulled from generated artifacts.
- Done when: portal builds; live preview shows generated flows; changelog updates automatically.

## 33. Configuration & Distribution Decisions (bubbled up)
- Tooling/CLI telemetry opt-in only; defaults off; no PII.
- Distribution via SwiftPM plugin + Homebrew tap; version pinning required.
- Release cadence: majors ~6 months; support two trailing minors.
- Crash reporting via adapters only; no default vendor.
- Data retention default 30 days; configurable.

## 34. Rollout Steps (v1)
- Implement KeyValueStore upgrades + tests.
- Implement ViewModelBound DI + previews.
- Add Repository error normalization + mocks.
- Introduce EnvContainer runtime.
- Add AppShell macro prototype + snapshot tests.
- Done when: these land behind feature flags with green CI (mandatory test set and perf budgets).

## 35. Risks & Mitigations
- Build/perf blowup: prioritize incremental/sharded generation, CI caching, perf budgets early.
- DX drift via overrides: document and enforce partial override limits; warn when upgrade guarantees break.
- Security/PII gaps: wire redaction + secret scanning before public release; enforce CI checks.
- Compatibility debt: keep N-1/N-2 compat suite running from the start.
