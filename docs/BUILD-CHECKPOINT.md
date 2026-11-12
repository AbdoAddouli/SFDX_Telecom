# ATS Telecom Build Checkpoint

**Last updated:** 2026-11-12  
**Org:** `abdo@telecom.com` (`00Dbm000014hQqrEAE`)  
**Current step:** E4 UC-COM-03 activation, the wizard “Finish & Activate” hand-off, and UC-COM-04 subscription state machine are complete. `SubscriptionWizardController.finishAndActivate()` locks the wizard session, converts the wizard Quote into one Order plus OrderItems, marks the Quote Accepted, and delegates to `ActivationService`. Activation is savepoint-guarded, idempotent, and BSS-backed; on BSS failure the Order returns to Ready for retry while the wizard session stays active. The Step 5 LWC now exposes Finish & Activate, Retry Activation, and View Order. `SubscriptionStateMachine` and `SubscriptionTriggerHandler` now enforce the allowed Subscription status moves from every DML path and block hard deletes. Targeted activation/wizard tests pass 41/41; the state machine plus MSISDN tests pass 18/18; the full local Apex suite passes 157/157. E5 remains closed. Next: UC-COM-05 Activation Flow / “Validate the Order” custom action; Q1/BQ1 ContractLineItem semantics and E6/E8 jobs remain.

---

## What is complete

### Data model (earlier work)

- 6 custom objects deployed.
- 53 custom fields on standard objects deployed.
- UC-DM-13 external IDs: 6 deployed fields are External ID + Unique;
  `Order.BSS_Order_Key__c` was changed to `unique=true` on 2026-11-06.
- `ATS_Feature_Flags__c` hierarchy custom setting + 7 fields, with the org-default record loaded.
- 4 custom permissions.
- 3 global value sets created.
- 12 custom labels + 12 French translations.
- 8 permission sets deployed; `ats_Admin` assigned to the running user.
- All 6 custom object tabs exist; persona tab visibility added to the 8 permission sets.
- `ats_AdvisorManager` now has the §17 read access on `Integration_Log__c` (object read + 9 field reads; `Error_Stack__c` excluded).
- `ats_IntegrationUser` standard-object permissions trimmed to read-only so the Integration User license can hold it; assigned to `integration@00dbm000014hqqreae.com`.
- Persona assignments: `ats_Admin`, `ats_OpsAdmin`, `ats_PricingAdmin` → `abdo@telecom.com`; `ats_Advisor` → `safaeazzam@telecom.com`; `ats_AdvisorManager` → `zini.yahya@telecom.com`; `ats_ServiceAgent` → `yassin@telecom.com`. `ats_PortalUser` remains unassigned because no portal/community user exists.

### Permission-set tab visibility (complete)

The 6 `CustomTab` components already existed. The permission-set metadata enum is
`Visible` / `Available` / `None` (not `DefaultOn` / `DefaultOff` / `Hidden`):

| Metadata value | Org `PermissionSetTabSetting.Visibility` |
|---|---|
| `Visible` | `DefaultOn` |
| `Available` | `DefaultOff` |
| `None` | no row (hidden / no access) |

| Permission set | Visible tabs | Available (default off) | Hidden |
|---|---|---|---|
| `ats_Admin` | all 6 | — | — |
| `ats_Advisor` | Subscription, Engagement, Customer Request, Eligibility, Wizard State | — | Integration Log |
| `ats_AdvisorManager` | all 6 | — | — |
| `ats_ServiceAgent` | Subscription, Engagement, Customer Request, Eligibility | — | Integration Log, Wizard State |
| `ats_PortalUser` | — | Subscription, Engagement, Customer Request, Eligibility | Integration Log, Wizard State |
| `ats_IntegrationUser` | — | — | all 6 (no UI access) |
| `ats_OpsAdmin` | all 6 | — | — |
| `ats_PricingAdmin` | — | Subscription, Engagement, Customer Request, Eligibility | Integration Log, Wizard State |

### Revenue Core metadata (already deployed, verified)

| Type | Records |
|---|---|
| `Pricing_Rule__mdt` | 4 |
| `Config_Rule__mdt` | 1 |
| `Pricing_Procedure__mdt` | 5 |

### Revenue Core pricing engine (complete 2026-11-07)

`PricingService` is deployed and verified as a thin facade. It resolves active
`PricebookEntry` rows, filters active and effective `Pricing_Rule__mdt`
records, matches product scope/commitment/segment, evaluates optional companion
scopes, and returns `PriceBreakdown` records with an auditable `appliedRules`
list. `PricingBatchRepository` performs the batch queries; `PricingContext`
carries per-request state; `PricingScope` owns shared matching; and
`PricingRuleEvaluator` plus `ConfigurationRuleEvaluator` are pure evaluators
with no SOQL or DML. The facade is `with sharing` and performs no DML.

- `priceBulk()` is the authoritative entry point. It performs one `Product2`,
  `PricebookEntry`, `Pricing_Rule__mdt`, and `Config_Rule__mdt` query per
  batch and returns results in request order. `price()` delegates to it for a
  single request.
- `PricingService.MAX_BATCH_SIZE = 200` is enforced. Larger workloads must be
  chunked by callers; a single 10,000-row call is deliberately not supported
  because it risks heap exhaustion.
- `evaluateConfiguration()` supports all four `Config_Rule__mdt` kinds
  (`Requires Commitment`, `Excludes Commitment`, `Requires Companion`,
  `Excludes Companion`). `Block` messages populate
  `PriceBreakdown.blockingReasons`; `Warn` messages populate `warningReasons`.
