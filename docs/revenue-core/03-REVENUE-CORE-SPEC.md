# 03 — Revenue Core: the build spec

The engine that replaces Revenue Cloud Advanced for the 80 use cases. **Scope-frozen**: it implements exactly what `UC-CAT-01` through `UC-CAT-09` and `UC-COM-01`/`UC-UX-07` demand. No generic pricing engine, no metadata-driven anything-beyond-this.

## 1. Component map

```
Revenue Core
├── Classification   Product_Classification__c          (replaces RCA ProductClassification)
├── Configuration    Config_Rule__mdt                   (replaces RCA ProductConfigurationRule)
├── Pricing          Pricing_Procedure__mdt
│                    Pricing_Rule__mdt
│                    PricingService (Apex)              (replaces RCA pricing procedure + API)
├── Consumption      CatalogQueryService (extended)     (the single server-side path both channels use)
└── Export           pricing-export/ (JSON dumps)       (replaces RCA decision-table export)
```

**Not in Revenue Core** — already covered by the blueprint: `ActivationService` (`UC-COM-03`), subscription state machine (`UC-COM-04`), `OfferBuilderService` (`UC-COM-01`), `EngagementPenaltyService` (`UC-LIF-01`).

## 2. Classification — `Product_Classification__c`

Replaces RCA's attribute-based `ProductClassification` that `UC-CAT-01` cannot build.

| | |
|---|---|
| Type | Custom object, `__c` |
| Purpose | Tree that groups products for the 360° view and the wizard's plan step |
| Key fields | `Name`, `Parent__c` (self-lookup), `Level__c` (Picklist: Family / Type / Variant), `Sort_Order__c`, `External_Id__c` (Text, **External ID, Unique**) |
| Related | `Product2.Classification__c` — lookup to this object |
| Seed | 9 products' families, from `use-cases/EPIC-02` |

**Fallback if you want zero new objects:** keep `Product2.Family` (the documented epic fallback) and add a `Classification_Path__c` formula field. The epic calls this *"documented, not permanent"* — so record the decision either way in file 04.

**Deployment note:** `DATA_MODEL.md` §1.4 marks the `Subscription__c.ProductClassification__c` lookup as **R** (RCA). Deploy it in the later increment as the fallback prescribes — here, now that Revenue Core exists.

## 3. Pricing

### 3.1 `Pricing_Procedure__mdt`

Mirrors the five-step procedure `UC-CAT-07` specifies, as ordered metadata so the sequence is auditable and exportable.

| Field | Type | Notes |
|---|---|---|
| `MasterLabel` / `DeveloperName` | — | `Five_Step_Standard` |
| `Step_Number__c` | Number(2,0) | 1–5 |
| `Step_Name__c` | Text | e.g. `Select base price` |
| `Apex_Class__c` | Text(80) | Handler invoked at this step |
| `On_Error__c` | Picklist | `Abort` / `Continue` / `Log` |
| `Active__c` | Checkbox | |

Steps: (1) resolve base `PricebookEntry` → (2) apply commitment variant → (3) apply bundle adjustments → (4) apply configuration constraints → (5) return breakdown.

### 3.2 `Pricing_Rule__mdt`

Replaces RCA `BundleBasedAdjustment` (`UC-CAT-05`) and carries the commitment-variant logic (`UC-CAT-03`).

| Field | Type | Notes |
|---|---|---|
| `MasterLabel` / `DeveloperName` | — | e.g. `Device_Bundle_30_Percent` |
| `Rule_Type__c` | Picklist | `Bundle Adjustment` / `Commitment Variant` / `Segment Price` |
| `Product__c` | Text(80) | Product2 DeveloperName or family code |
| `Commitment_Code__c` | Picklist | `24M` / `12M` / `NOCOMMIT` |
| `Segment__c` | Picklist | `Consumer` / `Business` (answers BQ6 one way; record the choice) |
| `Adjustment_Type__c` | Picklist | `Percent` / `Amount` / `Fixed` |
| `Adjustment_Value__c` | Number(8,4) | `30` for the device discount |
| `Priority__c` | Number(3,0) | Conflict resolution — **lower wins**, ties broken by `DeveloperName` |
| `Effective_From__c` / `Effective_To__c` | Date | Effective dating, required by `UC-CAT-04` |
| `Active__c` | Checkbox | |

**Non-negotiable:** rules are typed by `Rule_Type__c`. `UC-DM-11` rejects a catch-all product rule; Revenue Core honours that by keeping bundle adjustment, commitment variant and configuration constraint as *different record types*, never one flexible blob.

### 3.3 `Config_Rule__mdt`

Replaces RCA `ProductConfigurationRule` (`UC-CAT-06` — a device requiring a commitment must not appear on a `NOCOMMIT` quote).

