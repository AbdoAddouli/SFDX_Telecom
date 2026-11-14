# E2 — Catalog & Pricing (Phase 2)

**Objective:** build the RCA catalogue, commitment variants, bundle rules, and the single server-side pricing path both channels consume.
**Exit gate:** *A committed 5 GB plan prices correctly with and without commitment; the 30% device discount fires* (`ARCHITECTURE.md` §13).
**Source:** `ARCHITECTURE.md` §6; `BUSINESS_PROCESS.md` §5; `DATA_MODEL.md` §9.1, §10.5–10.6, §15.

> **Highest-risk configuration surface:** an unactivated decision table silently produces wrong prices with no error (`R13`). Pricing is also not fully deployable metadata (`R2`) — the `pricing-export/` step is mandatory.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-CAT-01 | Product classification hierarchy | Must | A7 Pricing Admin | 🔴 |
| UC-CAT-02 | Product attributes and attribute-driven behaviour | Must | A7 Pricing Admin | 🔲 |
| UC-CAT-03 | Selling models and commitment options (`ProductSellingModelOption`) | Must | A7 Pricing Admin | 🔲 |
| UC-CAT-04 | Pricebook topology and pricebook entries | Must | A7 Pricing Admin | 🔴 |
| UC-CAT-05 | Bundle adjustment — 30% device discount | Must | A7 Pricing Admin | 🔲 |
| UC-CAT-06 | Product configuration rule — mandatory commitment | Must | A7 Pricing Admin | 🔲 |
| UC-CAT-07 | Pricing procedure, decision tables, and activation | Must | A7 Pricing Admin | 🔲 |
| UC-CAT-08 | `CatalogQueryService` — server-side catalogue + pricing | Must | Salesforce Developer (Apex) | 🟡 |
| UC-CAT-09 | `pricing-export/` artefact and refresh discipline | Must | DevOps + A7 | 🟡 |

---

### UC-CAT-01 — Product classification hierarchy

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-FND-03, UC-DM-14 |
| Blocks | UC-CAT-02…08, E5 |
| Business process | 03 |
| Architecture ref | §6.1 |
| Data model ref | §10.5 |
| Status | 🔴 Blocked — RCA enablement |

**Goal.** Replace the flat `Product2.Family` hierarchy with RCA's attribute-based `ProductClassification` so the 360° view and wizard can group products.

**Preconditions** — RCA enabled (UC-FND-03).

**Main flow**
1. Create classifications: `Mobile Plan` (children Mobile 5/20/50/100 GB), `Fiber & Landline` (Fiber 20/100 Mb), `Device` (iPhone 15 Pro, iPhone 13, Samsung S22).
2. Associate the seeded `Product2` records from UC-DM-14.
3. Verify `Subscription__c.ProductClassification__c` resolves for the 360° grouping.

**Alternate / exception flows**
- E1: RCA not yet enabled → classification deferred; catalogue stays in `Product2.Family` temporarily (documented, not permanent).

**Business rules**

| Rule | Source |
|---|---|
| Attribute-based catalog replaces `Product2.Family` | §6.1 |
| Commitment variants are options, not classifications | §6.2, X3 |

**Acceptance criteria**
- [ ] Three classification families with all products associated.
- [ ] No separate plan object created (`DATA_MODEL.md` §18).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Mobile 5 GB product | Query classification | Under `Mobile Plan` |

**Definition of done**
- [ ] Classifications committed; 360° grouping resolves.

**Open questions / risks** — `R4` RCA object/field names differ by release.

---

### UC-CAT-02 — Product attributes and attribute-driven behaviour

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-01 |
| Blocks | UC-CAT-05, UC-CAT-06, E5 |
| Business process | 03 |
| Architecture ref | §6.1, §6.3 |
| Data model ref | §10.5 |
| Status | 🔲 Not started |

**Goal.** Expose product behaviour (`Data_GB__c`, `Speed_Mbps__c`, `Requires_Commitment__c`, etc.) through the catalog so rules and the wizard can filter without code.

**Preconditions** — UC-CAT-01.

**Main flow**
1. Register `ProductAttribute`s for data volume, speed tier, unlimited calls/SMS, and commitment requirement.
2. Map ATS `Product2` fields to the attribute set.
3. Verify admin ownership: changing a data-volume tier must not require a developer.

**Alternate / exception flows**
- E1: Complex constraint logic beyond attributes → optional CML / `ExpressionSetConstraintObj` (Advanced SKU only) (`R14`).

**Business rules**

| Rule | Source |
|---|---|
| Attribute-driven behaviour is admin-owned, no code | §6.3 |
| Fibre speed compared against `Eligibility__c.Max_Downstream_Mbps__c` | §6.3 |

