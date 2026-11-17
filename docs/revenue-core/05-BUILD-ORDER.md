# 05 — Build order

The blueprint's phase sequence is *phases 1–2 are the critical path, do not skip out of order* (`use-cases/README.md` §2). That still holds. What changes is the **substitute exit gate at E0** and the **content of E2**.

## 1. What moves into Phase 0

`UC-FND-03` (enable RCA) is permanently deferred. Its vacated slot takes the work that must exist before anything else deploys:

| New Phase 0 deliverable | Source |
|---|---|
| `scripts/reset-test-data.apex` | File 02 §4 — no rollback without it |
| Revenue Core metadata skeletons deployed empty | File 03 |
| Dev-org-only test strategy recorded as the E0 gate substitute | File 02 §1, `RC7` |
| Assumption table for the unanswered `BQ*` decisions | File 04 |

**Revised E0 exit gate:** *Metadata deploys cleanly over the live org; reset script returns the org to a known state; Revenue Core metadata types exist and are queryable.*

## 2. Phase 1 (E1) — unchanged, one addition

All six custom objects, the 14 standard-object extensions, FLS, seeds. Unaffected.

**Addition:** deploy `Subscription__c.ProductClassification__c` and `Subscription__c.Asset__c` here rather than in a later increment — the `DATA_MODEL.md` §1.4 fallback exists *because* RCA might not arrive. It has not. Revenue Core supplies both sides, so there is nothing to wait for.

Record `RC4` (the `Asset__c` inversion) in the same commit.

## 3. Phase 2 (E2) — now Revenue Core

This is the only phase whose *content* is replaced:

| Original | Now |
|---|---|
| RCA catalogue configuration | `Product_Classification__c` + seeds (`RC2`) |
| `ProductSellingModelOption` | Commitment variant via `Pricing_Rule__mdt.Rule_Type__c = Commitment Variant` |
| RCA bundle adjustment | `Pricing_Rule__mdt` record `Device_Bundle_30_Percent` |
| RCA product configuration rule | `Config_Rule__mdt` record |
| RCA pricing procedure | `Pricing_Procedure__mdt` `Five_Step_Standard` + `PricingService` |
| RCA decision-table export | `pricing-export/` JSON + `manifest.json` sha check |

**Revised E2 exit gate:** *54-entry seed commits; 30% device discount fires from `Pricing_Rule__mdt` with the applied rule named in `PriceBreakdown`; a `NOCOMMIT` quote cannot include a commitment-required device; pricing reproducible from `pricing-export/`.*

## 4. Phases 3–9 — unchanged

E3 acquisition, E4 activation, E5 advisor, E6 lifecycle, E8 integration, E9 hardening all build exactly as written. The only edits are the acceptance-criteria rewordings in file 03 §5.

## 5. Phases 7 and 10 — deferred

| Epic | Disposition | Effect |
|---|---|---|
| E7 — Portal | **Deferred** (`RC5`) | 6 use cases off the critical path. P4's FRONTEND load drops; re-check the allocation in `team.html` if you defer. |
| E10 — Billing | **Closed** (`RC6`) | 3 use cases closed. Q3/BQ7 recorded as *external billing — data-export requirement raised instead*. |

## 6. Suggested first week

1. `RC1` — decide Revenue Core is the approach (you already have, in principle: record it).
2. Phase 0: project skeleton, `reset-test-data.apex`, Revenue Core metadata types deployed empty.
3. Phase 1: the six objects, seeded, idempotent.
4. Phase 2: `Pricing_Rule__mdt` with the 30% device discount, `PricingService.price()`, and a test class proving it fires. That single working vertical slice — *a product, a price, a rule, a computed price, an assertion* — validates the whole Revenue Core premise before you build the remaining four steps of the procedure.

## 7. Definition of done for Revenue Core itself

- [ ] Four metadata types deployed and queryable via `SELECT ... FROM ...__mdt`
- [x] `PricingService.price()` implemented, `with sharing`, deterministic, 17 service tests pass (20 total with evaluator tests)
- [x] `PricingService.priceBulk()` implemented and bulk-safe; 200-request mixed test and 201-request cap guard pass
- [x] `PriceBreakdown.appliedRules` names every rule that fired
- [x] `Config_Rule__mdt` blocks a `NOCOMMIT` quote from a commitment-required device
- [x] `CatalogQueryService.getOptions()` and `getPriceBreakdown()` exist; `getPlans`, `getDevices`, and `filterByEligibility` complete the server-side read path. E5 wizard and deferred E7 portal caller wiring remain.
- [x] `scripts/export-pricing.apex` and `scripts/export-pricing.ps1` produce `pricing-export/` with a matching `manifest.json` SHA-256, a 10-file rollback snapshot, and `scripts/restore-pricing.ps1`; rollback drill restored 336.75 to 314.30
- [x] `scripts/verify-pricing-export.ps1` validates both manifests, totals, JSON file coverage, and rollback record names for the release/CI gate
- [x] Test classes at 75%+ coverage (87% org-wide on the full 76-test local run; 92% `PricingService`; 100% `CatalogQueryService`, `CatalogQueryRepository`, and `CatalogEligibilityFilter`), 200-request mixed bulk test passes
- [x] Supported batch cap is 200; larger workloads must be chunked by callers (10,000-row single call not supported)
- [ ] Headless CPQ script (E9) drives the sequence end-to-end without a UI
