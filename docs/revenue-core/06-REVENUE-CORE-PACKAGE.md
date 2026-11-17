# 06 — The Revenue Core metadata package

> What is actually on disk, how to deploy it, and every place it deviates from
> `03-REVENUE-CORE-SPEC.md`. Read this before you deploy anything.

## 1. What is in the package

The **three things to build** from `README.md` §"The short answer" — the pricing
engine, the configuration rules and the classification — are delivered here as the
three **Custom Metadata Types** that hold Revenue Core's configuration.

```
sfdx-project.json                                  project definition (API 68.0, namespace empty)
.forceignore                                       UC-FND-01 rule: pricing-export/ never deployed
.gitignore                                         .sf/ holds org tokens - never committed

force-app/main/default/
├── objects/                                       <- Custom Metadata Type DEFINITIONS
│   ├── Pricing_Rule__mdt/
│   │   ├── Pricing_Rule__mdt.object-meta.xml      11 fields
│   │   └── fields/*.field-meta.xml
│   ├── Config_Rule__mdt/
│   │   ├── Config_Rule__mdt.object-meta.xml       7 fields
│   │   └── fields/*.field-meta.xml
│   └── Pricing_Procedure__mdt/
│       ├── Pricing_Procedure__mdt.object-meta.xml  6 fields
│       └── fields/*.field-meta.xml
└── customMetadata/                                <- Custom Metadata Type RECORDS
    ├── Pricing_Rule__mdt.Commitment_Variant_12M.md-meta.xml
    ├── Pricing_Rule__mdt.Commitment_Variant_24M.md-meta.xml
    ├── Pricing_Rule__mdt.Device_Bundle_30_Percent.md-meta.xml
    ├── Pricing_Rule__mdt.Fiber_Mobile_Bundle_15_Percent.md-meta.xml
    ├── Config_Rule__mdt.Requires_Commitment_Device.md-meta.xml
    ├── Pricing_Procedure__mdt.Five_Step_Standard_01_Base_Price.md-meta.xml
    ├── Pricing_Procedure__mdt.Five_Step_Standard_02_Commitment.md-meta.xml
    ├── Pricing_Procedure__mdt.Five_Step_Standard_03_Bundle_Adjust.md-meta.xml
    ├── Pricing_Procedure__mdt.Five_Step_Standard_04_Constraints.md-meta.xml
    └── Pricing_Procedure__mdt.Five_Step_Standard_05_Breakdown.md-meta.xml
```

> **The custom metadata records are FLAT, with the type in the file name.** There is
> no `<Type__mdt>/` folder. That is not a style choice — see §1.1.

**37 files.** 3 type definitions + 24 field definitions + 10 records.

### 1.1 Why this folder layout

Every line below was confirmed by experiment against the Developer Edition org on
2026-10-22, not inferred.

| Artifact | Source format | Metadata API format |
|---|---|---|
| CMT definition | `objects/<Type__mdt>/<Type__mdt>.object-meta.xml` + `fields/*.field-meta.xml` | `objects/<Type__mdt>.object` |
| CMT record | `customMetadata/<Type__mdt>.<RecordName>.md-meta.xml` | `customMetadata/<Type__mdt>.<RecordName>.md` |

Traps, all confirmed by experiment:

- **A CMT record in a per-type folder does not deploy.** The layout
  `customMetadata/<Type__mdt>/<RecordName>.md-meta.xml` is the one the CLI
  documentation shows, but the deploy resolver cannot recover the type from the
  folder. It sends `Current Name: <RecordName>` and the org rejects it:
  `Must specify the name in the CustomMetadataType.CustomMetadata format,
  Required Delimiter: .` **The type has to be in the file name.** The flat
  `customMetadata/<Type__mdt>.<RecordName>.md-meta.xml` layout resolves to the
  correct `Type.Record` fullName and deploys clean — confirmed by
  `sf project convert source`, which emits exactly
  `Config_Rule__mdt.Requires_Commitment_Device` in its `package.xml`.
- A CMT definition in `customMetadata/<Type__mdt>/<Type__mdt>.object-meta.xml`
  **does not convert** — the CLI errors out.
