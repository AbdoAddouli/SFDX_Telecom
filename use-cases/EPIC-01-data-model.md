# E1 — Data Model (Phase 1)

**Objective:** build the full data contract every later component binds to — 6 custom objects, custom metadata, settings, validation rules, FLS, indexes, and idempotent seed data.
**Exit gate:** *Deploy succeeds; seeds load idempotently* (`ARCHITECTURE.md` §13).
**Source:** `DATA_MODEL.md` (all sections), `ARCHITECTURE.md` §5, §10, §11.5.

> **Critical path warning:** the data model is one of the two things expensive to change later (`ARCHITECTURE.md` §13). Do not proceed to E2 until E1's exit gate passes.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-DM-01 | Create the six custom objects | Must | Salesforce Developer (Admin/Config) | 🔲 |
| UC-DM-02 | `Subscription__c` — service instance fields, status, formulas | Must | Salesforce Developer | 🔲 |
| UC-DM-03 | `Engagement__c` — commitment fields, status, formulas | Must | Salesforce Developer | 🔲 |
| UC-DM-04 | `Customer_Request__c` — request fields, types, statuses, formulas | Must | Salesforce Developer | 🔲 |
| UC-DM-05 | `Eligibility__c` — fibre coverage lookup table | Must | Salesforce Developer | 🔴 |
| UC-DM-06 | `Integration_Log__c` — observability object | Must | Salesforce Developer | 🔲 |
| UC-DM-07 | `Subscription_Wizard_State__c` — resumable journey state | Must | Salesforce Developer | 🔲 |
| UC-DM-08 | Custom metadata types (`Engagement_Penalty__mdt`, `External_Api__mdc`) | Must | Salesforce Developer | 🔴 |
| UC-DM-09 | Custom setting, custom permissions, value sets, custom labels | Must | Salesforce Admin | 🔲 |
| UC-DM-10 | Standard-object extensions (14 objects) | Must | Salesforce Developer | 🔲 |
| UC-DM-11 | Validation rules and formulas | Must | Salesforce Developer | 🔴 |
| UC-DM-12 | Permission sets and FLS matrix | Must | Solution Architect + Admin | 🔲 |
| UC-DM-13 | Indexes, external IDs, duplicate rules | Must | Solution Architect | 🔴 |
| UC-DM-14 | Idempotent seed data and retention schedulers | Must | Salesforce Developer | 🔲 |

---

### UC-DM-01 — Create the six custom objects

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Developer (Admin/Config) |
| Depends on | UC-FND-04 |
| Blocks | every card UC-DM-02…14 |
| Business process | — |
| Architecture ref | §5.1 |
| Data model ref | §1.2, §19 |
| Status | 🔲 Not started |

**Goal.** Create the six ATS custom objects *without fields first*, so API names exist and later field/deploy steps resolve (`DATA_MODEL.md` §19).

**Preconditions** — E0 complete; dedicated org.

**Main flow**
1. Create `Subscription__c`, `Engagement__c`, `Customer_Request__c`, `Eligibility__c`, `Integration_Log__c`, `Subscription_Wizard_State__c`.
2. Set each object's label, plural label, description, and **data classification** per §16.2 (`Confidential` / `Internal` / `Restricted`).
3. Configure autonumber `Name` formats: `SUB-{0000}`, `ENG-{0000}`, `REQ-{0000}`, `LOG-{0000}`.
4. Create a **Named tab** per object.

**Alternate / exception flows**
- E1: `Subscription__c` collision with the foreign e-commerce object — must **not** occur in a dedicated org (`ARCHITECTURE.md` D3). If it does, stop.

**Business rules**

| Rule | Source |
|---|---|
| Every object has Named tab + description + data classification | §16.1 |
| `Subscription__c` name is free only in a dedicated org | `ARCHITECTURE.md` D3 |

**Acceptance criteria**
- [ ] All six objects exist with autonumber `Name`, description, classification.
- [ ] Named tabs created.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Deploy objects | Query `EntityDefinition` | All six present |
| TS-2 | `devtospace-stage` (if ever used) | Check `Subscription__c` | Collision would be detected — do not build here |

**Definition of done**
- [ ] Deployed to `ats-int`; data classification recorded.

**Open questions / risks** — `R5` name collision; verify at design time.

---