| Field | Type | Notes |
|---|---|---|
| `Rule_Kind__c` | Picklist | `Requires Commitment` / `Excludes Commitment` / `Requires Companion` / `Excludes Companion` |
| `Product__c` | Text(80) | The constrained product |
| `Applies_When_Commitment__c` | Picklist | Commitment codes this rule fires under |
| `Message__c` | Textarea | The advisor-facing rejection reason |
| `Severity__c` | Picklist | `Block` / `Warn` |

### 3.4 `PricingService` (Apex)

The single authoritative price path. `UC-CAT-08`'s guarantee — *"portal and advisor identical for identical input"* — is preserved by construction: both call this class, neither does arithmetic.

```
public with sharing class PricingService {
    public class PriceBreakdown {
        Id productId; String commitmentCode; String segment;
        Decimal listPrice; Decimal adjustmentTotal; Decimal finalPrice;
        List<AppliedRule> appliedRules;      // auditable
        List<String> blockingReasons;        // from Config_Rule__mdt
    }
    public static PriceBreakdown price(Id productId, String commitmentCode,
                                       String segment, Date effectiveDate);
    public static List<PriceBreakdown> priceBulk(List<PriceRequest> requests); // ≤200 rows
    public static List<ConfigResult> evaluateConfiguration(Id productId, String commitmentCode);
}
```

Rules of the class:

- **`with sharing`** — never leak prices across FLS boundaries.
- **Bulk-first** — `priceBulk` is the entry point any Flow, LWC or service uses. No per-record loops.
- **Deterministic** — same inputs, same output. `Priority__c` then `DeveloperName`.
- **Auditable** — `AppliedRule` names every rule that fired, so a price dispute is explainable years later (the same reproducibility requirement `Engagement__c` snapshots serve for penalties).
- **No DML** — it is a pure calculation service. Persisting a price is `OfferBuilderService`'s job.

### 3.5 `CatalogQueryService` extension

Two new methods carry the wizard and portal:

| Method | Replaces | Used by |
|---|---|---|
| `getPlans(type, commitment)` *(existing)* | — | Wizard step 3 |
| `getOptions(productId, commitment)` **new** | RCA Configuration API filtering | Wizard step 3 |
| `getPriceBreakdown(...)` **new** | RCA Pricing API server-side breakdown | Wizard step 5, portal, `UC-UX-06` |

## 4. Export — `pricing-export/`

`UC-CAT-09` requires pricing to be reproducible from version control. With RCA, that folder held decision tables. Now it holds a JSON dump of the metadata:

```
pricing-export/
├── procedures/Five_Step_Standard.json
├── rules/Device_Bundle_30_Percent.json
├── config-rules/Requires_Commitment_Device.json
└── manifest.json          # export timestamp, record count, sha of each file
```

Exported by `scripts/export-pricing.apex` (anonymous Apex → `Messaging.SingleEmailMessage` attachment, or `sf data query --result-format json` per type). The `.forceignore` rule from `UC-FND-01` — *exclude from normal deploy, track in git* — still applies verbatim.

**Refresh discipline:** the manifest's `sha` is the check. A CI step compares the org's live metadata against `manifest.json`; a mismatch means someone edited pricing in Setup without exporting, and the gate fails.

## 5. Where the blueprint's acceptance criteria change wording

| Use case | Original criterion | Revenue Core wording |
|---|---|---|
| `UC-CAT-08` | *"Service returns RCA price breakdown"* | *"Service returns `PricingService` price breakdown; portal and advisor identical for identical input"* — **the guarantee is unchanged** |
| `UC-COM-01` | *"No price arithmetic beyond RCA's returned values"* | *"No price arithmetic beyond `PricingService`'s returned values"* — **unchanged in spirit** |
| BR-10.6 | *"Portal pricing is the identical server-side RCA price"* | *"...identical server-side `PricingService` price"* |
| E9 headless test | *"Script the full CPQ sequence (RCA is API-first)"* | *"Script the full CPQ sequence against `PricingService` / `CatalogQueryService`"* — now a true white-box test |
| E2 exit gate | *"5 GB plan prices committed"* | *"54-entry seed commits correctly; scaling strategy documented to N thousand (see file 02 §3)"* |

## 6. Explicitly out of scope

- Tax, invoicing, payment, revenue recognition (E10 — blocked by Q3/BQ7, forbidden pre-build by `DATA_MODEL.md` §18)
- Any customer-authenticated portal surface (E7 — Experience Cloud licence)
- `Asset__c` as amendment parent — inverted: `Subscription__c` is truth (file 01 §3)
- Generic pricing features not demanded by the 80 use cases: tiers, slabs, rate matrices, usage rating, multi-currency, proration