- Tests: the focused E2 suite (`PricingServiceTest`,
  `ConfigurationRuleEvaluatorTest`, and `CatalogQueryServiceTest`) passes
  37/37. At the E2 checkpoint the full local suite passed 76/76 at 87%
  org-wide coverage; after UC-COM-01 the full suite passes 103/103 at 87%.
  Focused classes range from 82% to 100%; `CatalogQueryService`,
  `CatalogQueryRepository`, and `CatalogEligibilityFilter` are all 100%. The
  bulk test prices 200 mixed requests in one call, and a 201-request guard test
  asserts the cap.
- Real-org smoke test: Samsung S22 `449.00 -> 314.30` with the 30% device
  bundle; the same device on `NOCOMMIT` returns one blocking reason; Mobile
  20 GB `14.99 -> 13.49` with the 10% `COMMIT12` variant.
- The 4-argument overload intentionally does not apply rules that require a
  companion product. The 5-argument overload accepts companion scopes such as
  `TELCO_MOBILE` or `TELCO_RECURRING`.
- `CatalogQueryService` is the single server-side catalogue and pricing read
  path. It is a thin facade: `CatalogQueryRepository` owns the `WITH USER_MODE`
  SOQL, and `CatalogEligibilityFilter` owns the pure fibre speed/activation
  decision. `getPlans(type, commitment)` filters `Product2.Plan_Type__c`, active
  flags, and commitment-required plans; `getDevices()` filters
  `Family = 'TELCO_DEVICE'`; `getOptions()` and `getPriceBreakdown()` delegate
  to `PricingService`; `filterByEligibility()` applies the fibre speed cap and
  future-activation warning without mutating the caller's views. Non-fibre-only
  lists bypass the eligibility query. Apex class access is granted to the seven
  human-facing permission sets; the integration user is deliberately not
  granted UI class access.
- `CatalogQueryServiceTest` passes 16/16; the service, repository, and filter
  are all at 100% coverage. The suite exercises offer-type validation,
  commitment filtering, active/retired products, device images, speed caps,
  no-fibre postcodes, future activation, non-fibre pass-through, mixed lists,
  null inputs, configuration blocking, and pricing delegation. It also asserts
  bounded query counts and that eligibility filtering does not mutate its
  input.
- Real-org smoke test: 4 mobile plans, 2 fibre plans, and 3 devices returned;
  Mobile 20 GB at `COMMIT12` prices at 13.49; `75001` exposes both fibre
  speeds, `59000` exposes none; Samsung S22 returns one `NOCOMMIT` block and
  zero blocks at `COMMIT12`.
- `pricing-export/` contains one JSON file per procedure, pricing rule, and
  configuration rule plus `manifest.json` (6 files, 10 records, SHA-256 per
  file). `scripts/export-pricing.apex` emails a zip of the same layout;
  `scripts/export-pricing.ps1` writes the folder locally. The local manifest
  hashes were re-read and verified.
- `pricing-export/rollback/` contains the 10 deployable custom-metadata XML
  files and a SHA-256 `manifest.json`. `scripts/restore-pricing.ps1` verifies
  the snapshot, copies it outside the `.forceignore`-excluded tree, deploys it,
  and cleans up. The drill changed `Device_Bundle_30_Percent` from 30 to 25 in
  a temporary source tree, priced Samsung S22 at 336.75, then used the rollback
  snapshot to restore 30 and the 314.30 price.
- `scripts/verify-pricing-export.ps1` is the offline release/CI gate. It
  recomputes both manifests, checks file and record totals, rejects unmanifested
  JSON files, and cross-checks the rollback record names against the export. It
  passes on the current 6-file/10-record export and fails on a tampered copy.

### E5 advisor-wizard gap closure (complete 2026-11-12)

- **Step 1 — Confirm information:** `ATS_Feature_Flags__c.Is_Autosync__c` is a
  hierarchy checkbox (default true; the org-default record is set to true). The
  wizard shows editable Contact email/phone fields; changes are debounced by
  700 ms and persisted through `SubscriptionWizardController.saveContactDetails()`.
  The method requires a wizard session, scopes the Contact to the session
  Account, uses `WITH USER_MODE`/`AccessLevel.USER_MODE`, skips no-op writes,
  and rolls back on DML failure. Account fields remain read-only because
  `ats_Advisor` has Account read-only and Contact edit.
- **Step 3 — Plan filtering:** `PricingService.evaluateConfigurations()`
  evaluates the full plan list against the `Config_Rule__mdt` set in one query;
  `CatalogQueryService.getPlans()` removes plans with blocking option rules
  before the picker. `getPlans()` now issues two bounded queries (products +
  config rules), not one per plan.
- **Fibre fix:** `CatalogQueryService.ProductView` moved from plain Aura fields
  to `{ get; set; }` properties. `filterByEligibility()` receives the plan list
  back from the LWC; with plain fields, Aura deserialized every view as empty,
  so the fibre picker showed blank labels and invalid `productId` values.
  Properties preserve the round-trip without changing the service API.
- **Browser verification:** Step 1 debounce saved Contact changes; full fibre
  `75001` → `Fiber 100 Mb + Landline` → €39.99 → quote created on a temporary
  account (then cleaned up); future `OFB13001` → “Activation is blocked until
  2026-12-15.” and Create Quote disabled; capped `OFB69001` (20 Mbps) exposed
  only the 20 Mbps plan and kept Create Quote enabled.
- **Targeted Apex tests:** 48/48 across `SubscriptionWizardControllerTest`,
  `PricingServiceTest`, and `CatalogQueryServiceTest`. The full local Apex
  suite passes 120/120.

### E4 activation and wizard hand-off (complete 2026-11-12)

`ActivationService` implements UC-COM-03 as a bulk-safe, idempotent transaction.
`SubscriptionWizardController.finishAndActivate()` supplies the missing
quote-to-order hand-off.