### UC-DM-02 — `Subscription__c` — service instance fields, status, formulas

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | E4, E5, E6, E8 |
| Business process | 05, 11 |
| Architecture ref | §5.3, §7.4 |
| Data model ref | §3 |
| Status | 🔲 Not started |

**Goal.** Build the high-volume service-instance object: one record per active line per service type, with a strictly controlled status field and derived commitment state.

**Preconditions** — UC-DM-01; global value set `ATS_Subscription_Status` (UC-DM-09) or create inline.

**Main flow**
1. Add fields per `DATA_MODEL.md` §3.2, including external IDs: `Subscription_Number__c`, `External_Reference__c` (unique, ext ID), `MSISDN__c` (ext ID, unique when populated).
2. Add lookups: `Account__c` (required), `Product__c` (required), `Asset__c` (1:1, required), `Contract__c`, `Engagement__c`, `Root_Engagement__c`, `Parent_Subscription__c`, `Order_Product__c`, `ProductClassification__c` (**R** — RCA).
3. Create `Status__c` as a **restricted** picklist bound to the global value set, values per §3.3.
4. Add formula fields: `Display_Name__c` (§3.4), `Is_Committed__c` (§3.5), `Next_Renewal_Date__c` (formula over `Billing_End_Date__c`).
5. Add snapshot fields `Monthly_Amount__c`, `Billing_Start_Date__c`, `Billing_End_Date__c` — documented as snapshot-per-§12.
6. Index `Account__c`; request compound indexes in UC-DM-13.

**Alternate / exception flows**
- E1: RCA not enabled → defer `ProductClassification__c` to a later increment (do not drop it).

**Business rules**

| Rule | Source |
|---|---|
| `Status__c` is the only mutable lifecycle field | §3.2 |
| `Is_Committed__c` / `Months_Remaining__c` are formulas, never stored | §3.5, X5, `R11` |
| `Monthly_Amount__c` etc. are snapshots, written once | §12 |

**Acceptance criteria**
- [ ] All §3.2 fields present with descriptions + classification.
- [ ] `Status__c` restricted to the seven allowed values.
- [ ] `Is_Committed__c` and `Display_Name__c` are formulas.
- [ ] `MSISDN__c` and `External_Reference__c` are unique external IDs.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Subscription with active engagement | View `Is_Committed__c` | TRUE |
| TS-2 | Engagement end date passes today | Re-query | `Is_Committed__c` FALSE without any job |
| TS-3 | Product + MSISDN set | View `Display_Name__c` | "Product · MSISDN" |

**Definition of done**
- [ ] Deployed; formula fields verified against today's date changes.

**Open questions / risks** — `R11` stored commitment booleans; enforce formulas in code review.

---

### UC-DM-03 — `Engagement__c` — commitment fields, status, formulas

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A3, A8 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01, UC-DM-08 (penalty metadata) |
| Blocks | E6 |
| Business process | 05, 08, 09 |
| Architecture ref | §5.4 |
| Data model ref | §4 |
| Status | 🔲 Not started |

**Goal.** Build the commitment object whose snapshots make penalties reproducible years later.

**Preconditions** — UC-DM-01; `Engagement_Penalty__mdt` exists (UC-DM-08).

**Main flow**
1. Add fields per §4.2: `Duration_Months__c` (restricted 12/24), `Start_Date__c`, `End_Date__c` (settable), `Status__c` (§4.3), `Monthly_Amount__c` (snapshot), `Penalty_Rate__c` (snapshot), `Early_Termination_Fee__c`, `Penalty_Rule__c` (lookup to `Engagement_Penalty__mdt`), `Penalty_Breakdown__c`, `Breach_Amount__c`, `Goodwill_Waiver__c`, `Goodwill_Justification__c`, `Renewal_Contacted__c`, `Renewal_Contacted_On__c`.
2. Add lookups: `Account__c`, `Subscription__c`, `Root_Engagement__c` (self), `Contract__c`, `Asset__c`.
3. Create formula `Planned_End_Date__c` = `EDATE(Start_Date__c, Duration_Months__c)`.
4. Create formula `Months_Remaining__c` per §4.4 with the nested `IF` guard for `DATEDIF`.

**Alternate / exception flows**
- E1: `DATEDIF` error when start > end → guarded by the nested IF; test with cancelled subscriber data.

**Business rules**

