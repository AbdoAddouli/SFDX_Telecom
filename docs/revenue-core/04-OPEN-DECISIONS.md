# 04 — Open decisions register

The 16 register entries from `docs/index.html` (`Q1`–`Q4` + `BQ1`–`BQ12`), deduplicated to **13 distinct questions**, plus what each means now that Revenue Cloud is unavailable. Deciders are unchanged from the blueprint — this is a business answer, not a technical one.

| # | ID(s) | Question | Owner | Blocks | What it means without Revenue Cloud |
|---|---|---|---|---|---|
| 1 | `Q1 / BQ1` | Plan change = amendment or new contract? | Finance + Sales Ops | `UC-LIF-02`, `UC-COM-05`, `UC-DM-04` | Determines whether `Engagement__c` supersedes in place or a new one is born. Unaffected by the licence. **Blocking for E6.** |
| 2 | `Q2` | Target org type & licensing (RCA Growth vs Advanced) | Project sponsor | `UC-FND-03`, all of E2/E4/E5 | **Now answered by circumstance:** no RCA, any tier. Record as *"Deferred — no SKU available on DE org; Revenue Core substituted"*, then unblock E2/E4/E5 via file 03. |
| 3 | `Q3 / BQ7` | Do invoicing & revenue recognition live in Salesforce? | Finance | Entire E10 | **Default answer on your org: No.** RCA Billing SKU unavailable. Close E10 and raise a data-export requirement instead. Do not build `Invoice__c`. |
| 4 | `Q4 / BQ8` | Source & freshness of fibre eligibility data | Network team | `UC-DM-05`, `UC-LIF-01`, `UC-INT-06` | Unaffected. `Eligibility__c` is a plain custom object — buildable once the SLA is known. |
| 5 | `BQ2` | Is the 30-day cancellation notice correct for all categories/segments? | Commercial | `UC-DM-10`, `UC-LIF-03` | Unaffected — validation rule value only. |
| 6 | `BQ3` | Resolved 2026-11-19 — suspension does **not** pause the commitment clock | Commercial + Finance | `UC-LIF-04` unblocked | `Engagement__c` term continues unchanged; `SuspensionService` writes only Subscription, Case, and Customer Request. |
| 7 | `BQ4` | Do expired commitments roll, lapse, or re-price? | Commercial | `UC-LIF-06` | Unaffected. If *re-price*, `PricingService` gets a renewal entry point. |
| 8 | `BQ5 / Q7` | Restocking fee separate from engagement penalty? | Commercial | `UC-LIF-05`, `UC-LIF-03` | Unaffected — may need a second fee line on `Customer_Request__c`. |
| 9 | `BQ6 / Q3-DM` | Same pricebook for Consumer and Business? | Commercial | `UC-CAT-04` | **Now a Revenue Core question too.** One pricebook + `Segment__c` on `Pricing_Rule__mdt` (file 03 §3.2), or two `Pricebook2` records. Answer both at once. |
| 10 | `BQ9` | Goodwill waiver threshold = approval threshold? | Finance | `UC-LIF-03` | Unaffected — approval routing Flow. |
| 11 | `BQ10 / Q6` | Is MSISDN unique globally or per account? | Commercial | `UC-DM-11`, `UC-LIF-07` | **Resolved 2026-11-06 — globally unique.** Duplicate-rule scope remains org-wide; no Revenue Core change. |
| 12 | `BQ11` | Penalty-free window for device commitments | Commercial | `UC-DM-08`, `UC-LIF-01` | Unaffected — seeds `Engagement_Penalty__mdt`. |
| 13 | `BQ12` | Set `Churned` on any line cancel or the last line? | Sales Ops | `UC-LIF-03` | Unaffected — `Account` status derivation rule. |

## Decisions you must add (created by the missing licence)

These are **not** in the blueprint register because the blueprint assumed RCA. They need owners:

| # | New ID | Question | Owner | Blocks |
|---|---|---|---|---|
| N1 | `RC1` | Confirm the Revenue Core approach: build the pricing/config/classification engine rather than purchase RCA | Project sponsor + Solution Architect | Everything in file 03 |
| N2 | `RC2` | Classification: new `Product_Classification__c` object, or fall back to `Product2.Family`? | Solution Architect + A7 | `UC-CAT-01`, 360° grouping, wizard step 3 |
| N3 | `RC3` | Pricebook topology for Revenue Core (fold `BQ6` answer into the rule model) | A7 Pricing Admin | `UC-CAT-04`, `Pricing_Rule__mdt.Segment__c` |
| N4 | `RC4` | Record the `Asset__c` inversion: `Subscription__c` is parent of truth, no RCA amendment driver | Solution Architect | `UC-DM-02`, `UC-LIF-02` reconciliation semantics |
| N5 | `RC5` | E7 disposition: formally deferred (recommended) vs public-form-only substitute | Project sponsor | 6 use cases, P4's FRONTEND load |
| N6 | `RC6` | E10 disposition: closed, or retained as a future paid-SKU epic | Finance | 3 use cases |
| N7 | `RC7` | Testing strategy sign-off: dev-org-only, with `scripts/reset-test-data.apex` as a Phase 0 deliverable | Solution Architect + QA | E0 exit gate substitute |
| N8 | `RC8` | Scaling strategy for price volume (file 02 §3) accepted in place of the 5 GB gate | Solution Architect | E2 exit gate |

## Decision cadence

`UC-FND-06` (*Resolve and record blocking open decisions*) is the vehicle: *"Close or explicitly defer each decision, recording the decision, date, and rationale."* With no sponsor meetings available to you, the pragmatic move is:

1. Answer **N1, N2, N4, N5, N7, N8** yourself now — they are architectural, and you are the architect.
2. Answer **Q2** and **Q3/BQ7** by circumstance (no SKU), and record them as deferred-with-rationale.
3. Carry **Q1/BQ1, Q4/BQ8, BQ2–BQ12** as an explicit assumption table with placeholder values, each tagged `ASSUMPTION — pending <owner>` in the code and metadata. That is honest, auditable, and lets you keep building.

Every assumption you write down becomes a one-line change later — a validation-rule value, a formula, an `Engagement_Penalty__mdt` row. None of them block the Revenue Core build itself.
