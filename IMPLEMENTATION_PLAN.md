# ATS Telecom — Implementation Plan

> **Status:** plan approved, execution not started.
> Derived from: `ARCHITECTURE.md`, `DATA_MODEL.md`, `TECHNICAL_DOCUMENTATION.md`, `BUSINESS_PROCESS.md`, `use-cases/README.md`, and the Revenue Core workstream in `docs/revenue-core/` (especially `05-BUILD-ORDER.md`).
> Environment reality: **Developer Edition org, no Revenue Cloud, no Experience Cloud, no sandboxes, 5 MB data, 2 licences.** All rules below flow from that.

## Ground rules (apply to every stage)

- **Never deploy to the connected shared sandbox** (`devtospace-stage`, org `00DAP00000Nlp6j2AB`). The only build target is the dedicated DE org.
- **Backward-compatible deploys only** — every deploy goes to the live org; there is no rollback button. Destructive changes use the two-step pattern: add new → backfill → remove old.
- **Flow orchestrates, Apex executes** — never the reverse. One write path per object.
- **All price arithmetic lives in `PricingService`** — never in LWC, never in `OfferBuilderService`. Portal and advisor call the identical service.
- **Scope frozen at the 80 use cases.** No generic pricing features (tiers, slabs, rate matrices, usage rating, multi-currency, proration). No `Invoice__c`/`Payment__c` pre-build. No portal build (E7 deferred, E10 closed).
- **Snapshots immutable, formulas never stored** (`Is_Committed__c`, `Months_Remaining__c`).
- Any work derived from an unanswered decision is tagged `ASSUMPTION — pending <owner>` in code and metadata.

---

## Stage 0 — Pre-flight hygiene

Unblocks everything; do first.

- [ ] **Fix git.** Current repo root is `C:\Users\addou` (home dir) with zero commits. Either re-init git inside the project folder or verify the home-dir repo + `.gitignore`, then make an initial "specs only" commit so the design is versioned before any code exists.
- [ ] **Verify the org target.** `sf org list` — confirm the dedicated DE org is authenticated and is the default target; confirm the shared sandbox is *not* the default.
- [ ] **Create `sfdx-project.json`** — package directory `force-app`, API 68.0. Namespace: include `ats_` only if the DE org actually has it (DE orgs cannot host namespaces without a managed package).
- [ ] **Create standard SFDX skeleton** — `force-app/main/default/{classes,objects,flows,lwc,permissionsets,...}`, `scripts/`, `pricing-export/`, `.forceignore`.
- [ ] **`.forceignore` rule from `UC-FND-01`** — exclude `pricing-export/` from normal deploys, keep it tracked in git.

**Gate — Stage 0:** project deploys cleanly to the DE org with an empty `force-app/`; git history exists; org target confirmed in writing here.

---

## Stage 1 — Phase 0 (revised E0 gate)

Content per `docs/revenue-core/05-BUILD-ORDER.md` §1. `UC-FND-03` (enable RCA) is permanently deferred; its slot takes these deliverables.

- [ ] **`scripts/reset-test-data.apex`** — deletes by `Test_Batch__c` marker field, re-seeds idempotently. *The single most important artefact in a no-sandbox org — Phase 0 gate, not an afterthought.*
- [ ] **Revenue Core metadata skeletons deployed empty** — `Pricing_Procedure__mdt`, `Pricing_Rule__mdt`, `Config_Rule__mdt` (queryable via `SELECT ... FROM ...__mdt`).
- [ ] **`ASSUMPTIONS.md`** — assumption table for unanswered BQ decisions (BQ2–BQ12, Q1/BQ1, Q4/BQ8), each tagged `ASSUMPTION — pending <owner>` per `docs/revenue-core/04-OPEN-DECISIONS.md` §Decision cadence.
- [ ] **Record decisions RC1, RC2, RC4, RC5, RC7, RC8** (architect-decidable now — file 04 lists which and why).
- [ ] **Record Q2 and Q3/BQ7 as deferred-with-rationale** — no SKU available on a DE org; Revenue Core substituted; E10 closed, data-export requirement raised instead.
- [ ] **Dev-org-only test strategy** written down as the official E0 gate substitute (RC7).