| Rule | Source |
|---|---|
| `Monthly_Amount__c` / `Penalty_Rate__c` snapshots → reproducible fee | §4.5, X4 |
| `Months_Remaining__c` is a formula | §4.4, X5 |

**Acceptance criteria**
- [ ] All §4.2 fields present; `Status__c` restricted to `Pending/Active/Expired/Breached/Transferred`.
- [ ] `Planned_End_Date__c` and `Months_Remaining__c` are formulas; the latter never errors for past engagements.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Engagement End_Date in the past | View `Months_Remaining__c` | 0, no formula error |
| TS-2 | Start date > end date | View | No runtime error |

**Definition of done**
- [ ] Deployed; formula edge cases tested.

**Open questions / risks** — penalty-free window for devices (BQ11) affects seed, not schema.

---

### UC-DM-04 — `Customer_Request__c` — request fields, types, statuses, formulas

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A2, A3, A4 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | E6, E7 |
| Business process | 06, 07, 08, 10 |
| Architecture ref | §5.5 |
| Data model ref | §5 |
| Status | 🔲 Not started |

**Goal.** Build the single controlled entry point for all lifecycle changes — the object that makes "what happened, who asked, what we charged" answerable.

**Preconditions** — UC-DM-01.

**Main flow**
1. Add fields per §5.2 including required `Account__c`, `Contact__c`, `Submitted_By__c`, `Case__c` (conditional — see §5.5), `Subscription__c` (conditionally required), `Eligibility__c`, `Requested_Product__c`, `Impacted_Engagement__c`, `Related_Quote__c`, `Related_Order__c`, `Calculated_Fee__c`, `Fee_Breakdown__c`, `Cancellation_Reason__c`, `Cancellation_Effective_Date__c`, `Approved_By__c`, `Approved_On__c`, `Rejection_Reason__c`, `Resolution_Summary__c`, `Completed_On__c`.
2. Create `Request_Type__c` (§5.3) and `Channel__c` (`Portal/Advisor/API/Batch`) restricted picklists.
3. Create `Status__c` (§5.4) restricted picklist.
4. Create `Is_Compliant_Request__c` formula (§5.6).
5. Implement the **`Info` exception**: `Case__c` becomes a Flow-enforced conditional requirement, not a hard required field (§5.5).
6. Add a Case reciprocal field `Case.Request_Link__c` (UC-DM-10).

**Alternate / exception flows**
- E1: Field-level required accidentally left on `Cancellation_Reason__c` → it would be demanded on non-cancellation requests; must stay OFF (`ARCHITECTURE.md` §5.5).

**Business rules**

| Rule | Source |
|---|---|
| `Account__c` derived server-side, never from client | §5.2, X12 |
| `Calculated_Fee__c` server-computed only | §5.2 |
| `Info` requests create no Case (documented exception) | §5.5 |

**Acceptance criteria**
- [ ] All §5.2 fields present; types/statuses restricted per §5.3–5.4.
- [ ] `Cancellation_Reason__c` field-level required is **OFF**.
- [ ] `Is_Compliant_Request__c` is a formula.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | PlanChange request, no engagement | View | Disabled-hint formula produces correct value |
| TS-2 | Info request | Save | Saves without a Case |

**Definition of done**
- [ ] Deployed; `Info` exception verified.

**Open questions / risks** — Q1 determines whether `Related_Order__c`/`Contract__c` are re-pointed.

---

### UC-DM-05 — `Eligibility__c` — fibre coverage lookup table

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A9, A3 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | UC-LIF-01, UC-INT-06 |
| Business process | 02 |
| Architecture ref | §5.6 |
| Data model ref | §6 |
| Status | 🔴 Blocked — Q4/BQ8 (source system) |

**Goal.** Provide the one-record-per-serviceable-geography lookup that gates every fibre promise.

**Preconditions** — Q4 resolved (source of truth for coverage).

**Main flow**
1. Add fields per §6.2: `Postal_Code__c` (required, unique — the lookup key), `Country__c`, `Region__c`, `City__c`, `Geo_Hash__c`, `Coverage_Polygon__c`, `Fiber_Available__c`, `Max_Downstream_Mbps__c`, `Max_Upstream_Mbps__c`, `Technologies__c` (multiselect `FTTH/FTTC/DSL/Cable/5G`), `Earliest_Activation_Date__c`, `Service_Restrictions__c`, `Is_Active__c`, `Source_System__c`, `Last_Synced_On__c`.
2. `Name` = human-readable locality (e.g. `75001 — Paris 1er`), **not** the lookup key.
3. Implement the §6.3 query pattern assumption: single-index lookup on `Postal_Code__c` + `Is_Active__c`.