- `ActivationService.activateOrder()` caps one invocable call at 80 orders so
  the savepoint limit stays safe; the bulk test covers 200 OrderItems in one
  order. It locks the Order row, requires `Activation_State__c = Ready`, and
  uses `Activation_State__c` (`Not_Eligible`, `Ready`, `Activating`,
  `Activated`, `Failed`) because standard `Order.Status` only has `Draft` and
  `Activated`.
- Contract binding is isolated in `ActivationContractWriter`. The current
  default is amend: reuse `Order.ContractId` when present, otherwise create a
  minimal Draft Contract, then activate it after BSS success. No
  `ContractLineItem` is written because standard `ContractLineItem` belongs to
  `ServiceContract`, not `Contract`; Q1/BQ1 remains unresolved.
- BSS access is behind `BssProvisioningGateway`.
  `SimulatedBssProvisioningGateway` returns `SIM-{SubscriptionNumber}` and uses
  `Subscription__c.Name` for idempotency.
  `External_Api__mdt.Bss_Provisioning` is active, but the `BSS_Api` Named
  Credential does not exist yet, so the real callout stays in E8.
- Activation creates Asset → Subscription → Engagement for each recurring plan
  line. Device lines inherit the nearest preceding plan engagement, or the
  first plan engagement. `Engagement_Key__c` is `ENG-{OrderItemId}`,
  `Subscription__c.External_Reference__c` is unique,
  `OrderItem.Subscription_Number__c` is the reconciliation back-link, and
  `OrderItem.Commitment_Option_Code__c` snapshots the accepted commitment.
- `ActivationPenaltyPolicy` resolves the metadata penalty. Verified examples:
  Consumer Fiber 12M stores `Consumer_Fiber_12M` / `25`; Business Mobile 12M
  stores `Business_Any` / `15`. `NOCOMMIT` creates no Engagement and leaves
  `ContractTerm` null because `Contract` rejects a zero term.
- Success and failure write `Integration_Log__c`; success stores the BSS
  correlation in `Order.BSS_Order_Key__c`. BSS failure rolls local DML back,
  returns the Order to `Ready`, records the failure reason, and leaves no
  orphan Asset, Subscription, Engagement, or Contract.
- `finishAndActivate(sessionId, quoteId)` locks the wizard session row with
  `FOR UPDATE` so a double-click cannot create two orders, validates the Quote
  against the session Account/Contact, loads QuoteLineItems, and finds an
  existing order by `Name = Quote.QuoteNumber`. The Order description carries
  the Quote Id as a linkage marker because standard `Order` has no Quote
  lookup.
- On first call it creates one Order (`Draft`, `Activation_State__c = Ready`,
  `EffectiveDate = today`) and copies product, pricebook entry, quantity,
  price, description, service date, and commitment from each QuoteLineItem.
  It marks the Quote `Accepted`, then calls `ActivationService`.
- The wizard session is deactivated only after successful activation or a
  no-op retry. On failure it stays active and `State_Json__c` stores
  `orderId`, `orderNumber`, `activationStatus`, and the failure message so the
  user can retry from Step 5 or after a refresh.
- The Step 5 LWC now shows **Finish & Activate**, **Retry Activation** after a
  failure, and **View Order** plus the activation summary on success.
- Tests: targeted `ActivationServiceTest` and `SubscriptionWizardControllerTest`
  pass 41/41; the full local Apex suite passes 157/157 after the UC-COM-04
  state-machine tests. The wizard tests cover success, double-call idempotency,
  BSS failure followed by retry, missing quote lines, and missing session.
- Activation DML is user-mode. Every current human user holds System
  Administrator, so the wizard path works in this org today. `ats_Advisor` and
  `ats_AdvisorManager` remain read-only on Order, OrderItem, Asset, Contract,
  Subscription__c, and Engagement__c. Before either set is assigned to a
  non-admin user, E9 must grant the activation object/field CRUD/FLS or route
  the hand-off through an ops-owned service. This is tracked as E9 FLS
  hardening, not silently widened in the persona matrix.

### E4 subscription state machine (UC-COM-04, complete 2026-11-12)

`SubscriptionStateMachine` owns the explicit allowed-transition map.
`SubscriptionTriggerHandler` is called from the single `Subscription__c`
trigger; the existing `SubscriptionMSISDNTrigger` name is retained to avoid a
destructive trigger rename, and the same trigger still delegates MSISDN
uniqueness to `SubscriptionMSISDNDuplicateHandler`.

- Allowed moves: `Draft → PendingActivation → Active`; `Active ⇄ Suspended`;
  `Active → PendingCancellation → Cancelled`; `Active → Superseded`.
  `Cancelled` and `Superseded` are terminal.
- Inserts must start in `Draft` or `PendingActivation`; a blank start status
  defaults to `Draft`. Direct `Active` inserts, `Active → Cancelled`, attempts
  to reopen a terminal state, and every out-of-map move add a field-level error
  through the trigger, including data loads, API, Flow, and integration DML.
- Same-status updates are allowed so unrelated edits are not blocked.
- `before delete` adds an error for every subscription. Hard delete is blocked;
  records must be soft-closed through `Cancelled` or `Superseded`.
- `ActivationService` remains compatible: it inserts `PendingActivation` and
  moves each subscription to `Active` only after BSS success.
- Tests: `SubscriptionTriggerHandlerTest` 11/11 and the existing MSISDN tests
  7/7; targeted state-machine coverage 18/18. The full local Apex suite passes
  157/157.

### Quote creation service (UC-COM-01, complete 2026-11-09)

`OfferBuilderService` is a thin `public with sharing` facade that exposes
`createQuote(Selection)` for LWC callers and the invocable
`createQuotes(List<Selection>)`. The implementation is split by responsibility:

- `OfferContext` resolves and validates the account, contact, wizard, and
  opportunity, normalizes offer type/commitment, and performs read-only SOQL.
- `OfferCatalog` resolves the plan and device through `CatalogQueryService` and
  applies fibre speed/activation eligibility.
- `OfferQuotePricing` builds the plan/device pricing requests in one batch,
  calls `PricingService.priceBulk()`, validates the breakdowns, and serializes
  the persisted price snapshot.
- `OfferQuoteText` formats opportunity/quote/line text and generated
  subscription keys without data access.
- `OfferQuoteResult` maps persisted records and pricing breakdowns to the public
  `OfferResult`.
- `OfferQuoteWriter` owns user-mode persistence for the Opportunity, Quote,
  QuoteLineItems, and wizard update.

- Reads use user mode through `CatalogQueryService`. All DML uses
  `AccessLevel.USER_MODE` and is wrapped in a savepoint; any validation,
  pricing, or DML failure rolls back the Opportunity, Quote, QuoteLineItems,
  and wizard update.
- The service resolves or creates the Opportunity, validates the account,
  contact, and wizard relationships, checks offer type, commitment, plan/device
  family, and fibre coverage, and creates one Quote plus QuoteLineItems from
  `PricingService.priceBulk()`.
- Each line snapshots `UnitPrice` from `PriceBreakdown.finalPrice`, stores
  `Commitment_Option_Code__c`, and receives a generated
  `Subscription_Key__c`. The Quote stores `Wizard_Session__c` and
  `Portal_Submitted__c`, and the wizard session advances to Step 5.
- `QuoteLineItem.Commitment_Option_Immutable` rejects changes to
  `Commitment_Option_Code__c` after insert. Blank commitment input resolves to
  `NOCOMMIT`; supported values are `NOCOMMIT`, `COMMIT12`, and `COMMIT24`.
- Permission metadata: `OfferBuilderService` class access is granted to
  `ats_Admin`, `ats_Advisor`, `ats_AdvisorManager`, and `ats_OpsAdmin`;
  `ats_IntegrationUser` is deliberately excluded. `ats_Advisor` now has
  create/edit on Quote and editable access to `Quote.Wizard_Session__c`,
  `Quote.Portal_Submitted__c`, `QuoteLineItem.Commitment_Option_Code__c`, and
  `QuoteLineItem.Subscription_Key__c`. The org exposes no independent
  `QuoteLineItem` object-permission rows; line-item access follows the Quote
  while field permissions are stored explicitly.
- Tests: `OfferBuilderServiceTest` passes 26/26. Coverage is 100% for
  `OfferBuilderService`, 92.7% for `OfferCatalog`, 89.8% for `OfferContext`,
  87.1% for `OfferQuotePricing`, 88% for `OfferQuoteText`, 85.2% for
  `OfferQuoteResult`, and 85.7% for `OfferQuoteWriter`. The full local suite
  passes 103/103 at 87% org-wide coverage.
- Real-org smoke test: Mobile 20 GB `COMMIT12` plus Samsung S22 produced two
  persisted lines, a generated quote number, and a total of 327.79. The
  two-line request used 9 SOQL queries and 8 DML statements with no per-line
  queries. The anonymous Apex test rolled back all records and left no customer
  or quote behind.

### Custom metadata types (complete)

| Type | Records | Fields | Status |
|---|---|---|---|
| `Engagement_Penalty__mdt` | 6 | 10 | Deployed 2026-11-03 |
| `External_Api__mdt` | 3 | 7 | Deployed 2026-11-03 |

Penalty matrix loaded (lowest `Priority__c` wins):

| Priority | Segment | Category | Months | After | Rate | Cap |
|---|---|---|---|---|---|---|
| 10 | Consumer | Mobile | 12 | 1 | 20% | 100% |
| 20 | Consumer | Mobile | 24 | 3 | 15% | 100% |
| 30 | Consumer | Fiber | 12 | 1 | 25% | 100% |
| 40 | Consumer | Fiber | 24 | 3 | 20% | 100% |
| 50 | Consumer | Device | any | 0 | 50% | 100% |
| 90 | Business | Any | any | 0 | 15% | 100% |

External API registry loaded: `Bss_Provisioning` (NamedCredential, cache 0),
`Product_Image` (cache 86400), `Weather` (cache 3600).

### Validation rules (complete)

| Object | Rule | Enforces |
|---|---|---|
| `Customer_Request__c` | `Cancellation_Reason_Required` | Cancellation requests need a reason |
| `Customer_Request__c` | `Target_Subscription_Required` | Five target-bearing request types need a subscription |
| `Customer_Request__c` | `Cancellation_Notice_Period` | Effective date at least 30 days out |
| `Customer_Request__c` | `Rejection_Reason_Required` | Rejected requests need a reason |
| `Engagement__c` | `Goodwill_Justification_Required` | Goodwill waiver needs a justification |
| `Engagement__c` | `Duration_12_Or_24` | Commitment is 12 or 24 months |
| `Engagement__c` | `End_Date_After_Start` | End date strictly after start |
| `Subscription__c` | `MSISDN_Format` | 7-15 digits, optional leading `+` |
| `Subscription__c` | `Termination_After_Activation` | No termination before activation |
| `Eligibility__c` | `Fiber_Requires_Speeds` | Fibre needs a positive downstream speed |

All 10 are active in the org (verified by retrieve). §11.2 contains 13 headings,
but three are explicitly not validation rules:

- `Engagement__c` — Breach requires an amount: spec says Flow, because
  `Early_Termination_Fee__c` is written by Apex.
- `Subscription__c` — Uniqueness when populated: `COUNT()` is unavailable in
  validation rules. Implemented outside validation rules with a matching rule,
  a duplicate rule, and a before-save Apex trigger (below).