**Acceptance criteria**
- [ ] Attributes registered and mapped.
- [ ] An admin can change a tier without a deployment.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Attribute updated | Query product | New value returned |

**Definition of done**
- [ ] Attributes in source control where deployable.

**Open questions / risks** — none.

---

### UC-CAT-03 — Selling models and commitment options (`ProductSellingModelOption`)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-01 |
| Blocks | UC-CAT-04, UC-CAT-07, E4, E5 |
| Business process | 03 |
| Architecture ref | §6.2 |
| Data model ref | §15.4 |
| Status | 🔲 Not started |

**Goal.** Model commitment as **variant pricing on one product**, not as separate products — the single most important catalogue decision.

**Preconditions** — UC-CAT-01.

**Main flow**
1. Create selling model `TELCO_RECURRING` with options `NOCOMMIT` (0%), `COMMIT12` (−10%), `COMMIT24` (−20%).
2. Create `TELCO_DEVICE` with option `STANDARD` (0%) — **no** own commitment option; devices inherit `Root_Engagement__c`.
3. Bind option codes to `Engagement__c.Duration_Months__c` (12/24) in E4.
4. Verify against the Revenue Management Developer Guide that the exact `ProductSellingModelOption` field names match the org release.

**Alternate / exception flows**
- E1: Team proposes `Mobile 5 GB — 12 months` as a separate Product2 → **rejected** (`ARCHITECTURE.md` §6.2, anti-pattern §15).

**Business rules**

| Rule | Source |
|---|---|
| One product, three options: never three products | §6.2, X3 |
| `TELCO_DEVICE` has no commitment option — inherits the plan's | §15.4 |

**Acceptance criteria**
- [ ] Four options exist; discounts −10%/−20% correct.
- [ ] `COMMIT12`/`COMMIT24` map to durations 12/24.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Mobile 5 GB + COMMIT24 | Price | −20% applied |

**Definition of done**
- [ ] Options committed; binding to Engagement verified in E4.

**Open questions / risks** — `R4` field-name drift.

---

### UC-CAT-04 — Pricebook topology and pricebook entries

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7, A8 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-03 |
| Blocks | UC-CAT-05, UC-CAT-07, E4 |
| Business process | 03 |
| Architecture ref | §6.3, §6.4 |
| Data model ref | §10.6, §15.1–15.3 |
| Status | 🔴 Blocked — BQ6/Q3-DM (single vs multiple pricebooks) |

**Goal.** Establish list prices for the 9 seed products with effective dating.

**Preconditions** — BQ6/Q3-DM resolved (Consumer vs Business pricebook topology).

**Main flow**
1. Create pricebook(s) with `Is_Active__c`, `Effective_From__c`, `Effective_To__c`.
2. Add `PricebookEntry` list prices: Mobile €9.99/14.99/19.99/24.99; Fiber €24.99/39.99; devices €999/599/449.
3. Record the topology decision so `Account.Segment__c` pricing behaviour is explicit.

**Alternate / exception flows**
- E1: Price change without refreshing decision tables → stale pricing (`ARCHITECTURE.md` anti-pattern §15, `R2`).

**Business rules**

| Rule | Source |
|---|---|
| Step 1 of the pricing procedure is list price from `PricebookEntry` | §6.4 |
| Effective dating governs price revisions | §10.6 |

**Acceptance criteria**
- [ ] All 9 products priced in the correct pricebook(s).
- [ ] Effective dates set.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Mobile 5 GB | Query entry | €9.99 |

**Definition of done**
- [ ] Entries committed; topology documented.

**Open questions / risks** — BQ6 determines whether a second pricebook is needed.

---

### UC-CAT-05 — Bundle adjustment — 30% device discount

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-03, UC-CAT-04 |
| Blocks | E5 exit gate, E9 pricing test |
| Business process | 03 |
| Architecture ref | §6.3, §6.4 |
| Data model ref | §15.5 |
| Status | In progress - metadata, PricingService bulk pricing and Config_Rule blocking deployed; quote integration pending |

**Goal.** Make the bundle discount automatic and advisor-bypass-proof, declaratively.

**Preconditions** — options + pricebook entries exist.

**Main flow**
1. Create `Bundle_PlanDevice_30`: plan + device on the quote → −30% on the device line.
2. Create `Bundle_FiberMobile_15`: fibre + mobile → −15% on the mobile line.
3. Wire both into **Step 3** of the pricing procedure.
4. Confirm the discount cannot be removed by the advisor.

**Alternate / exception flows**
- E1: Discount implemented in LWC → **rejected** (X2, §6.5).