**Alternate / exception flows**
- E1: Inactive rows must be retained → request compound index `Postal_Code__c + Is_Active__c` (UC-DM-13).

**Business rules**

| Rule | Source |
|---|---|
| Fibre plan with no active record can never be quoted | BR-02.1 |
| Eligibility is a customer attribute, not a product attribute | BR-02.4 |
| Inactive coverage soft-retires via `Is_Active__c` | §6.2, X7 |

**Acceptance criteria**
- [ ] `Postal_Code__c` required + unique; `Is_Active__c` present.
- [ ] `Fiber_Available__c` validation: availability requires a downstream speed (§11.2).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Postcode with active record | Query §6.3 | Single indexed row returned |

**Definition of done**
- [ ] Deployed; seed per §15.6 loads.

**Open questions / risks** — `R` resolution of Q4; staleness handled in E8.

---

### UC-DM-06 — `Integration_Log__c` — observability object

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | E8 |
| Business process | 05, 07, 08 |
| Architecture ref | §5.7 |
| Data model ref | §7 |
| Status | 🔲 Not started |

**Goal.** Add the object the case study omits — without it a failed provisioning callout is undiagnosable and BSS reconciliation is manual.

**Preconditions** — UC-DM-01.

**Main flow**
1. Add fields per §7.2: `Correlation_Id__c` (required), `Direction__c`, `System__c`, `Operation__c`, `Endpoint__c`, `Status__c`, `Status_Code__c`, `Duration_Ms__c`, `Retry_Count__c`, `Idempotency_Key__c`, `Payload_Doc__c` (**lookup to ContentDocument** — not a text field), `Payload_Summary__c`, `Error_Message__c`, `Subscription__c`, `Order__c` (**R**), `Error_Stack__c`.
2. Restrict `Error_Stack__c` FLS to `ats_OpsAdmin` + `ats_IntegrationUser` only (§7.3).

**Alternate / exception flows**
- E1: Storing full payloads in a text field → rejected; use `Payload_Doc__c` file to keep PII out of a hot table.

**Business rules**

| Rule | Source |
|---|---|
| Payload stored as a File, not a field | §7.2 |
| `Error_Stack__c` never granted to portal/advisor | §7.3 |
| Never log secrets or PII | X15 |

**Acceptance criteria**
- [ ] All §7.2 fields present; `Payload_Doc__c` is a ContentDocument lookup.
- [ ] `Error_Stack__c` FLS restricted.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Log record with error stack | View as `ats_Advisor` | Field not visible |

**Definition of done**
- [ ] Deployed; retention job (UC-DM-14) scheduled.

**Open questions / risks** — highest-volume object; retention is mandatory.

---

### UC-DM-07 — `Subscription_Wizard_State__c` — resumable journey state

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A3 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | E5 |
| Business process | 03 |
| Architecture ref | §8.2 |
| Data model ref | §8 |
| Status | 🔲 Not started |

**Goal.** Persist guided-journey state so a dropped connection, browser crash, or end-of-day does not lose an advisor session.

**Preconditions** — UC-DM-01.

**Main flow**
1. Add fields per §8.1: `Advisor__c` (required), `Account__c`, `Contact__c`, `Opportunity__c`, `Step__c` (1–5), `Offer_Type__c`, `Product__c`, `Selling_Model_Option__c` (**R**), `Device__c`, `Quote__c` (**R**), `Price_Breakdown__c`, `State_Json__c`, `Is_Active__c`, `Last_Activity_On__c`, `Expires_On__c`.
2. Enforce **one active state per advisor** via trigger (built in E5).

**Alternate / exception flows**
- E1: `Expires_On__c` left blank → cleanup batch cannot purge; make it auto-computed = `Last_Activity_On__c + 7`.

**Business rules**

| Rule | Source |
|---|---|
| One active wizard state per advisor | §8.1 |
| Abandoned states hard-deleted after 7 days | §8.2, BR-03.7 |

**Acceptance criteria**
- [ ] All §8.1 fields present; `Expires_On__c` computed.
- [ ] `Price_Breakdown__c` server-computed only (no client write path).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | State inactive 8 days | Run cleanup | Record deleted |