- `Engagement__c` — Duration must match the commitment option: cross-object, so
  Flow/Apex per §11.1.

The breach-amount check and the duration-vs-commitment check are now implemented
as Flows, and the MSISDN uniqueness check as matching/duplicate rules plus an
Apex trigger (all below).

#### Formula corrections applied during verification

Three §11.2 formulas were inverted: they fired when the record was compliant
instead of when it violated the rule. The deployed rules now match their error
messages.

| Rule | Deployed formula |
|---|---|
| `Engagement__c.Duration_12_Or_24` | `NOT(OR(Duration_Months__c = 12, Duration_Months__c = 24))` |
| `Engagement__c.End_Date_After_Start` | `OR(ISBLANK(End_Date__c), End_Date__c <= Start_Date__c)` |
| `Subscription__c.Termination_After_Activation` | `AND(NOT(ISBLANK(Termination_Date__c)), NOT(ISBLANK(Activation_Date__c)), Termination_Date__c < Activation_Date__c)` |

### Engagement breach-amount Flow (complete)

`Engagement_Breach_Amount_Required` is an active record-triggered after-save
Flow (`AutoLaunchedFlow`, API 68.0, version 1) on `Engagement__c`.

- Trigger: create or update, entry condition `Status__c = Breached`.
- Decision: `$Record.Breach_Amount__c` is null.
- Action: Custom Error on `Breach_Amount__c` with the message
  `Breach Amount is required when Status is Breached.`
- Runs after save so Apex-written penalty fields are visible. A value of `0` is
  allowed, which supports a fully waived fee.
- Verified with anonymous Apex: an `Active` Engagement with
  `Breach_Amount__c = 0` saved, then the update to `Breached` with a blank
  amount was rejected with the custom error. The test records were deleted.
- Source: `force-app/main/default/flows/Engagement_Breach_Amount_Required.flow-meta.xml`.

### Engagement duration-vs-commitment Flow (complete)

`Engagement_Duration_Must_Match_Commitment` is an active record-triggered
after-save Flow (`AutoLaunchedFlow`, API 68.0, version 6) on `Engagement__c`.

- Trigger: create or update.
- Guard: runs only when `$Record__Prior.Id` is null (create) or
  `Duration_Months__c` / `Subscription__c` changed. This avoids SOQL on
  unrelated updates. `IsChanged` entry criteria cannot be used because they
  evaluate false on create.
- Resolves `QuoteLineItem` for the related Subscription using
  `QuoteLineItem.Subscription_Key__c = Subscription__c.Name`, ordered by
  `CreatedDate DESC`, first record only.
- Commitment mapping: `COMMIT12` / `12M` → 12; `COMMIT24` / `24M` → 24;
  `NOCOMMIT` → block any Engagement.
- No quote line found: the save is allowed.
- Action: Custom Error on `Duration_Months__c` when the duration does not match,
  and a separate Custom Error for `NOCOMMIT`.
- Verified with anonymous Apex:
  1. `COMMIT12` + duration 24 on create → blocked.
  2. No quote line → allowed.
  3. `COMMIT12` + duration 12 on create → allowed.
  4. Update 12 → 24 → blocked; stored duration remained 12.
  5. Latest quote line `NOCOMMIT` → blocked.
  6. Two quote lines (older `COMMIT12`, newer `NOCOMMIT`) → blocked with the
     `NOCOMMIT` message, proving the Flow uses the newest `CreatedDate`.
  All test records were deleted.
- Data note: `Subscription__c.Name` is an auto-number that is not populated on
  the in-memory record immediately after insert in Apex. The quote-line
  `Subscription_Key__c` must be copied from the re-queried Subscription Name.
- Source: `force-app/main/default/flows/Engagement_Duration_Must_Match_Commitment.flow-meta.xml`.

### Subscription MSISDN duplicate handling (complete)

`Subscription__c.MSISDN__c` already has `unique=true`. To provide a consistent
friendly message, the org also has:

| Component | API name | Detail |
|---|---|---|
| Matching rule | `Subscription__c.ATS_MSISDN_Match_Rule` | Exact match on `MSISDN__c`; blanks not matched; active |
| Duplicate rule | `Subscription__c.ATS_MSISDN_Duplicate_Rule` | Block on insert and update; alert text `A Subscription with this MSISDN already exists.`; active |
| Apex trigger | `SubscriptionMSISDNTrigger` | `before insert, before update`; calls the handler |
| Apex class | `SubscriptionMSISDNDuplicateHandler` | Bulk-safe; detects duplicates within one DML batch and against existing rows; adds a field-level error |
| Apex test | `SubscriptionMSISDNDuplicateHandlerTest` | 7 tests, 100% pass |

Source files:

- `force-app/main/default/matchingRules/Subscription__c.matchingRule-meta.xml`
- `force-app/main/default/duplicateRules/Subscription__c.ATS_MSISDN_Duplicate_Rule.duplicateRule-meta.xml`
- `force-app/main/default/triggers/SubscriptionMSISDNTrigger.trigger`
- `force-app/main/default/classes/SubscriptionMSISDNDuplicateHandler.cls`
- `force-app/main/default/classes/SubscriptionMSISDNDuplicateHandlerTest.cls`

Source-format matching rules use a per-object container file named
`<Object>.matchingRule-meta.xml`; the child `fullName` is the bare rule name.
The duplicate rule references the bare matching-rule name. The duplicate rule
is redundant with the field's `unique=true` constraint but provides the
documented duplicate-rule governance and a UI-level alert; the trigger provides
the friendlier API/DML message.