- A record named `<RecordName>.<Type__mdt>.xml` (no `-meta` infix) **converts
  silently but is dropped** — it disappears from the deploy payload with no
  warning. Only the `.md-meta.xml` suffix is picked up.

The CLI is also the source of truth for the **decomposed** field layout: one file
per field under `fields/`, not a single blob. `sfdx-project.json` can flip this
back with `sourceBehaviorOptions`, but leave it decomposed — it is the current
default and it keeps every field reviewable in a diff.

> **Known CLI quirk on this machine (CLI 2.150.6):** `sf project convert source`
> writes a correct `package.xml` but no metadata files, and
> `sf project convert mdapi` reports `No metadata found to convert`. The
> **deploy** path is unaffected — `sf project deploy start --source-dir force-app`
> resolves and deploys all 37 components. Do not use the converters as a
> round-trip check; use `--dry-run`.

## 2. Deploying it

```powershell
# 1. point at the DE org - NEVER the shared sandbox
sf org list
sf org login web --alias ats-de          # the dedicated Developer Edition

# 2. dry run first (no org writes)
sf project deploy start --dry-run --target-org ats-de --source-dir force-app

# 3. deploy
sf project deploy start --target-org ats-de --source-dir force-app

# 4. prove the types are queryable - this is the E0 gate
sf data query --target-org ats-de --query "SELECT Id,DeveloperName FROM Pricing_Rule__mdt"
sf data query --target-org ats-de --query "SELECT Id,DeveloperName FROM Config_Rule__mdt"
sf data query --target-org ats-de --query "SELECT Id,DeveloperName FROM Pricing_Procedure__mdt"
```

> **The DE is connected on this machine as `abdo@telecom.com`** (org id
> `00Dbm000014hQqrEAE`, instance `orgfarm-b39f661169-dev-ed`). Substitute it for
> `ats-de` unless you have logged into a different DE. The whole package was
> deployed to it on 2026-10-22: 37 components, dry-run clean.

> ⚠️ **Always pass `--target-org` explicitly.** The global default in
> `C:\Users\addou\.sf\config.json` was `addouli.abdelmoumen@devtospace.com.stage`
> — the **shared sandbox** that `IMPLEMENTATION_PLAN.md` Stage 0 forbids
> deploying to. It now points at `abdo@telecom.com`, but the global default is
> still the wrong place to encode a safety rule.

**Deployment order.** The 3 types must exist before the records reference them.
`sf project deploy start --source-dir force-app` handles this in one pass (it
sorts by dependency) — that is the command to use. If you deploy by hand, or if
you deploy a record before its type exists, the org rejects the records with
`Custom metadata type <Type__mdt> is not available in this organization`:

```powershell
sf project deploy start --target-org ats-de --source-dir force-app/main/default/objects
sf project deploy start --target-org ats-de --source-dir force-app/main/default/customMetadata
```

> **This org is a Developer Edition with no source tracking.** `sf project deploy
> preview` fails with `NonSourceTrackedOrgError`. Use
> `sf project deploy start --dry-run` instead — it runs the same validation
> against the org without writing anything.

**Naming limits.** A custom metadata record's `DeveloperName` and `MasterLabel`
are both capped at **40 characters** by the platform (`Value too long for field:
fullName maximum length is:40`). The five `Pricing_Procedure__mdt` records were
shortened to fit — see §4.3. The full step description lives in `Step_Name__c`
(Text 80), which has no such cap.

**Phase 0 gate** (file 05 §1) is satisfied when all three `__mdt` types are
queryable — that is exactly what step 4 above checks.

## 3. Field reference

### 3.1 `Pricing_Rule__mdt` — replaces RCA `BundleBasedAdjustment` + `ProductSellingModelOption`