**Definition of done**
- [ ] Deployed; cleanup seeded (UC-DM-14).

**Open questions / risks** — none.

---

### UC-DM-08 — Custom metadata types (`Engagement_Penalty__mdt`, `External_Api__mdc`)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A7, A8, A6 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01 |
| Blocks | UC-LIF-01, E8 |
| Business process | 08 |
| Architecture ref | §9 |
| Data model ref | §9.1, §9.2, §9.3 |
| Status | 🔴 Blocked — BQ11 (device penalty window) for final seed values |

**Goal.** Encode the two genuinely ATS-specific configuration concerns as custom metadata — never as a parallel rule engine.

**Preconditions** — A8 sign-off on penalty matrix (§22 DoD).

**Main flow**
1. Create `Engagement_Penalty__mdt` with fields per §9.1.
2. Seed the **six rows** per §9.1 (Consumer/Business × Mobile/Fiber/Device) with lowest-`Priority__c`-wins resolution.
3. Create `External_Api__mdc` with fields per §9.2.
4. Seed three rows: `Bss_Provisioning` (Cache TTL **0 — never cache provisioning**), `Product_Image`, `Weather`.
5. Do **not** create a `Product_Rule__mdt` (§9.3).

**Alternate / exception flows**
- E1: Someone proposes a catch-all product rule metadata → reject; RCA `BundleBasedAdjustment` / `ProductConfigurationRule` cover it.

**Business rules**

| Rule | Source |
|---|---|
| Penalty rule resolution: lowest `Priority__c` wins | §9.1 |
| Provisioning callout must never be cached | §9.2 |
| No catch-all product rule metadata | §9.3 |

**Acceptance criteria**
- [ ] Both metadata types deployed with all fields.
- [ ] Six penalty rows and three API rows seeded and committed.
- [ ] `Bss_Provisioning.Cache_Ttl_Seconds__c = 0`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Consumer Mobile 12-month row | Resolve penalty | Row selected |
| TS-2 | Two matching rows | Resolve | Lowest priority wins |

**Definition of done**
- [ ] Metadata deployed; seeds in source control.

**Open questions / risks** — BQ11 device window; BQ9 waiver threshold.

---

### UC-DM-09 — Custom setting, custom permissions, value sets, custom labels

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Admin |
| Depends on | UC-DM-01 |
| Blocks | E2, E5, E6, E7 |
| Business process | — |
| Architecture ref | §9, §10 |
| Data model ref | §9.4–9.7 |
| Status | 🔲 Not started |

**Goal.** Provide the configuration surface that lets behaviour change without a deployment, plus the reusable value sets and microcopy.

**Preconditions** — UC-DM-01.

**Main flow**
1. Create hierarchy custom setting `ATS_Feature_Flags__c` with `Wizard_Enabled__c`, `Portal_Requests_Enabled__c`, `BSS_Provisioning_Enabled__c`, `External_Api_Enabled__c`, `Maintenance_Mode__c`, `Cancellation_Approval_Threshold__c`.
2. Create custom permissions: `ats_Force_Activation__c`, `ats_Bypass_Penalty_Approval__c`, `ats_View_Margin__c`, `ats_Run_BSS_Batch__c` (§9.5).
3. Create global value sets: `ATS_Subscription_Status`, `ATS_Request_Channel`, `ATS_Service_Line_Type` (§9.6).
4. Create the **12 custom labels** (§9.7) EN/FR.

**Alternate / exception flows**
- E1: Checklist in `DATA_MODEL.md` §21 references "9 custom permissions" while §9.5 defines 4 → reconcile the count with the architect and correct whichever is wrong.

**Business rules**

| Rule | Source |
|---|---|
| Custom permissions are Flow entry conditions, not profile switches | §9.5 |
| Value sets reused, not duplicated per object | §9.6 |

**Acceptance criteria**
- [ ] Feature-flag setting present with all six fields.
- [ ] 4 custom permissions created (count reconciled with §21).
- [ ] 3 global value sets and 12 labels created.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | `Wizard_Enabled__c = false` | Open wizard | Journey blocked |

**Definition of done**
- [ ] Deployed; count discrepancy resolved and documented.

**Open questions / risks** — §21 vs §9.5 permission-count discrepancy.