- Spec deviation: `Database.getDuplicateRecords` is not an Apex method. The
  supported duplicate API is `Datacloud.FindDuplicates`; the handler uses a
  selective SOQL query on the unique, indexed `MSISDN__c` field instead. This
  keeps the check bulk-safe and returns the same field-level message.

**Q6 resolved 2026-11-06:** `Subscription__c.MSISDN__c` is unique **org-wide**,
not per `Account`. A phone number identifies one subscription globally. The
existing field constraint, exact matching rule, blocking duplicate rule, Apex
handler, and seven tests already implement this scope; no deployment was needed.

### Data lifecycle cleanup (partial)

Two of the four `UC-DM-14` jobs are deployed, tested, and scheduled:

| Job | Type | Schedule | Behavior |
|---|---|---|---|
| `IntegrationLogCleanupBatch` | `Database.Batchable` + `Schedulable` | Weekly, Sunday 02:00 (`0 0 2 ? * SUN`) | Hard-deletes `Integration_Log__c` rows with `CreatedDate` older than 13 months; batch size 2,000 |
| `WizardStateCleanupBatch` | `Database.Batchable` + `Schedulable` | Nightly 01:00 (`0 0 1 ? * *`) | Hard-deletes `Subscription_Wizard_State__c` rows whose `Expires_On__c` is in the past; falls back to `Last_Activity_On__c` older than 7 days when the expiry is blank |

The wizard job does not filter on `Is_Active__c`: expiry is the retention
signal, and filtering on the session-concurrency flag would leave abandoned
rows that were never explicitly deactivated. The fallback also covers older
rows whose `Expires_On__c` was not populated.

Deployment and verification:

- `IntegrationLogCleanupBatchTest` and `WizardStateCleanupBatchTest`: 5/5 tests pass.
- Active `CronTrigger` records verified:
  `ATS Integration Log Cleanup (Weekly)` next fire 2026-11-08 and
  `ATS Wizard State Cleanup (Nightly)` next fire 2026-11-07.
- Scheduled jobs are org configuration, not deployable metadata; re-create them
  with `System.schedule` when building a new org.

Source files:

- `force-app/main/default/classes/IntegrationLogCleanupBatch.cls`
- `force-app/main/default/classes/IntegrationLogCleanupBatchTest.cls`
- `force-app/main/default/classes/WizardStateCleanupBatch.cls`
- `force-app/main/default/classes/WizardStateCleanupBatchTest.cls`

Still deferred: `RenewalOutreachScheduler` (wired in E6) and
`BssReconciliationBatch` (wired in E8).

### Page layouts (complete)

All 20 layouts were deployed on 2026-11-04. The six custom-object layouts were
rewritten from the flat defaults into logical sections; the 14 standard-object
layouts were enhanced in place, preserving the standard sections and related
lists. Because the existing default layouts were modified, no profile layout
assignment was needed.

| Object | ATS section / layout purpose | Related lists added |
|---|---|---|
| `Subscription__c` | Subscription Details, Commercial and Dates, Commitment Links | Engagements, Customer Requests, Integration Logs, Child Subscriptions |
| `Engagement__c` | Commitment Details, Penalty and Financials, Renewal and Hierarchy | Subscriptions, Root Subscriptions, Customer Requests, Child Engagements, Contract Line Items |
| `Customer_Request__c` | Request Details, Related Records, Cancellation and Fees, Approval and Resolution | Related Cases |
| `Eligibility__c` | Coverage Details, Network Capability | Customer Requests |
| `Integration_Log__c` | Integration Details, Related Records, Payload and Error | — |
| `Subscription_Wizard_State__c` | Wizard Session, Customer Context, Offer Context, Session Payload | Quotes |
| `Account` | ATS Customer Profile | Subscriptions, Engagements, Customer Requests, Wizard States |
| `Contact` | ATS Contact Preferences | Subscriptions, Customer Requests, Wizard States, Opportunities |
| `Case` | ATS Request Links | Customer Requests |
| `Opportunity` | ATS Journey | Wizard States |
| `Product2` | ATS Product Details | Subscriptions, Customer Requests, Wizard Product, Wizard Device |
| `Pricebook2` | ATS Price Book Details | — |
| `Quote` | ATS Quote Details | Wizard States, Customer Requests |
| `QuoteLineItem` | ATS Line Details | — |
| `Order` | ATS Activation | Customer Requests, Integration Logs |
| `OrderItem` | ATS Subscription Details | Subscriptions |
| `Asset` | ATS Service Line | Subscriptions, Engagements |
| `Contract` | ATS Contract Details | Subscriptions, Engagements |
| `ContractLineItem` | ATS Engagement | — |
| `Lead` | ATS Lead Qualification | — |

Implementation notes:

- Related lists use the `RelatedListDefinition` `RelatedListId` (for example
  `Engagement__c.Subscription__c`), not the child relationship name.
- Related-list columns use exact case-sensitive `RelatedListColumnDefinition`
  aliases; custom fields keep their API-name casing (for example `Status__c`,
  not `STATUS__c`).
- Layouts cannot contain `CreatedDate` or `LastModifiedDate`; the system
  sections use `CreatedById` and `LastModifiedById`.
- New `relatedLists` elements must precede `relatedObjects` / `show*` elements
  in the `Layout` XML; appending them at the end causes
  `Element relatedLists is duplicated at this location`.
- All 20 layouts were retrieved back from the org after deployment and their
  sections and related-list IDs were checked.
- The 14 standard layouts are confirmed as the System Administrator profile's
  assigned layouts; the six custom-object layouts are the objects' default
  layouts.
- Source files are in `force-app/main/default/layouts/` (20
  `*.layout-meta.xml` files).

### Compact layouts (complete)

Six compact layouts were deployed on 2026-11-05 and assigned as each custom
object's compact layout. Each contains ten fields, led by `Name`.