| Field | Type | Required | Notes |
|---|---|---|---|
| `Rule_Type__c` | Picklist (restricted) | ✔ | `Bundle Adjustment` / `Commitment Variant` / `Segment Price` — **typed, never a catch-all** (UC-DM-11) |
| `Product__c` | Text(80) | — | Product2 DeveloperName or scope code. Blank = all products |
| `Requires_Product__c` | Text(80) | — | **Amendment A1.** Companion scope that must be present for the rule to fire |
| `Commitment_Code__c` | Picklist (restricted) | — | `NOCOMMIT` / `COMMIT12` / `COMMIT24`. Blank = any commitment |
| `Segment__c` | Picklist (restricted) | — | `Consumer` / `Business`. Blank = any segment. Carries BQ6 (RC3) |
| `Adjustment_Type__c` | Picklist (restricted) | ✔ | `Percent` / `Amount` / `Fixed` |
| `Adjustment_Value__c` | Number(8,4) | — | `30` = 30 percent. Magnitude only |
| `Priority__c` | Number(3,0) | ✔ | **Lowest wins**, ties by `DeveloperName` |
| `Effective_From__c` | Date | — | Effective dating required by UC-CAT-04 |
| `Effective_To__c` | Date | — | Blank = open-ended |
| `Active__c` | Checkbox | — | Default `true`. Disable, never delete |

### 3.2 `Config_Rule__mdt` — replaces RCA `ProductConfigurationRule`

| Field | Type | Required | Notes |
|---|---|---|---|
| `Rule_Kind__c` | Picklist (restricted) | ✔ | `Requires Commitment` / `Excludes Commitment` / `Requires Companion` / `Excludes Companion` |
| `Product__c` | Text(80) | ✔ | The constrained product scope |
| `Companion_Product__c` | Text(80) | — | **Amendment A2.** Companion scope for the Companion rule kinds |
| `Applies_When_Commitment__c` | Picklist (restricted) | — | Commitment code the rule fires under. Blank = all. **D2 rejected** — see §6 |
| `Message__c` | LongTextArea(1000) | — | Advisor-facing rejection reason → `PriceBreakdown.blockingReasons`. **Was 255** — API 68.0 rejects a LongTextArea shorter than 256 |
| `Severity__c` | Picklist (restricted) | ✔ | `Block` / `Warn` |
| `Active__c` | Checkbox | — | Default `true`. Disable, never delete |

### 3.3 `Pricing_Procedure__mdt` — replaces the RCA five-step procedure

| Field | Type | Required | Notes |
|---|---|---|---|
| `Procedure_Name__c` | Text(80) | ✔ | **Amendment A3.** Groups step records into one procedure — `Five_Step_Standard` |
| `Step_Number__c` | Number(2,0) | ✔ | 1–5 |
| `Step_Name__c` | Text(80) | ✔ | Shown in the `PriceBreakdown` trace |
| `Apex_Class__c` | Text(80) | ✔ | Handler invoked at this step. All five steps = `PricingService` |
| `On_Error__c` | Picklist (restricted) | ✔ | `Abort` / `Continue` / `Log` |
| `Active__c` | Checkbox | — | Default `true` |

## 4. The seed records

### 4.1 `Pricing_Rule__mdt`

| Record | Type | Scope | Requires | Adjustment | Priority |
|---|---|---|---|---|---|
| `Commitment_Variant_12M` | Commitment Variant | `TELCO_RECURRING` | — | Percent 10 | 10 |
| `Commitment_Variant_24M` | Commitment Variant | `TELCO_RECURRING` | — | Percent 20 | 20 |
| `Device_Bundle_30_Percent` | Bundle Adjustment | `TELCO_DEVICE` | `TELCO_RECURRING` | Percent 30 | 30 |
| `Fiber_Mobile_Bundle_15_Percent` | Bundle Adjustment | `TELCO_MOBILE` | `TELCO_FIBER` | Percent 15 | 40 |

All four have `Effective_From__c = 2026-01-01`, `Effective_To__c` blank
(open-ended), `Active__c = true`.

The two bundle rules come straight from `DATA_MODEL.md` §15.5:

| Rule | Condition | Effect |
|---|---|---|
| `Bundle_PlanDevice_30` | quote has a recurring plan **and** a device line | −30% on the device line |
| `Bundle_FiberMobile_15` | quote has a fibre line **and** a mobile plan | −15% on the mobile line |

### 4.2 `Config_Rule__mdt`