---

### UC-DM-10 — Standard-object extensions (14 objects)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A3, A4, A7 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-01, UC-FND-03 (for RCA objects) |
| Blocks | E2, E3, E4, E5, E6, E7 |
| Business process | 01, 03, 04, 05, 10 |
| Architecture ref | §5 |
| Data model ref | §10 |
| Status | 🔲 Not started |

**Goal.** Extend the standard objects the processes bind to, with correct external IDs for idempotency.

**Preconditions** — UC-DM-01; RCA enabled for Quote/Order/Asset/Contract extensions.

**Main flow**
1. `Account`: `Segment__c`, `Customer_Status__c`, `Legacy_Customer_Id__c` (unique ext ID), `Preferred_Language__c`, `Consent_Marketing__c`, `Onboarding_Date__c`, `Advisor__c`.
2. `Contact`: `Do_Not_Call__c`, `Preferred_Contact_Method__c`, `Is_Primary_Contact__c`.
3. `Lead`: `Lead_Source_Detail__c`, `Consent_Given__c`, `Duplicate_Checked__c`, `Convert_Score__c` (PostalCode is standard — no extension).
4. `Opportunity`: `Journey_Step__c`, `Eligibility_Checked__c`, `Portal_Source__c`, `Primary_Contact__c`.
5. `Product2`: `ATS_Product_Code__c` (unique ext ID — seed key), `Plan_Type__c`, `Data_GB__c`, `Speed_Mbps__c`, `Unlimited_Calls__c`, `Unlimited_SMS__c`, `Requires_Commitment__c`, `Recurring__c`, `Device_Image_URL__c`, `Specs__c`, `Is_Active__c`.
6. `Pricebook2`: `Is_Active__c`, `Effective_From__c`, `Effective_To__c`.
7. `Quote`/`QuoteLineItem` (**R**): `Wizard_Session__c`, `Portal_Submitted__c`, `Commitment_Option_Code__c` (snapshot), `Subscription_Key__c`.
8. `Order`/`OrderItem` (**R**): `Activation_State__c` (idempotency guard), `Activated_By__c`, `Activated_On__c`, `BSS_Order_Key__c` (ext ID), `Failure_Reason__c`, `Subscription_Number__c`, `Creates_Asset__c`.
9. `Asset` (**R**): `Service_Line_Type__c`, `Is_Primary__c`, `Provisioned_Status__c`.
10. `Contract`/`ContractLineItem` (**R**): `ATS_Contract_Type__c`, `Signed_On__c`, `Auto_Renew__c`, `Engagement__c`.
11. `Case`: `Request_Link__c`, `Subscription_Link__c`, `Channel__c`.

**Alternate / exception flows**
- E1: RCA not yet enabled → split the (R) fields into a later increment; never remove them.

**Business rules**

| Rule | Source |
|---|---|
| `Commitment_Option_Code__c` snapshotted so catalogue change cannot alter a signed quote | BR-03.6 |
| Devices are `Product2` records, not a `Device__c` object | §18 |

**Acceptance criteria**
- [ ] All listed fields deployed; external IDs unique.
- [ ] `Order.Activation_State__c` restricted to `Not_Eligible/Ready/Activating/Activated/Failed`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Two Order records, same `BSS_Order_Key__c` | Upsert | No duplicate created |

**Definition of done**
- [ ] Deployed; (R) split documented if RCA delayed.

**Open questions / risks** — `R4` RCA field names differ per release; verify.

---

### UC-DM-11 — Validation rules and formulas

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6, A8 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-02…10 |
| Blocks | E6 |
| Business process | 06, 07, 08 |
| Architecture ref | §5.5, §12 |
| Data model ref | §11 |
| Status | 🔴 Blocked — BQ2 (notice period) |

**Goal.** Implement the non-bypassable constraints and the derived formulas, choosing the right mechanism per constraint type.

**Preconditions** — BQ2 resolved for the notice-period rule.

**Main flow**
1. Implement the 11 validation rules in §11.2:
   - `Customer_Request__c`: cancellation reason mandatory; target subscription required; notice period ≥ today+30; rejection requires reason.
   - `Engagement__c`: goodwill waiver justification; duration ∈ {12,24}; end date after start.
   - `Subscription__c`: MSISDN format; termination after activation.
   - `Eligibility__c`: fibre availability requires speeds.
