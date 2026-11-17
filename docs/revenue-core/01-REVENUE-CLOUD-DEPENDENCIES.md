# 01 — Every Revenue Cloud dependency in the blueprint

Traceable list of every use case that depends on Revenue Cloud Advanced (RCA), plus the fallback that the epic files themselves already document. Source: `use-cases/EPIC-*.md`, `DATA_MODEL.md` §1.4 and §18, `ARCHITECTURE.md` §3.3.

## 1. The licence gate

| ID | Title | Status | Blocked by |
|---|---|---|---|
| `UC-FND-03` | Enable Revenue Cloud Advanced and required org configuration | 🔴 Blocked | **Q2** (RCA Growth vs Advanced SKU) |

- RCA **cannot be enabled via CLI** — it requires the Salesforce account team (`ARCHITECTURE.md` §3.3).
- `UC-FND-03` **blocks**: E2, E4, E5, and three RCA-dependent lookups in `DATA_MODEL.md` §1.4.
- **Your situation:** Q2 never resolves, because there is no SKU to buy on a DE org. Treat `UC-FND-03` as **permanently deferred**, and take the documented alternate flow: *"base objects (E1) proceed; the RCA-dependent lookup fields are split into a later deployment increment."*

## 2. Blocked use cases and their documented fallbacks

### E2 — Catalog & Pricing

| ID | Blocked by | RCA dependency | Documented fallback |
|---|---|---|---|
| `UC-CAT-01` | RCA enablement | Replace flat `Product2.Family` with RCA attribute-based `ProductClassification` | *"RCA not enabled → classification deferred; catalogue stays in `Product2.Family` temporarily (documented, not permanent)"* |

| ID | RCA dependency | Your replacement |
|---|---|---|
| `UC-CAT-03` | `ProductSellingModelOption` (commitment as variant pricing on one product) | Pricebook2 variant strategy — see file 03 §3.2 |
| `UC-CAT-05` | RCA `BundleBasedAdjustment` (30% device discount) | `Pricing_Rule__mdt` record, evaluated by `PricingService` |
| `UC-CAT-06` | RCA `ProductConfigurationRule` (mandatory commitment) | `Config_Rule__mdt` record |
| `UC-CAT-07` | RCA five-step pricing procedure | `Pricing_Procedure__mdt` + `PricingService.execute()` |
| `UC-CAT-08` | Delegates to the **RCA Pricing API** server-side | `PricingService` — the same single-server-side-path guarantee holds |
| `UC-CAT-09` | `pricing-export/` holds RCA decision tables | Same folder holds the **custom metadata records** exported as JSON — keep the folder, keep the discipline |

> `UC-DM-11` contains an explicit rejection you must honour: *"Someone proposes a catch-all product rule metadata → reject; RCA `BundleBasedAdjustment` / `ProductConfigurationRule` cover it."* With RCA gone, `Config_Rule__mdt` **is** the sanctioned mechanism — but it must stay **typed and specific** (bundle adjustment vs configuration rule are different record types), never a single catch-all blob.

### E4 — Commerce & Activation

| ID | Blocked by | RCA dependency |
|---|---|---|
| `UC-COM-02` | Q1 / BQ1 | Contract + ContractLineItem as commercial container |
| `UC-COM-01` | *(implicit)* | Calls the RCA **Configuration API** + **Transaction API** to build `Quote`/`QuoteLineItem` |

- **Acceptance criterion to preserve:** *"No price arithmetic in the service beyond RCA's returned values."* With Revenue Core, `OfferBuilderService` must obey the identical rule — **all arithmetic lives in `PricingService`**, none in the builder.

### E5 — Advisor Experience

The five-step wizard hard-depends on RCA at steps 3 and 5:

- Step 3 — *"option-aware filtering via the RCA Configuration API"*
- Step 5 — *"server-side RCA price breakdown (rendered read-only)"*

Replacement: `CatalogQueryService` gains `getOptions(productId)` (config rules) and `getPriceBreakdown(...)` (pricing service).

### E6 — Lifecycle

- Plan change path step 3 — *"Re-quote — `CatalogQueryService` + RCA pricing → new `Quote`"*. Same replacement as E5.

### E7 — Portal

- Business rule **BR-10.6** — *"Portal pricing is the identical server-side RCA price."* This rule is a **design guarantee, not an RCA requirement**: as long as both channels call the same Apex service, the rule holds with Revenue Core. **Keep the rule, change the implementation.**

### E9 — Hardening & NFR

- *"Script the full configure-price-quote sequence without a UI (RCA is API-first)."* This becomes your **headless integration test for Revenue Core** — arguably more valuable now, since you wrote the engine and can drive it directly.

### E10 — Billing *(conditional — do not build)*

| ID | Status | Gate |
|---|---|---|
| `UC-BIL-01` | 🔴 Blocked | Q3 / BQ7 |
| `UC-BIL-02` | 🔴 Blocked | Q3, **and** "RCA Billing SKU available" |
| `UC-BIL-03` | 🔴 Blocked | Q3 |

`DATA_MODEL.md` §18: `Invoice__c` and `Payment__c` are **not to be pre-built**. Do not create placeholder objects. E10 has only two legal outcomes: **closed** (external billing → raise a data-export requirement instead) or **built later** with a billing SKU you do not have.

## 3. Data model fields that assume RCA

`DATA_MODEL.md` §1.4 marks three RCA-dependent lookups on `Subscription__c`. Per the fallback, **deploy them in a later increment, never remove them**:

| Field | Marked | RCA role |
|---|---|---|
| `ProductClassification__c` | **R** | Drives 360° grouping |
| `Asset__c` | **R** (1:1) | *"RCA drives amendments from `Asset`. `Subscription__c` mirrors it"* |
| `Contract__c` | — | *"RCA owns contracts; we reference, never write directly"* |

The `Asset__c` 1:1 relationship is the one that matters most: with no RCA, **`Subscription__c` becomes the parent of truth** and `Asset__c` is a passive provisioned-equipment record. Document this inversion explicitly — it changes who wins in a reconciliation dispute.

## 4. Summary count

| Category | Count |
|---|---|
| Use cases blocked by RCA enablement | 2 (`UC-FND-03`, `UC-CAT-01`) |
| Use cases whose *implementation* must be substituted | 7 (`UC-CAT-03/05/06/07/08`, `UC-COM-01`, wizard steps in `UC-UX-07`) |
| Use cases where only the *acceptance criteria wording* changes | 4 (`UC-CAT-09`, `UC-BR-10.6`, E9 headless test, `UC-CAT-08` parity rule) |
| Use cases permanently out of scope without a purchase | 3 (E10) + 6 (E7 portal) |