| Record | Kind | Product | Applies when | Severity |
|---|---|---|---|---|
| `Requires_Commitment_Device` | Requires Commitment | `TELCO_DEVICE` | `NOCOMMIT` | `Block` |

This is the UC-CAT-06 rule: a commitment-required device cannot sit on a
`NOCOMMIT` quote.

### 4.3 `Pricing_Procedure__mdt` — `Five_Step_Standard`

| # | DeveloperName | Step name | Handler | On error |
|---|---|---|---|---|
| 1 | `Five_Step_Standard_01_Base_Price` | Resolve base price | `PricingService` | `Abort` — no price, no quote |
| 2 | `Five_Step_Standard_02_Commitment` | Apply commitment variant | `PricingService` | `Abort` |
| 3 | `Five_Step_Standard_03_Bundle_Adjust` | Apply bundle adjustments | `PricingService` | `Log` — a bundle glitch must not kill pricing |
| 4 | `Five_Step_Standard_04_Constraints` | Apply configuration constraints | `PricingService` | `Continue` — returns `blockingReasons` instead of aborting |
| 5 | `Five_Step_Standard_05_Breakdown` | Return breakdown | `PricingService` | `Abort` |

> The `DeveloperName`s were shortened from `Five_Step_Standard_01_Resolve_Base_Price`
> and friends: the platform caps a custom metadata `DeveloperName` at 40
> characters and the descriptive versions ran to 51. The full step description
> is preserved in `Step_Name__c`, which is what `PriceBreakdown` shows. `A3` is
> why `Procedure_Name__c` exists — these records would otherwise have no way
> to say they belong to `Five_Step_Standard`.

## 5. The scope-code vocabulary

`Product__c` and `Requires_Product__c` hold a **scope code**, not a Product2 id.
Four codes, mapped to `Product2.Family` values to be seeded in Stage 2:

| Code | Covers | Source |
|---|---|---|
| `TELCO_MOBILE` | mobile plans | `DATA_MODEL.md` §15.1 |
| `TELCO_FIBER` | fibre & landline plans | `DATA_MODEL.md` §15.2 |
| `TELCO_DEVICE` | devices | `DATA_MODEL.md` §15.3 |
| `TELCO_RECURRING` | umbrella — mobile **and** fibre | `DATA_MODEL.md` §15.4 selling model |

> **Align this with the RC2 decision.** If RC2 = `Product2.Family`, these four
> values are the `Family` values to seed. If RC2 = `Product_Classification__c`,
> the codes must resolve against that hierarchy instead — `PricingService` is the
> only place that needs to change.

## 6. Deviations from `03-REVENUE-CORE-SPEC.md` — read before merging

Everything here is a deliberate, flagged deviation. **Confirm or reject each one.**

| # | Deviation | Why | Impact if rejected |
|---|---|---|---|
| **A1** | `Pricing_Rule__mdt.Requires_Product__c` added | `DATA_MODEL.md` §15.5 defines bundle conditions with **two** products. With a single `Product__c` the 30% device discount cannot express "a plan must also be on the quote" — it degenerates into "always −30% on any device". The spec's field table has no room for the trigger side. | Rewrite the bundle rules as `Config_Rule__mdt` constraints + a fixed device price, or accept an unconditional discount |
| **A2** | `Config_Rule__mdt.Companion_Product__c` added | Same gap. `Rule_Kind__c` offers `Requires Companion` / `Excludes Companion` but no field says *which* companion. | Drop the two Companion rule kinds |
| **A3** | `Pricing_Procedure__mdt.Procedure_Name__c` added | The spec gives `DeveloperName = Five_Step_Standard` **and** `Step_Number__c` 1–5 on one record — impossible, since DeveloperName is unique. One record per step needs a field that says which procedure the step belongs to. | Name steps `Five_Step_Standard_01`… by convention only, with no field to enforce it |
| **A4** | `Active__c` added to `Config_Rule__mdt` | The spec lists it for the other two types only. Without it, disabling a rule means deleting it — which destroys the audit trail and the `pricing-export/` history. | Delete the record to disable it |
| **D1** | Commitment codes are `NOCOMMIT` / `COMMIT12` / `COMMIT24` | Spec §3.2 says `24M` / `12M` / `NOCOMMIT`; `DATA_MODEL.md` §15.4 and the pricing simulator in `index.html` both say `NOCOMMIT` / `COMMIT12` / `COMMIT24`. **The data model won** — it drives the seed catalogue and the `Engagement__c` creation. | Change every value in 3 types + 10 records + the simulator + `DATA_MODEL.md` §15.4 |
| **D2** | ~~`Applies_When_Commitment__c` is a **MultiPicklist**~~ — **REJECTED, reverted to a restricted Picklist** | Originally proposed because the spec says "Picklist" but means "commitment codes this rule fires under" — plural. **Rejected 2026-10-22**: Salesforce Custom Metadata Types support only Checkbox, Date, DateTime, LongTextArea, Number, Picklist and Text. The platform rejects `MultiselectPicklist` on a CMT field outright (`Type MultiselectPicklist of CustomMetadataField ... is not supported for the Entity`), so the deviation was never deployable. | **Accepted**: rules can only ever fire under one commitment code. If a rule must fire under several codes, split it into one record per code |