2. Implement cross-object constraints as **Flow/Apex** (cross-object validation rules no longer exist): duration-matches-commitment-option; breach-requires-amount; MSISDN multi-record uniqueness.
3. Implement MSISDN uniqueness as a duplicate rule + selective trigger query (§13.2).

**Alternate / exception flows**
- E1: Temptation to enforce notice period with field-level required → rejected; scope must be conditional.

**Business rules**

| Rule | Source |
|---|---|
| Conditionally required → validation rule (hard, non-bypassable) | §11.1 |
| Cross-object constraint → Flow/Apex (not validation rule) | §11.1 |
| Multi-record uniqueness → Apex trigger | §11.1 |

**Acceptance criteria**
- [ ] All 11 validation rules implemented with the documented error messages.
- [ ] Cross-object constraints implemented as Flow/Apex.
- [ ] Cancel in month 1 of a 12-month contract with window = 1 → fee 0 (BQ/BR-08.5 interplay verified in E6).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Cancellation request, reason blank | Save | Blocked with message |
| TS-2 | Non-cancellation request | Save | Reason not demanded |
| TS-3 | Effective date < today+30 | Save | Blocked |
| TS-4 | Goodwill waiver true, justification blank | Save | Blocked |

**Definition of done**
- [ ] Deployed; each rule has a negative test.

**Open questions / risks** — BQ2 scope; `R9`/`R11` interplay with E6.

---

### UC-DM-12 — Permission sets and FLS matrix

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A3, A4, A5, A6, A7, A2 |
| Suggested owner | Solution Architect + Admin |
| Depends on | UC-DM-02…10 |
| Blocks | E7, E9 |
| Business process | all |
| Architecture ref | §10 |
| Data model ref | §17 |
| Status | 🔲 Not started |

**Goal.** Grant least-privilege access through permission sets (not profiles), matching the FLS matrix exactly — CRUD/FLS is **not** on by default.

**Preconditions** — objects and fields exist.

**Main flow**
1. Create sets: `ats_Advisor`, `ats_AdvisorManager`, `ats_ServiceAgent`, `ats_PortalUser`, `ats_IntegrationUser`, `ats_OpsAdmin`, `ats_PricingAdmin`.
2. Apply the §17 matrix field-by-field.
3. Enforce §17.1 non-negotiables:
   - No `ats_PortalUser` access to manager-level fields (`Approved_By__c`, fee write, `Goodwill_Waiver__c`).
   - **No permission set grants delete** on `Subscription__c`, `Engagement__c`, `Customer_Request__c`.
   - `ats_PortalUser` gets **no** `Integration_Log__c` access.
4. Assign custom permissions (`ats_View_Margin__c`, etc.) to the right sets.
5. Omit sharing rules on `Subscription__c` deliberately (§10).

**Alternate / exception flows**
- E1: Checklist says "8 permission sets" while §17 names 7 → reconcile the count before deploy.

**Business rules**

| Rule | Source |
|---|---|
| Permission sets, not profiles | §10 |
| Financial records soft-closed only — no delete grant | X7, §17.1 |
| Portal never holds integration-log access | §17.1 |
| Sharing rules deliberately omitted | §10 |

**Acceptance criteria**
- [ ] Every set matches §17; no delete grants on financial objects.
- [ ] `ats_PortalUser` cannot read `Integration_Log__c` or manager fields.
- [ ] Custom-permission count reconciled with §9.5.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Run as `ats_PortalUser` | Query `Integration_Log__c` | Access denied |
| TS-2 | Run as `ats_Advisor` | Delete `Subscription__c` | Not permitted |
| TS-3 | Run as `ats_PortalUser` | Read `Approved_By__c` | Not visible |

**Definition of done**
- [ ] Deployed; FLS tests pass as each persona.

**Open questions / risks** — count discrepancies (§17 vs §21).

---

### UC-DM-13 — Indexes, external IDs, duplicate rules

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6 |
| Suggested owner | Solution Architect |
| Depends on | UC-DM-02, UC-DM-05 |
| Blocks | E5, E6, E8, E9 |
| Business process | 05, 09, 11 |
| Architecture ref | §5 |
| Data model ref | §13 |
| Status | 🟡 In progress — Q6 resolved org-wide; 6/7 external IDs verified; index case prepared, not submitted |