| Object | Compact layout | Fields |
|---|---|---|
| `Engagement__c` | `ATS_Engagement_Compact` | Name, Status, Account, Subscription, Start Date, End Date, Duration, Monthly Amount, Early Termination Fee, Breach Amount |
| `Subscription__c` | `ATS_Subscription_Compact` | Name, Status, Account, Service Line Type, MSISDN, Product, Monthly Amount, Activation Date, Next Renewal Date, Current Engagement |
| `Customer_Request__c` | `ATS_Customer_Request_Compact` | Name, Request Type, Status, Account, Contact, Channel, Priority, Due Date, Calculated Fee, Subscription |
| `Eligibility__c` | `ATS_Eligibility_Compact` | Name, Postal Code, City, Region, Country, Fiber Available, Max Downstream, Max Upstream, Earliest Activation Date, Active |
| `Integration_Log__c` | `ATS_Integration_Log_Compact` | Name, System, Operation, Direction, Status, Status Code, Duration (ms), Retry Count, Correlation ID, Subscription |
| `Subscription_Wizard_State__c` | `ATS_Subscription_Wizard_State_Compact` | Name, Step, Active, Account, Contact, Product, Device, Offer Type, Commitment Code, Expires On |

Implementation notes:

- The layouts are under each object's `compactLayouts/` directory, and the
  object metadata sets `<compactLayoutAssignment>` to the corresponding layout.
- `Eligibility__c.Technologies__c` is a multi-select picklist, which Salesforce
  rejects in a compact layout (`Cannot use item ... in a compact layout`).
  `Region__c` is displayed instead; `Technologies__c` remains on the page layout.
- The deployed layouts were retrieved back from the org and their assignment
  and ten-field order were verified.

### Feature flags (complete)

Org-default hierarchy record created 2026-11-03 (`a07bm00001T45tEAAR`,
`SetupOwnerId = 00Dbm000014hQqrEAE`):

| Field | Value |
|---|---|
| `Wizard_Enabled__c` | true |
| `Portal_Requests_Enabled__c` | true |
| `BSS_Provisioning_Enabled__c` | true |
| `External_Api_Enabled__c` | true |
| `Maintenance_Mode__c` | false |
| `Cancellation_Approval_Threshold__c` | 0 |
| `Is_Autosync__c` | true |

`Cancellation_Approval_Threshold__c = 0` is deliberately conservative: any fee
above zero routes to manager approval until Finance answers BQ9
(goodwill-waiver threshold vs approval threshold). Update the record when the
decision lands; no deployment is needed.

### §15 seed catalogue (complete)

| Item | Status |
|---|---|
| `Product2` seed records | **9 / 9 loaded** |
| `Eligibility__c` seed records | **7 / 7 loaded** |
| `PricebookEntry` — standard price book | **9 / 9 loaded** |
| `PricebookEntry` — active `Standard` price book | **9 / 9 loaded** |
| `Pricebook2` ATS flags on active book | `Is_Active__c = true`, `Effective_From__c = 2026-01-01` |

The final missing row (`PHONE_SAMSUNG_S22`, €449.00, active `Standard` price
book) was created on 2026-11-03. The seed is now complete and idempotent.

---

## Verification results

### Products

| Code | Name | Family | Plan Type |
|---|---|---|---|
| `MOBILE_5` | Mobile 5 GB | `TELCO_MOBILE` | Mobile |
| `MOBILE_20` | Mobile 20 GB | `TELCO_MOBILE` | Mobile |
| `MOBILE_50` | Mobile 50 GB | `TELCO_MOBILE` | Mobile |
| `MOBILE_100` | Mobile 100 GB | `TELCO_MOBILE` | Mobile |
| `FIBER_20` | Fiber 20 Mb + Landline | `TELCO_FIBER` | Fiber |
| `FIBER_100` | Fiber 100 Mb + Landline | `TELCO_FIBER` | Fiber |
| `PHONE_IPHONE_15_PRO` | iPhone 15 Pro | `TELCO_DEVICE` | — |
| `PHONE_IPHONE_13` | iPhone 13 | `TELCO_DEVICE` | — |
| `PHONE_SAMSUNG_S22` | Samsung S22 | `TELCO_DEVICE` | — |

### Eligibility

7 records: `75001`, `75002`, `69001`, `13001`, `33000`, `59000`, and inactive `75099`.

### Pricebooks

| Pricebook | IsStandard | IsActive | Is_Active__c | ATS entries |
|---|---|---|---|---|
| Standard Price Book | true | false | false | 9 |
| Standard | false | true | true | 9 |

The standard price book is inactive in this org. Salesforce still requires a
standard price to exist before a custom price can be created, so the seed keeps
standard entries populated and mirrors prices into the active `Standard`
pricebook.

---

## Re-running the seed

The loader is idempotent:

```powershell
.\scripts\seed-catalogue.ps1
```

Last run (2026-11-03) reported:

- products processed=9, failed=0
- eligibility processed=7, failed=0
- standard pricebook entries: 9 unchanged
- active pricebook entries: 1 created, 8 unchanged

Current totals:

- `Product2` with `ATS_Product_Code__c != null`: **9**
- `Eligibility__c`: **7**
- `PricebookEntry` for ATS products: **18** (9 standard + 9 active)
- All 18 entries are active, with prices matching `DATA_MODEL.md` §15.

---

## Files added for the seed

| File | Purpose |
|---|---|
| `data/seed/products.csv` | 9 products, upsert key `ATS_Product_Code__c` |
| `data/seed/pricebook-entries.csv` | 9 product codes + list prices |
| `data/seed/eligibility.csv` | 7 postcode records, upsert key `Postal_Code__c` |
| `scripts/seed-catalogue.ps1` | Idempotent loader for all three |