**Business rules**

| Rule | Source |
|---|---|
| Bundle discount is automatic and non-bypassable | BR-03.4 |
| Declarative `BundleBasedAdjustment`, advisor cannot bypass | §6.3 |

**Acceptance criteria**
- [ ] 30% device discount fires whenever plan + device co-exist.
- [ ] 15% fibre-mobile discount fires.
- [ ] No code computes the discount.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Plan + iPhone 15 Pro | Price quote | Device line −30% |
| TS-2 | Device only, no plan | Price | Discount does not fire (and is blocked by UC-CAT-06) |

**Definition of done**
- [ ] Verified in a scripted configure-price-quote sequence (E9).

**Open questions / risks** — `R2` export discipline.

---

### UC-CAT-06 — Product configuration rule — mandatory commitment

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-03 |
| Blocks | UC-CAT-05 verification, E5 |
| Business process | 03 |
| Architecture ref | §6.3 |
| Data model ref | §10.5, §15.3 |
| Status | 🟡 In progress - server-side Config_Rule__mdt evaluation deployed; quote UI integration pending |

**Goal.** Prevent a device that requires a commitment from appearing on a `NOCOMMIT` quote.

**Preconditions** — attributes + options exist.

**Main flow**
1. Create a `ProductConfigurationRule` (inclusion/exclusion) keyed on `Requires_Commitment__c`.
2. Test that iPhone 15 Pro / iPhone 13 / Samsung S22 cannot be selected with `NOCOMMIT`.
3. Log the decision to use declarative rules rather than CML (CML only if constraints exceed it).

**Alternate / exception flows**
- E1: A rule needs constraint logic the declarative engine cannot express → escalate to CML (Advanced SKU, `R14`).

**Business rules**

| Rule | Source |
|---|---|
| Device with `Requires_Commitment__c` cannot sit on a `NOCOMMIT` quote | BR-03.3 |
| Some smartphones cannot be sold without a commitment | §1.1 |

**Acceptance criteria**
- [ ] A device-only, no-commitment quote is impossible.
- [ ] Choosing `COMMIT12/24` unlocks device selection.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | NOCOMMIT plan | Add iPhone 15 Pro | Blocked |

**Definition of done**
- [x] Rule committed and verified server-side.

**Open questions / risks** — none.

---

### UC-CAT-07 — Pricing procedure, decision tables, and activation

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7 |
| Suggested owner | A7 Pricing Admin |
| Depends on | UC-CAT-04, UC-CAT-05, UC-CAT-06 |
| Blocks | UC-CAT-08, E5 |
| Business process | 03 |
| Architecture ref | §6.4 |
| Data model ref | §9.1, §9.4 |
| Status | 🔲 Not started |

**Goal.** Build and **activate** the five-step pricing procedure — activation is a discrete, forgettable, silently-breaking step.

**Preconditions** — all pricing components exist.

**Main flow**
1. Create `PricingProcedure: "ATS Offer Pricing"`:
   - Step 1 list price ← `PricebookEntry`
   - Step 2 commitment discount ← `ProductSellingModelOption`
   - Step 3 bundle discount ← `BundleBasedAdjustment`
   - Step 4 loyalty adjustment ← `AttributeBasedAdjustment`
   - Step 5 floor/guardrail ← max discount, margin floor
2. Create the supporting decision tables.
3. **Activate** decision tables and the procedure (inert until activated).
4. Add activation to the release runbook; add to `pricing-export/`.

**Alternate / exception flows**
- E1: Procedure left deactivated → wrong prices, no error (`R13`). Release gate must assert activation.

**Business rules**

| Rule | Source |
|---|---|
| Decision tables/procedures must be activated | §6.4 |
| Activation is an explicit release-runbook step | `R13` |

**Acceptance criteria**
- [ ] Procedure active with all five steps.
- [ ] Floor/guardrail prevents a negative or below-margin price.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Committed 5 GB plan | Run procedure | Correct net price |
| TS-2 | Deactivated procedure | Run | Test fails (activation asserted) |

**Definition of done**
- [ ] Procedure active; exported to `pricing-export/`.

**Open questions / risks** — `R13`, `R2`.

---

### UC-CAT-08 — `CatalogQueryService` — server-side catalogue + pricing

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A3, A2 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-CAT-07, UC-LIF-01 |
| Blocks | E5, E7 |
| Business process | 02, 03 |
| Architecture ref | §6.5, §8.2 |
| Data model ref | §10.5 |
| Status | 🟡 In progress - server-side service deployed 2026-11-07; E5/E7 caller wiring remains |