**Goal.** Ensure the highest-frequency queries remain selective at millions of records and that duplicates are impossible.

**Preconditions** — Q6 resolved 2026-11-06: `MSISDN__c` is org-wide unique. Request the compound indexes.

**Main flow**
1. Confirm the 7 external IDs (§13.1): `Subscription__c.External_Reference__c`, `Subscription__c.MSISDN__c`, `Engagement__c.Engagement_Number__c`, `Account.Legacy_Customer_Id__c`, `Product2.ATS_Product_Code__c`, `Order.BSS_Order_Key__c` (**R**), `Eligibility__c.Postal_Code__c`. Six are deployed and unique; `Engagement__c` uses the auto-number `Name` reference (see checkpoint).
2. Request the 7 compound indexes (§13.2), notably `Subscription__c.Account__c + Status__c` (the 360° query) and `Status__c + Next_Renewal_Date__c` (renewal batch). Case text is prepared in `docs/salesforce-support-custom-index-request.md`; submission needs a support-entitled org.
3. Create a duplicate rule on `MSISDN__c` with org-wide scope.

**Alternate / exception flows**
- E1: Index request denied → escalate; the 360° view will not scale without it.

**Business rules**

| Rule | Source |
|---|---|
| Every external ID is unique and the sole integration key | §16.1 |
| Renewal scan must use a `Database.QueryLocator` + compound index | §13.3 |

**Acceptance criteria**
- [ ] 6 deployed external-ID fields unique; Engagement reference confirmed as auto-number `Name` or a separate external ID approved.
- [ ] 7 compound indexes submitted/confirmed through a support-entitled org.
- [x] Duplicate rule prevents duplicate populated MSISDNs within scope.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | 1M subscriptions | Query account+status | Selective plan |

**Definition of done**
- [ ] Indexes confirmed; duplicate rule active.

**Open questions / risks** — Q6 resolved 2026-11-06 (org-wide unique). The compound index request remains outstanding. `Engagement__c.Engagement_Number__c` is a spec inconsistency: §4.2 requires an Auto Number and §13.1 requires an External ID; the deployed reference is the auto-number `Name`.

---

### UC-DM-14 — Idempotent seed data and retention schedulers

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 1 |
| Actor(s) | A6, A7 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-13, UC-DM-05, UC-DM-08 |
| Blocks | E2 exit gate |
| Business process | 02, 03 |
| Architecture ref | §11.5 |
| Data model ref | §14, §15, §21 |
| Status | 🟡 In progress — seeds and 2 cleanup jobs complete; renewal/BSS jobs deferred |

**Goal.** Load the catalogue and coverage baseline idempotently, and schedule the cleanup/reconciliation jobs the data lifecycle requires.

**Preconditions** — objects, indexes, metadata deployed.

**Main flow**
1. Write idempotent seed scripts using `sf data upsert` on external IDs — **never** `insert` (§11.5).
2. Seed `Product2`: 4 mobile + 2 fibre + 3 devices with `ATS_Product_Code__c` (§15.1–15.3).
3. Seed 4 selling models/options and 2 bundle adjustments (§15.4–15.5) — executed in E2.
4. Seed 7 `Eligibility__c` records (§15.6), including the inactive `75099`.
5. Deploy schedulers: `IntegrationLogCleanupBatch` (weekly, hard delete > 13 months), `WizardStateCleanupBatch` (nightly), `RenewalOutreachScheduler` (daily — wired in E6), `BssReconciliationBatch` (nightly — wired in E8).

**Alternate / exception flows**
- E1: Re-running the seed duplicates catalogue → the use of `insert` is a defect; must use upsert.

**Business rules**

| Rule | Source |
|---|---|
| Seeds are idempotent (upsert, not insert) | §11.5, anti-pattern §15 |
| `Integration_Log__c` hard-deleted at 13 months (not soft) | §14.1 |
| Wizard state hard-deleted after 7 days | §14.2 |

**Acceptance criteria**
- [ ] Re-running all seeds produces zero duplicates.
- [ ] All four schedulers deployed and active.
- [ ] 9 products, 7 eligibility records load from a clean org.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Catalogue seeded once | Run seed again | Count unchanged |
| TS-2 | Log 14 months old | Run cleanup | Deleted |

**Definition of done**
- [ ] E1 exit gate met: deploy succeeds, seeds load idempotently.

**Open questions / risks** — none.