---

## Environment notes

- The org is **single-currency** (`CurrencyIsoCode` does not exist on
  `PricebookEntry`). The seed prices are stored as the numeric EUR values from
  `DATA_MODEL.md` §15, but Salesforce displays them in the org's default
  currency. Multi-currency/EUR was not enabled.
- `Product2.Family` uses the Revenue Core scope codes from
  `docs/revenue-core/06-REVENUE-CORE-PACKAGE.md` §5:
  `TELCO_MOBILE`, `TELCO_FIBER`, `TELCO_DEVICE`. `TELCO_RECURRING` is the
  umbrella scope used by the pricing rules, not a product-level family.
- Bulk upserts on this Windows host require `--line-ending LF` because the CSV
  files use LF. Without it, Bulk API 2.0 rejects the job with
  `LineEnding is invalid on user data`.
- `sf data upsert bulk` is the only upsert form in CLI 2.150.6.
- The repo has commits on `main`; `docs/`, `scripts/`, and other root files
  remain intentionally untracked.

---

## Deviations recorded during this step

- `Engagement_Penalty__mdt.Min_Penalty__c` is **Number(12,2)**, not Currency.
  Custom metadata types do not support Currency fields (the platform supports
  only Checkbox, Date, DateTime, LongTextArea, Number, Picklist and Text). The
  org is single-currency, so the numeric floor is unambiguous.
- `Engagement_Penalty__mdt.Product_Category__c` includes an **Any** value. The
  §9.1 seed has a Business row with "any" category while the field is required;
  `Any` is the explicit wildcard. The runtime resolver must treat `Any` as a
  match for every category.
- `Is_Active__c` on both types is a checkbox with default `true`; all seed rows
  set it explicitly. The required-checkbox intent is carried by the default.
- `External_Api__mdt.Bss_Provisioning.Base_Url__c` stores the literal
  `{!NamedCredential.BSS_Api.Data.ApiEndpoint}` expression, as specified.
- `Customer_Request__c.Cancellation_Reason_Required`: Salesforce rejects
  `ISBLANK()` on a picklist field, so the rule uses `ISPICKVAL(..., "")`. The
  spec's `CHANGED()` is not a Salesforce function; the rule uses `ISCHANGED()`.
- `Customer_Request__c.Target_Subscription_Required`: the §11.2 formula is
  logically impossible (it requires `PlanChange` **and** one of
  `Cancellation`/`EquipmentSwap`/`Suspension`/`Portability`). The deployed rule
  uses an `OR` across the five target-bearing types.
- `Subscription__c.MSISDN_Format`: the regex uses `[+]?` instead of `\+?` for
  the optional plus sign. The two expressions are equivalent; the character
  class avoids backslash escaping in the formula string.
- `Engagement__c.Penalty_Rule__c` is a **Text(255)** field storing the
  `Engagement_Penalty__mdt.DeveloperName`, not a lookup. A custom object cannot
  have a lookup to a custom metadata type. The field is read-only on the
  Engagement layout and is intended to be stamped by Apex; its FLS mirrors
  `Penalty_Rate__c` across the 8 permission sets.
- `Integration_Log__c.Payload_Doc__c` is a **Text(18)** field holding the
  `ContentDocumentId`, not a lookup. A custom object cannot have a direct
  `Lookup(ContentDocument)`. The actual payload file is attached through the
  standard Files related list (`RelatedFileList`, backed by
  `ContentDocumentLink`), which is now on the Integration Log layout.

---

## Deferred / not started

- GVS repoint for 6 empty picklist fields (blocked by Salesforce; requires
  delete/recreate, not approved).
- Record types: `DATA_MODEL.md` specifies none for the 6 custom objects; none
  were created. The "four record types" in EPIC-05 refer to the Case /
  Opportunity / Quote / Order timeline, not custom-object record types.
- Persona assignments are complete except `ats_PortalUser`, which cannot be
  assigned until a portal/community user exists. The human users all share the
  System Administrator profile, so the assignments do not create true FLS
  isolation; dedicated non-admin test users are still needed for persona-level
  FLS testing.
- The seven compound indexes in `DATA_MODEL.md` §13.2 have not been submitted.
  A ready-to-file support case is in
  `docs/salesforce-support-custom-index-request.md`. Custom indexes can't be
  created by the Metadata API alone: the `CustomIndex` type only exposes
  `allowNullValues` and `booleanIndexedValue`, not the indexed fields. The
  Developer Edition org has no support-case entitlement, so submission requires
  the production org.
- `Engagement__c.Engagement_Number__c` is not deployed because `DATA_MODEL.md`
  §4.2 specifies an Auto Number while §13.1 specifies an External ID; an
  auto-number field can't also be an External ID. The engagement reference is
  the auto-number `Name` field (`ENG-{0000}`). A separate Text(30) external ID
  would be a design decision, not a prerequisite for the index request.
- The remaining two retention/reconciliation jobs in `UC-DM-14` are not yet
  implemented: `RenewalOutreachScheduler` (E6) and `BssReconciliationBatch` (E8).
- E2's server-side catalogue, pricing export, and UC-COM-01 quote creation are
  complete. `priceBulk()` is capped at 200 requests per call (the spec's
  supported batch size); the 200-request mixed test passes and a 201-request
  guard test asserts the cap. A 10,000-row single call is deliberately not
  supported because it risks heap exhaustion; callers must chunk. The UC-CAT-09
  rollback drill is complete and the export/rollback runbook is in
  `docs/revenue-core/07-PRICING-EXPORT-RUNBOOK.md`; E7 caller wiring and CI
  workflow wiring remain. The `OfferBuilderService`, E5 wizard, and
  `SubscriptionWizardController` files are deployed and committed (2026-11-12).