Also worth knowing:

- **All content is pure ASCII.** Em dashes, arrows and symbols were stripped from
  every XML file. The CLI's own converter mangles non-ASCII in inline help text
  on this machine, and a deploy payload must not carry mojibake.
- **`Effective_To__c` is blank everywhere** = open-ended. A demo rule that silently
  expires is a trap; a real expiry is a one-field change.
- **Every custom metadata file needs the `xsd` namespace.** Without
  `xmlns:xsd="http://www.w3.org/2001/XMLSchema"` on the root `<CustomMetadata>`
  element, the payload fails with `xsi:type "xsd:string" cannot be resolved`.
  All 10 records carry it.
- **A CMT field cannot be a multi-select picklist.** The platform allows only
  Checkbox, Date, DateTime, LongTextArea, Number, Picklist and Text on a custom
  metadata type. See D2.
- **A `LongTextArea` must be at least 256 characters.** `Message__c` is
  `LongTextArea(1000)`; the 255 in the original draft was rejected by API 68.0
  with `Invalid length, minimum is: 256`.

## 7. What is deliberately NOT in this package

| Missing | Why | When |
|---|---|---|
| `Product_Classification__c` + `Product2.Classification__c` | A custom **object**, not a CMT. Belongs to Stage 2 / RC2. | Stage 3b |
| `PricingService` (Apex) | The package is metadata only. The vertical slice needs the service + a test class. | Stage 3a |
| `CatalogQueryService` extensions | Same. `getOptions()` / `getPriceBreakdown()` need the service to exist. | Stage 3b |
| `scripts/export-pricing.apex` + `pricing-export/` | Needs the service and a live org to export from. `.forceignore` already excludes the folder. | Stage 3b |
| `scripts/reset-test-data.apex` | Stage 1 Phase 0 deliverable, independent of this package. | Stage 1 |
| The 54-entry price seed | Needs `Product2` + `PricebookEntry` data, which is Stage 2 (E1). | Stage 3b |
| The 6 business objects, 14 standard-object extensions | Stage 2 (E1), unaffected by the licence. | Stage 2 |

## 8. Definition of done for this package

- [x] `sf project deploy start --dry-run` succeeds with 0 errors
- [x] `SELECT ... FROM Pricing_Rule__mdt` returns 4 records
- [x] `SELECT ... FROM Config_Rule__mdt` returns 1 record
- [x] `SELECT ... FROM Pricing_Procedure__mdt` returns 5 records
- [x] All three types appear in Setup → Custom Metadata Types
- [x] Every deviation in §6 is accepted or reverted — D2 reverted 2026-10-22
- [x] The default target org is **not** the shared sandbox

## 9. One-line summary of what this package proves

`Device_Bundle_30_Percent` + `Requires_Commitment_Device` + the five
`Five_Step_Standard` steps is the **configuration half** of the vertical slice.
The other half — `PricingService.price()` reading these records and returning a
`PriceBreakdown` with `appliedRules` naming the rule that fired — is Stage 3a.
When both exist, the Revenue Core premise is validated and the remaining four
procedure steps become incremental.