**Gate — revised E0** (replaces "deploys cleanly to an empty org"):
> Metadata deploys cleanly **over the live org** with no errors and no destructive changes; reset script returns the org to a known state; Revenue Core metadata types exist and are queryable.

---

## Stage 2 — Phase 1 (E1 Data Model)

Per `DATA_MODEL.md` §19 deployment sequence. Unaffected by the licence.

- [ ] Deploy the **6 custom objects** in dependency order: `Subscription__c`, `Engagement__c`, `Customer_Request__c`, `Eligibility__c`, `Integration_Log__c`, `Subscription_Wizard_State__c` (core fields first, dictionaries in follow-up commits).
- [ ] **Include the two RCA-marked lookups now** — `Subscription__c.ProductClassification__c` and `Subscription__c.Asset__c` (`docs/revenue-core/05-BUILD-ORDER.md` §2 moves them up; RCA will never arrive).
- [ ] **Record RC4 in the same commit** — `Subscription__c` is parent of truth; `Asset__c` is passive provisioned-equipment (the reconciliation inversion).
- [ ] **14 standard-object extensions** (Account, Contact, Lead, Opportunity, Quote, QuoteLineItem, Order, OrderItem, Product2, Pricebook2, PricebookEntry, Asset, Contract, Case — per DATA_MODEL §4).
- [ ] Custom metadata seeds: `Engagement_Penalty__mdt`, `External_Api__mdc`.
- [ ] Custom settings: `ATS_Feature_Flags__c`.
- [ ] Validation rules (`DATA_MODEL.md` §11.2), duplicate rules, indexes (`Subscription__c.Account__c`, external IDs, PricebookEntry compound keys).
- [ ] FLS/permission-set skeletons + FLS matrix (`DATA_MODEL.md` §17).
- [ ] **Idempotent seed scripts** (no manual Setup clicks; anything clicked becomes a recorded demo artefact).
- [ ] **Storage reality check** — verify consumption against the 5 MB ceiling after every object deploy; trim audit fields early if needed (the docs are silent here — flag it, don't discover it at E2).

**Gate — E1:** all six objects + extensions deployable by script; reset script restores the seeded state; storage headroom documented.

---

## Stage 3 — Phase 2 (E2 Catalog & Pricing = Revenue Core) — *vertical slice first*

Critical sequencing per `docs/revenue-core/05-BUILD-ORDER.md` §6 — **one working slice before building horizontally.**

### 3a — The slice (day 1–2)

- [ ] `Pricing_Rule__mdt` record `Device_Bundle_30_Percent` (Rule_Type `Bundle Adjustment`, `Adjustment_Value__c = 30`, `Priority__c`).
- [ ] `PricingService.price()` — minimal version that resolves base `PricebookEntry`, applies the rule, returns `PriceBreakdown` with `appliedRules` naming the rule.
- [ ] Test class proving: the discount fires, the applied rule is named in the breakdown, same input → same output.
- [ ] Seed: 1 product + 1 pricebook entry + the rule, via script.

> ✅ **Premise validated** — product, price, rule, computed price, assertion. Only then continue.

### 3b — Full Revenue Core

- [ ] Full `PricingService` — `priceBulk()` (≤200 rows, entry point for all callers), `evaluateConfiguration()`, `with sharing`, no DML, deterministic (`Priority__c` then `DeveloperName`, lower wins).
- [ ] `Pricing_Procedure__mdt` `Five_Step_Standard` — 5 ordered steps: base price → commitment variant → bundle adjustment → configuration constraints → breakdown.
- [ ] `Config_Rule__mdt` — `Requires_Commitment_Device` record; **prove a NOCOMMIT quote cannot include a commitment-required device**; `Block`/`Warn` severities.
- [ ] Commitment variants as `Pricing_Rule__mdt.Rule_Type__c = Commitment Variant` (replaces `ProductSellingModelOption`).
- [ ] `Product_Classification__c` object + `Product2.Classification__c` lookup + seeds (assuming RC2 = build it; if RC2 = `Product2.Family` fallback, record the decision and use the formula-path variant).
- [ ] `CatalogQueryService` extensions — `getOptions(productId, commitment)` (wizard step 3), `getPriceBreakdown(...)` (wizard step 5 / future portal).
- [ ] `scripts/export-pricing.apex` + `pricing-export/` JSON dump + `manifest.json` sha discipline (CI check fails on Setup edits made without export).
- [ ] Segment handling on `Pricing_Rule__mdt.Segment__c` — folds the BQ6 answer in (one pricebook + segment rules, or two pricebooks — record the choice as RC3).
- [ ] 54-entry seed (9 products × 3 commitment variants × 2 segments) generated programmatically.
- [ ] Bulk test: 10 000 `PricebookEntry`-equivalent rows with `@TestVisible` limits assertions, run at deploy, never committed as data.
- [ ] Test coverage ≥ 75%.

**Decision checkpoint before Stage 4:** RC2 (classification) and RC3 (pricebook topology / BQ6) answered — cheap now, expensive later.

**Gate — revised E2:**
> 54-entry seed commits; 30% device discount fires from `Pricing_Rule__mdt` with the applied rule named in `PriceBreakdown`; a NOCOMMIT quote cannot include a commitment-required device; pricing reproducible from `pricing-export/`; scaling strategy documented (`docs/revenue-core/02-DE-ORG-CONSTRAINTS.md` §3).

---

## Stage 4 — Phases 3–9 (blueprint order unchanged)

Critical path E1 → E2 → E3/E4 per `use-cases/README.md` §2. Only acceptance-criteria wording changes (file 03 §5).

### E3 — Acquisition
- [ ] `LeadImportService` + import Flow
- [ ] Lead conversion Flow (F-01)
- [ ] `UC-ACQ-03` public unauthenticated form (the only customer-facing surface left)

### E4 — Commerce & Activation
- [x] `OfferBuilderService` — **zero arithmetic**; consumes `PricingService` output only
- [x] `ActivationService` — atomic, idempotent, bulk-safe, BSS rollback (`UC-COM-03`)
- [x] Subscription state machine (`UC-COM-04`)
- [x] Activation Flow + "Validate the Order" custom action (`UC-COM-05`)
- [x] Activation idempotency + 200/500 bulk proof (`UC-COM-06`)
- [x] `ActivationService` split into reader/provisioner/BSS/writer/context; 163/163 local suite (2026-11-14)
- [ ] Trigger framework + handlers

### E5 — Advisor Experience
- [ ] Customer 360° cockpit LWC
- [ ] `subscriptionWizard` LWC — 5 steps; step 3 via `getOptions()`, step 5 via `getPriceBreakdown()` (both Revenue Core)

### E6 — Lifecycle *(partially blocked)*
- [ ] `EngagementPenaltyService` + penalty flows (`UC-LIF-01`)
- [ ] Cancellation flow, suspension, renewal (`UC-LIF-03/04/06`, with BQ assumptions tagged)
- [ ] ⛔ **Skip UC-LIF-02 and UC-DM-04** — blocked on Q1/BQ1 (assumption "amend", pending Finance + Sales Ops)

### E8 — Integration
- [x] Slice 1 (2026-11-21): `ExternalApiService` façade + focused collaborators + `IntegrationLogService` + `HttpCalloutMock` failure suite deployed; no live gateway switched over.
- [x] Slice 2 (2026-11-21): `Integration_Log_Event__e` Publish Immediately outbox + bulk trigger handler; failure logs survive rollback.
- [x] Slice 3 (2026-11-21): Failing-endpoint runtime proof via synthetic `E8_Failure_Test` metadata + `E8IntegrationSmoke`; real HTTP 500 produced 0 DML rows and a surviving `Failure`/`500` audit row.
- [x] Slice 4 (2026-11-21): `Service_Activated__e` post-commit activation event, publisher, subscriber stub and rollback/no-PII tests.
- [x] Slice 5 (2026-11-22): Flag-off `RealBssProvisioningGateway` scaffold + factory and `BSS_Provisioning_Live__c` (default false); simulated gateway remains the live path.
- [x] Slice 6 (2026-11-22): Flag-off `BssReconciliationBatch` + scheduler, status gateway factory, drift tests and status-only writes; `BSS_Status_Live__c` default false.
- [x] Slice 7 (2026-11-22): Flag-off `ProductImageSyncBatch` + scheduler, placeholder `Product_Image` metadata, cached-field writes and no-PII request test; `Product_Image_Live__c` default false.
- [x] Slice 8 (2026-11-23): CDC enablement on four custom objects + `Asset`, flag-off `CdcReportingService` with five change-event triggers and non-PII allowlists, `CDC` audit picklist; `CDC_Reporting_Live__c` default false.
- [ ] `External_Api__mdt` + named credentials (real Named Credential still blocked in DE org)
- [ ] Callout services I-01…I-07 with `Integration_Log__c` logging
- [x] Activation event `ats.service.activated.v1` (`Service_Activated__e`); [x] image sync scaffold (slice 7), [x] CDC reporting scaffold (slice 8), [ ] live endpoints/feed
- [ ] Cache TTL / rate-limit enforcement, payload files via `ContentDocument`
- [x] `HttpCalloutMock` suite incl. deliberately failing endpoint (slice 1 covers mock success/HTTP error/transport error; slice 3 proves real HTTP 500 with rollback-safe audit)

### E9 — Hardening & NFR
- [ ] Permission sets + FLS matrix (`DATA_MODEL.md` §17)
- [ ] IDOR review, CRUD/FLS enforcement tests
- [ ] Translations
- [ ] **Headless CPQ-sequence script** — drives configure-price-quote end-to-end against `PricingService`/`CatalogQueryService` without a UI (white-box; more valuable than the original RCA version)

### Explicitly not built
- **E7 Portal** — deferred (RC5), Experience Cloud licence required. `docs/index.html` shows E7 as *deferred — licence required*.
- **E10 Billing** — closed (RC6). No `Invoice__c`, no `Payment__c`. Data-export requirement raised instead.

**Gate — E9 / release:** FLS matrix enforced, headless CPQ test green, no open 🔴 without a recorded decision or assumption.

---

## Stage 5 — Continuous practices (run from Stage 1 onward)

- [ ] **Deploy loop:** `sf project deploy start --dry-run` → deploy → focused tests → `reset-test-data` if data was dirtied.
- [ ] **Every Apex class ships with its test in the same commit.**
- [ ] **Two-step pattern** for any destructive change (add → backfill → remove).
- [ ] **Re-run `_board-gen.js` / `_build.js`** after any `use-cases/*.md` edit so `docs/board-data.js` and `docs/team.html` don't drift.
- [ ] **Demo artefact flow:** git branch + seed script = reproducible demo state (the sandbox replacement).
- [ ] **`pricing-export/` sha check** — a mismatch means someone edited pricing in Setup without exporting; treat as a failed gate.

---

## Decision register status (as of this plan)

| ID | Question | Disposition in this plan |
|---|---|---|
| Q1 / BQ1 | Plan change = amend or new contract? | **Blocking** E6 (UC-LIF-02, UC-COM-05, UC-DM-04). Assumption: amend. Pending Finance + Sales Ops. |
| Q2 | RCA licensing | **Answered by circumstance** — no SKU on DE org; deferred with rationale; Revenue Core substituted. |
| Q3 / BQ7 | Invoicing in Salesforce? | **Default No** — E10 closed, data-export requirement raised. |
| Q4 / BQ8 | Fibre eligibility source/freshness | Open — `Eligibility__c` buildable once SLA known; assumption tagged. |
| BQ2–BQ12 | Commercial/ops questions | Carried as tagged assumptions (`ASSUMPTIONS.md`); each is a one-line change later. |
| RC1–RC8 | New decisions created by the missing licence | RC1/RC2/RC4/RC5/RC7/RC8 answered now (architect); RC3 at Stage 3 checkpoint. |

## Definition of Done (project)

- [ ] All Stages 0–4 checkboxes complete or explicitly deferred with a recorded decision.
- [ ] 74 of 80 use cases demonstrable (6 portal + 3 billing never built; 3 E6 cards blocked on Q1 remain assumption-tagged).
- [ ] Every 🔴 in `use-cases/` has either a green resolution or a written deferral with date + rationale (`UC-FND-06`).
- [ ] Reset script + seed scripts reproduce the full demo state from a fresh org state on demand.
- [ ] `pricing-export/` manifest matches org state.