**Goal.** Provide the single Apex service that resolves product options and returns authoritative `PricingService` prices to **both** advisor and portal, so they can never diverge.

**Preconditions** — pricing procedure active; `Eligibility__c` data loaded.

**Main flow**
1. Implement `CatalogQueryService` (`cacheable=true`) exposing `getPlans(type, commitment)`, `getDevices()`, `getOptions(productId, commitment)`, `getPriceBreakdown(...)`, and `filterByEligibility(...)`.
2. Delegate configuration and pricing to `PricingService` server-side; no RCA API dependency.
3. Apply FLS via `WITH USER_MODE`; validate inputs.
4. For fibre, filter plans where `Max_Downstream_Mbps__c >= Speed_Mbps__c`; mark future `Earliest_Activation_Date__c` as blocked.

**Alternate / exception flows**
- E1: LWC attempts to compute price → **rejected**; the LWC renders only (`§6.5`, `X2`).

**Business rules**

| Rule | Source |
|---|---|
| Neither wizard nor portal computes price in LWC | §6.5, X2 |
| Product option resolution not available declaratively → service | §8.2 |
| Same price returned to portal and advisor | §6.5, BR-10.6 |

**Acceptance criteria**
- [x] Service returns `PricingService.PriceBreakdown`; advisor and future portal paths share the same method.
- [x] No client-side price arithmetic exists in the implemented service path.
- [x] Fibre filtering covers speed caps, no-fibre postcodes, unknown postcodes, and future activation.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Same account+plan from portal and advisor | Query | Identical price |
| TS-2 | Fibre postcode with 20 Mbps cap | `getPlans` | 100 Mb excluded |

**Definition of done**
- [x] ≥80% coverage; `CatalogQueryService` passes 16/16 and the service, `CatalogQueryRepository`, and `CatalogEligibilityFilter` are at 100%. Query-budget tests assert one read per source and no eligibility query for non-fibre-only lists.
- [ ] E9 headless price test asserts the end-to-end numbers.

**Open questions / risks** — no RCA API signature dependency remains; callers must use the published DTO fields and never calculate prices client-side.

---

### UC-CAT-09 — `pricing-export/` artefact and refresh discipline

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 2 |
| Actor(s) | A7, A6 |
| Suggested owner | DevOps + A7 |
| Depends on | UC-CAT-07 |
| Blocks | E9 release gate, `R2` mitigation |
| Business process | 03 |
| Architecture ref | §3.3, §11.3 |
| Data model ref | §9.1 |
| Status | 🟡 In progress - export and rollback artefacts complete 2026-11-08; release/CI wiring and versioned commit remain |

**Goal.** Make pricing reproducible from version control: pricing procedures, pricing rules, configuration rules, and their manifest are exported as JSON with per-file SHA-256 values.

**Preconditions** — `Pricing_Procedure__mdt`, `Pricing_Rule__mdt`, and `Config_Rule__mdt` records present.

**Main flow**
1. Define the controlled export step that writes procedures, pricing rules, and configuration rules to `pricing-export/`.
2. Add the export and `scripts/verify-pricing-export.ps1` to the release runbook and CI.
3. Document the **refresh** rule: after modifying `PricebookEntry`, refresh decision tables or pricing goes silently stale (`ARCHITECTURE.md` anti-pattern §15).
4. Prove a rollback: use `scripts/restore-pricing.ps1` against the 10-file snapshot and confirm previous prices.

**Alternate / exception flows**
- E1: Export skipped → pricing becomes the one part of the release you cannot reproduce or roll back (`R2`).

**Business rules**

| Rule | Source |
|---|---|
| `pricing-export/` mandatory, not optional | §11.3 |
| Refresh decision tables after `PricebookEntry` changes | §15 |

**Acceptance criteria**
- [x] `pricing-export/` populated (6 files, 10 records) with `manifest.json` SHA-256 values.
- [ ] Version-control commit of `pricing-export/` (pending explicit request).
- [ ] Release runbook includes export + activation.
- [x] `scripts/verify-pricing-export.ps1` validates both manifests and the rollback record set offline.
- [x] A rollback restored the Samsung S22 price from 336.75 to 314.30 using the 10-file snapshot.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Modified price | Re-run pricing test | Identical results after refresh |
| TS-2 | Export reverted | Deploy | Prior prices restored (verified 2026-11-08: 336.75 → 314.30) |

**Definition of done**
- [x] Pricing reproducible from the exported JSON and verified manifest hashes.
- [x] Offline verifier checks both manifests, totals, file coverage, and rollback record names.
- [x] Rollback drill proves prior prices are restored.

**Open questions / risks** — `R2`, `R13`; the export folder is currently untracked until the user requests a commit.
