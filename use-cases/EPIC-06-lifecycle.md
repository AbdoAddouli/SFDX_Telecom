# E6 — Lifecycle (Phase 6)

**Objective:** implement in-life service management — plan change, suspension, equipment swap, portability, cancellation, and renewal — all through the shared request intake with one penalty engine.
**Exit gate:** *Both paths produce correct fees* (`ARCHITECTURE.md` §13).
**Source:** `BUSINESS_PROCESS.md` §8 (Process 06), §9 (Process 07), §10 (Process 08), §11 (Process 09); `ARCHITECTURE.md` §7.2, §7.4; `DATA_MODEL.md` §4, §5, §9.1.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-LIF-01 | `EngagementPenaltyService` + penalty-matrix resolution | Must | Salesforce Developer (Apex) | ✅ |
| UC-LIF-02 | Plan change Flow (amend path) | Must | Salesforce Developer + Admin | ✅ |
| UC-LIF-03 | Cancellation Flow (intake → fee → approval → fulfilment) | Must | Salesforce Developer + Admin | ✅ |
| UC-LIF-04 | Suspension / unfreeze | Must | Salesforce Admin (Flow) | ✅ |
| UC-LIF-05 | Equipment swap | Should | Salesforce Admin (Flow) | ✅ Deployed 2026-11-20 |
| UC-LIF-06 | Renewal management (T−60/30/7) | Must | Salesforce Admin (Flow) | ✅ |
| UC-LIF-07 | Number portability (inbound/outbound) | Should | Salesforce Developer | ✅ |
| UC-LIF-08 | Shared request intake, Case traceability, approval gate | Must | Salesforce Admin (Flow) | ✅ |

---

### UC-LIF-01 — `EngagementPenaltyService` + penalty-matrix resolution

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A4, A8 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-DM-03, UC-DM-08 |
| Blocks | UC-LIF-03, UC-LIF-02 |
| Business process | 08 |
| Architecture ref | §7.2 #8 |
| Data model ref | §4.5, §9.1 |
| Status | Complete - BQ11 = 14 days, BQ9 = same threshold |

**Goal.** Compute early-termination fees server-side and reproducibly, from inception snapshots and a configurable matrix.

**Preconditions** — `Engagement_Penalty__mdt` seeded and signed off by Finance.

**Main flow**
1. Resolve the `Engagement_Penalty__mdt` row by (segment, category, duration, activity date); **lowest `Priority__c` wins**.
2. If within the penalty-free window (`Penalty_Applicable_After_Months__c`) → fee = 0.
3. Else `fee = MIN(Months_Remaining × Monthly_Amount × Penalty_Rate, Max_Penalty_Cap × contract value)`.
4. Stamp `Penalty_Rule__c`, `Penalty_Calculated_On__c`; write plain-language `Penalty_Breakdown__c`.
5. Write `Calculated_Fee__c` (server-computed only).
6. If the engagement has already **expired** → fee 0 and `Status = Expired` (not `Breached`).
7. If no metadata row matches → apply a **default rule**, never throw (E9).

**Alternate / exception flows**
- E1: Missing metadata row → default rule applied, no exception surfaced to the customer.
- E2: Cancelling month 1 of a 12-month contract (window 1) → fee 0.
- E3: Fee disputed → `Penalty_Breakdown__c` + snapshots make the figure reproducible (E10).

**Business rules**

| Rule | Source |
|---|---|
| Penalty amounts reproducible from inception snapshots | X4, BR-08.4 |
| Penalty-free window respected | BR-08.5 |
| Expired engagement → `Expired`, not `Breached` | BR-08.9 |
| Missing metadata → default rule, never an exception | E9 |

**Acceptance criteria**
- [ ] Fee correct and reproducible years later (invoice-time snapshot test).
- [ ] Lowest priority wins; device rate 50% applies.
- [ ] Fee = 0 within the penalty-free window.
- [ ] No rule → default, not an exception.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Consumer Mobile 24, 6 months remaining | Calculate | Matches formula |
| TS-2 | Missing metadata row | Calculate | Default applied |
| TS-3 | Expired engagement | Cancel | Fee 0, status Expired |
| TS-4 | Historical price change in year 2 | Recompute year-1 fee | Identical |

**Definition of done**
- [ ] ≥80% coverage; Finance sign-off on the numbers.

**Open questions / risks** — BQ11 (device window), BQ9 (waiver threshold).

---

### UC-LIF-02 — Plan change Flow (amend path)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A3, A4, A5 |
| Suggested owner | Salesforce Developer + Admin |
| Depends on | UC-LIF-01, UC-COM-01, UC-LIF-08 |
| Blocks | E6 exit gate |
| Business process | 06 |
| Architecture ref | §7.2 #9 |
| Data model ref | §5.2, §5.6 |
| Status | Complete - scoped amend path deployed |

**Goal.** Let a customer upgrade/downgrade mid-term while correctly repricing the contract, superseding the old instance, and preserving commitment integrity.

**Preconditions** — Q1 default (amend) confirmed; penalty-free plan-change rule agreed.

**Implemented flow**
1. **Intake** — `LifecycleRequestService` creates the `Customer_Request__c`/`Case` pair and derives `Impacted_Engagement__c` server-side.
2. **Validation** — `PlanChangeService` requires an active source line, active engagement, active target product, and fibre eligibility where applicable.
3. **Re-quote** — `CatalogQueryService.getPriceBreakdown` returns the authoritative price; the quote is stored in `Customer_Request__c.Fee_Breakdown__c` with no LWC-side calculation.
4. **Approval** — plan changes are fee-free and auto-approved; `PlanChangeApprovalService` applies a manager-approved request through `PlanChangeService.applyApproved`.
5. **Amend** — the old `Subscription__c` becomes `Superseded`; a replacement `Subscription__c` with `Parent_Subscription__c` is inserted as `Active`; the existing engagement and term are preserved. No `ContractLineItem` is created because the target org uses standard `Contract`.
6. **Close-out** — the linked Case is closed and the request is `Completed`.

**Not in scope** — `Quote` creation, `ContractLineItem` rate updates, and the new-contract (Q1 alternative) branch remain future work.

**Alternate / exception flows**
- A1: Q1 = new contract → close old, open new, restart the penalty clock (opposite branch).
- E1: Engagement not `Active` or past `End_Date__c` → request non-compliant (`Is_Compliant_Request__c`).
- E2: Device-only line → cannot change independently; the root engagement governs penalty once (`Root_Engagement__c`).

**Business rules**

| Rule | Source |
|---|---|
| Engagement does not restart on upgrade by default | BR-06.1 |
| Old line superseded, never deleted | BR-06.2 |
| Target subscription mandatory | BR-06.3 |
| Root engagement governs penalty once, not twice | BR-06.4 |
| Every plan change carries a Case | BR-06.7 |

**Acceptance criteria**
- [x] Upgrade supersedes the old line and keeps the same term.
- [x] New price is server-computed; request fee display-only.
- [x] Plan-change requests are fee-free and apply only after approval.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active 24-month line | Upgrade plan | Rate changes, term unchanged, old line `Superseded` (verified) |
| TS-2 | Fee above threshold | Submit | Not applicable: plan changes are fee-free |
| TS-3 | Expired engagement | Submit | `Rejected` with reason; no line superseded (verified) |
| TS-4 | Approved request | Apply twice | First application completes; second is idempotent (verified) |

**Definition of done**
- [x] Scoped amend path verified; Q1 decision recorded.

**Open questions / risks** — `R3` wrong Q1 choice forces historical repricing.

---

### UC-LIF-03 — Cancellation Flow (intake → fee → approval → fulfilment)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A2, A3, A4, A5 |
| Suggested owner | Salesforce Developer + Admin |
| Depends on | UC-LIF-01, UC-LIF-08, UC-COM-04 |
| Blocks | E6 exit gate, E7 |
| Business process | 08 |
| Architecture ref | §7.2 #10 |
| Data model ref | §5, §11.2 |
| Status | ✅ Complete — BQ2 = 30-day notice; BQ12 = churn only when the last active line cancels |

**Goal.** Terminate a service legally compliant (notice period), financially correct (penalty), fully traceable (case + reason), and operationally clean (network released, no orphans).

**Preconditions** — notice period confirmed; penalty matrix signed off.

**Main flow**
1. **Intake** — always a `Customer_Request__c` + `Case`, never a direct status edit; capture `Channel__c`, **mandatory** `Cancellation_Reason__c`, `Cancellation_Effective_Date__c` ≥ today + 30, customer comment.
2. **Fee calculation** — `EngagementPenaltyService` (server-side); snapshots + breakdown written.
3. **Approval gate:**
   - fee = 0 → auto-proceed;
   - fee ≤ threshold → advisor may proceed;
   - fee > threshold → `Awaiting_Approval` → Advisor Manager;
   - `Goodwill_Waiver__c` → manager approval + mandatory `Goodwill_Justification__c`.
4. **Decision** — Approved → fulfilment; Rejected → mandatory `Rejection_Reason__c`, customer informed.
5. **Fulfilment** (effective on the effective date):
   - today → effective date: `Subscription__c = PendingCancellation` (service continues);
   - on effective date (scheduled job): subscription `Cancelled` (terminal), asset `Retired`, contract `Terminated`, engagement `Breached` with `Early_Termination_Fee__c`/`Breach_Amount__c`, `Account.Customer_Status__c = Churned` if no other lines;
   - BSS de-provision callout (rollback on failure);
   - audit outcome written after commit (`Integration_Log__c`); a platform event can be added when an event object exists in the data model.
6. Close — `Resolution_Summary__c`, `Completed_On__c`, close Case; reason feeds churn analytics.

**Alternate / exception flows**
- E1: Reason blank → validation rule blocks (non-bypassable).
- E2: Effective date < today+30 → blocked.
- E3: Goodwill waiver without justification → blocked.
- E4: BSS de-provision fails → rollback; never a one-way Salesforce-only cancel (E7/BR-08.11).
- E5: Duplicate in-flight cancellation for same line → suppressed (`Is_Compliant_Request__c`).

**Business rules**

| Rule | Source |
|---|---|
| Reason always mandatory | BR-08.1 |
| 30-day notice | BR-08.2 |
| No direct cancel from 360 view | BR-08.3 |
| Waiver requires justification | BR-08.6 |
| `PendingCancellation` while waiting; service continues | BR-08.8 |
| Duplicate in-flight requests blocked | BR-08.10 |
| BSS failure rolls back | BR-08.11 |

**Acceptance criteria**
- [x] Cancellation cannot be created without a reason, a Case, and a compliant effective date.
- [x] Correct fee; `PendingCancellation` until the effective date.
- [x] On the effective date Subscription, Asset, Contract, Engagement, Case, and request transition correctly.
- [x] Failed de-provision leaves no cancelled-with-live-network state.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active committed line | Submit cancellation | Reason mandatory; fee computed |
| TS-2 | Fee above threshold | Submit | Awaiting approval |
| TS-3 | Effective date reached | Scheduled job | Subscription Cancelled, Asset Retired, Contract Terminated, Engagement Breached, request Completed |
| TS-4 | BSS de-provision 500 | Fulfil | Rollback, retry logged |
| TS-5 | Second in-flight cancellation | Submit | Blocked |

**Definition of done**
- [x] E6 exit gate; both paths produce correct fees; BQ2/BQ12 resolved.

**Implementation note (2026-11-18)** — `CancellationFulfilmentBatch` selects due requests and is scheduled daily as `ATS Cancellation Fulfilment (Daily)`; `CancellationFulfilmentService` calls the simulated BSS de-provision gateway before a single savepoint-guarded bulk write. `CancellationFulfilmentServiceTest` passes 7/7 (`707bm00001XKzVb`) and the full suite passes 193/193 (`707bm00001XLQDr`). Audit outcomes are recorded in `Integration_Log__c`; no platform event object exists yet.

**Open questions / risks** — `R10` only; BQ2 and BQ12 are resolved.

---

### UC-LIF-04 — Suspension / unfreeze

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-COM-04, UC-LIF-08 |
| Blocks | — |
| Business process | 07 |
| Architecture ref | §7.2 #10 (hybrid) |
| Data model ref | §3.3 |
| Status | 🟢 Deployed — BQ3 resolved 2026-11-19: suspension does NOT pause the commitment clock |

**Goal.** Freeze and unfreeze a line via a reversible transition without touching the commercial term.

**Preconditions** — BQ3 resolved: the commitment clock does not pause; Contract and Engagement are untouched.

**Main flow**
1. Request (`Suspension`) + Case; `Subscription__c` required.
2. `Active → Suspended` (reversible) via the state machine.
3. `Contract` **unchanged**; `Engagement__c` **unchanged** (BQ3: the clock keeps running).
4. BSS suspend callout; failure rolls back the status change.
5. Exit: `Suspended → Active` via a reverse request.

**Alternate / exception flows**
- E1: BSS suspend fails → status rolls back to `Active`.
- E2: Billing while suspended → out of scope pending Q2/Q3.

**Business rules**

| Rule | Source |
|---|---|
| `Active ⇄ Suspended` is reversible | §3.3 |
| Contract unchanged; term continues to run | §9.2 |
| BSS failure rolls back the status change | §9.2 |

**Acceptance criteria**
- [x] Freeze and unfreeze both work through requests.
- [x] Contract and engagement untouched by a freeze.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active line | Suspend | Status Suspended, contract unchanged |
| TS-2 | Suspended line | Unfreeze | Status Active |
| TS-3 | BSS suspend 500 | Suspend | Rollback to Active |

**Definition of done**
- [x] Deployed; BQ3 recorded.

**Implementation note (2026-11-19)** — `SuspensionService` is the invocable façade; `SuspensionIntake` creates the request/Case through `LifecycleRequestService` and applies approved state changes through `SuspensionFulfilment`, the `BssSuspensionGateway` boundary, and a single savepoint-guarded bulk write. `SuspensionApprovalService` exposes the manager-approval entry point. `SuspensionServiceTest` passes 7/7 (`707bm00001Xcf5U`) and the full suite now passes 209/209 (`707bm00001Xek74`).

**Open questions / risks** — none; BQ3 resolved as no clock pause.

---

### UC-LIF-05 — Equipment swap

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 6 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-LIF-08, UC-DM-10 |
| Blocks | — |
| Business process | 07 |
| Architecture ref | §7.2 #10 |
| Data model ref | §10.9 |
| Status | ✅ Complete — deployed 2026-11-20; BQ5/Q7 fee-free default recorded |

**Goal.** Replace a customer's device while preserving the service instance and commitment.

**Preconditions** — `Asset` extensions deployed.

**Main flow**
1. Request (`EquipmentSwap`) + Case; `Subscription__c` required.
2. Old `Asset → Retired`; new `Asset` created with parent relationship preserved.
3. `Subscription__c` **unchanged** — the service instance survives.
4. `Engagement__c` **unchanged** unless the device tier changes.
5. BSS IMEI swap callout; new asset records serial, colour, image; lineage via `OrderItem`.

**Alternate / exception flows**
- E1: Swap changes commitment tier → engagement handling per BQ (may create a new engagement).
- E2: Restocking fee on return → BQ5/Q7 (may need a second fee line).

**Business rules**

| Rule | Source |
|---|---|
| Subscription survives a swap | §9.3 |
| Old asset retired, new asset created, parent preserved | §9.3 |
| Engagement unchanged unless the device tier changes | §9.3 |

**Acceptance criteria**
- [x] Swap retires the old asset and creates the new one behind the same subscription.
- [x] No change to subscription status or contract.
- [x] New lineage is stored on `Asset.Order_Item__c`; old asset is `Retired`/`Superseded`, new asset `Installed`/`Active`.
- [x] BSS failure rolls back asset writes but keeps the `Approved` request for retry.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active line + device | Swap device | Old Retired, new created, subscription unchanged |
| TS-2 | Goodwill waiver requested | Submit swap | Status `Awaiting_Approval`, no BSS call, no replacement asset |
| TS-3 | BSS gateway throws | Submit approved swap | Writes rolled back, request stays `Approved`, retry succeeds |
| TS-4 | Two swaps in one payload | Bulk submit | Both applied independently |
| TS-5 | Non-device product or in-flight request | Submit swap | Rejected before intake |

**Definition of done**
- [x] Deployed; BQ5/Q7 noted.
- [x] Dedicated intake/approval Flows, 17 Apex classes, 9 fields, FLS in 8 permission sets.
- [x] `EquipmentSwapServiceTest` 8/8 (`707bm00001Y0HAM`); deploy `0Afbm00000p4XG9CAM` 37/37; full local suite 224/224 (`707bm00001Y0An9`).

**Open questions / risks** — BQ5/Q7 restocking fee remains commercially open; the implemented default is fee-free with the open policy noted in `Fee_Breakdown__c`. A real BSS callout still needs the `BSS_Api` Named Credential (E8).

---

### UC-LIF-06 — Renewal management (T−60/30/7)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-DM-14, UC-LIF-02, UC-LIF-03 |
| Blocks | KPI: renewal coverage 100% |
| Business process | 09 |
| Architecture ref | §7.2 #12 |
| Data model ref | §4.2, §13.2 |
| Status | ✅ Complete — deployed 2026-11-19; BQ4 implemented as monthly rollover |

**Goal.** Turn the natural end of a commitment into a deliberate commercial event — renew, re-price, or let lapse — before the customer drifts away uncontacted.

**Preconditions** — BQ4 resolved (expiry behaviour).

**Main flow**
1. Daily scheduled job scans `Subscription__c.Next_Renewal_Date__c` (formula over `Billing_End_Date__c`) using the compound index and `Database.QueryLocator`.
2. T−60 → outreach task #1, once per engagement (stage-prefix idempotency).
3. T−30 → outreach #2 + renewal offer prepared, priced server-side.
4. T−7 → final outreach + high-priority task to the record owner.
5. Customer decision:
   - renew same terms → old engagement `Expired`, new active engagement with the quoted amount;
   - renew new plan → same as above using the selected product and server-side catalogue pricing;
   - do nothing → old engagement `Expired` and subscription billing end rolled forward one month (BQ4);
   - cancel early → rejected with an instruction to use `CancellationService` (Process 08).
6. First outreach stamps `Renewal_Contacted__c = TRUE` + `Renewal_Contacted_On__c`; per-stage Task subjects prevent duplicate outreach.

**Alternate / exception flows**
- E1: Daily job re-runs → stage-prefix Task guard and `Renewal_Contacted__c` prevent duplicate outreach (BR-09.1, E13).
- E2: DNC customer → no phone outreach (BR-09.2).

**Business rules**

| Rule | Source |
|---|---|
| No duplicate outreach | BR-09.1 |
| DNC suppresses phone contact | BR-09.2 |
| `Months_Remaining__c` / `Is_Committed__c` are formulas | BR-09.3, X5 |
| Expired engagement terminal; renewal creates a **new** engagement | BR-09.4 |
| Renewal uses the same server-side pricing path | BR-09.5 |

**Acceptance criteria**
- [x] Outreach at T−60/30/7, once each per engagement.
- [x] Renewal pricing identical to new-sale pricing for the same input.
- [x] Coverage KPI measurable through daily Task creation and `Renewal_Contacted__c` stamping.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Engagement at T−60 | Run job | One task created |
| TS-2 | Same engagement next day | Run job | No duplicate task |
| TS-3 | DNC customer at T−30 | Run job | Email-only task, no phone task |
| TS-4 | Active subscription at T−30 | `RenewSameTerms` | Old engagement `Expired`; new active engagement; server quote stored on request |
| TS-5 | New target product | `RenewNewPlan` | Catalogue price applied; subscription product switched |
| TS-6 | Active subscription at T−7 | `LetLapse` | Old engagement `Expired`; billing end rolls one month |
| TS-7 | Any active subscription | `CancelEarly` | Rejected before intake; no request created |

**Implementation note (2026-11-19)** — `RenewalOutreachBatch` is scheduled as `ATS Renewal Outreach (Daily)` at 03:00 and delegates to `RenewalOutreachService`. It uses stage-prefixed Task subjects because only one `Renewal_Contacted__c` checkbox exists. `RenewalService` is the invocable façade; `RenewalValidator` calls `CatalogQueryService` for pricing and fibre eligibility. `RenewalFulfilment` wraps all writes in one savepoint, and `RenewalWriter` expires the old engagement and inserts a new one for renewals. `RenewalServiceTest` 5/5 and `RenewalOutreachServiceTest` 4/4 pass (`707bm00001XdDLU`); full suite 209/209 (`707bm00001Xek74`).

**Definition of done**
- [x] Deployed; BQ4 implemented; coverage KPI measurable.

**Open questions / risks** — None for renewal; BQ4 is resolved and implemented.

---

### UC-LIF-07 — Number portability (inbound/outbound)

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 6 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-LIF-08, UC-DM-13 |
| Blocks | — |
| Business process | 07 |
| Architecture ref | §7.2 #10 |
| Data model ref | §3.2, §13.1 |
| Status | ✅ Complete — deployed 2026-11-19; Q6 resolved org-wide |

**Goal.** Transfer a number in or out with **two-phase** discipline — never optimistically overwriting the number.

**Preconditions** — Q6 resolved 2026-11-06: `MSISDN__c` is org-wide unique.

**Main flow**
1. Request (`Portability`) + Case; `Subscription__c` required.
2. Phase 1 — request the port; wait for donor-network confirmation.
3. Phase 2 — on confirmation, update `Subscription__c.MSISDN__c`.
4. Enforce uniqueness (duplicate rule + trigger) with idempotency key = subscription number.

**Alternate / exception flows**
- E1: Donor rejects → MSISDN unchanged; request rejected with reason.
- E2: Duplicate MSISDN → duplicate rule/trigger blocks.

**Business rules**

| Rule | Source |
|---|---|
| Two-phase: request → confirm → apply | §9.4 |
| Never optimistically overwrite the number | §9.4 |
| `MSISDN__c` unique when populated | §9.4, §13.1 |

**Implementation.** `PortabilityService` is the invocable façade used by the
`Portability_Request` Flow; `PortabilityConfirmationService` is the second
invocable wrapper required by the dedicated `Portability_Confirmation` Flow.
`PortabilityValidator`, `PortabilityRepository`, `PortabilityIntake`,
`PortabilityBssClient`, `PortabilityWriter`, `PortabilityConfirmation`, and
`PortabilityLogger` keep validation, bulk reads, intake, BSS calls, writes, and
logging separate. Intake uses `LifecycleRequestService` to create the shared
request/Case pair and stamps the port fields only after BSS accepts the request.
Confirmation is a separate invocation that applies the donor outcome; simulated
BSS access uses `SimulatedBssPortabilityGateway` until E8.

**Acceptance criteria**

- [x] Number updated only after confirmation.
- [x] Duplicate MSISDN impossible within the agreed scope.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Port requested | Before confirmation | MSISDN unchanged |
| TS-2 | Confirmation received | Apply | MSISDN updated once |

| TS-3 | Donor rejects | Apply rejection | Request rejected; MSISDN unchanged |
| TS-4 | Duplicate requested MSISDN | Submit port | Rejected before intake; no request or Case |
| TS-5 | BSS apply failure | Retry confirmation | Salesforce writes roll back; retry succeeds |

**Definition of done**

- [x] Deployed; Q6 resolution recorded.

**Open questions / risks** — None on duplicate scope; Q6 is resolved (org-wide).

---

### UC-LIF-08 — Shared request intake, Case traceability, approval gate

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 6 |
| Actor(s) | A2, A3, A4, A5 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-DM-04, UC-DM-12 |
| Blocks | UC-LIF-02…07, E7 |
| Business process | 06, 07, 08, 10 |
| Architecture ref | §7.2 |
| Data model ref | §5.5, §10.11 |
| Status | Complete - deployed, 6/6 service tests passing; threshold value still pending Finance |

**Goal.** Provide one intake skeleton that every lifecycle process reuses, guaranteeing traceability and approval routing.

**Implementation.** `LifecycleRequestService.createRequests` is the single server-side intake path. The `Customer_Request_Intake` screen Flow submits to it; the service derives the Account from the subscription, resolves the impacted engagement snapshot, calls `EngagementPenaltyService`, applies `ATS_Feature_Flags__c.Cancellation_Approval_Threshold__c`, and uses a savepoint so a failed batch commits nothing. Advisor and manager permission sets grant the service class, `Customer_Request__c` CRUD, and `Case` edit.

**Preconditions** — `Customer_Request__c` + `Case` extensions deployed.

**Main flow**
1. Intake flow creates `Customer_Request__c` + `Case` (except `Info`) with `Channel__c` stamped.
2. Require `Subscription__c` for all actionable types except `NewSubscription`.
3. Populate `Impacted_Engagement__c` at intake (not at approval).
4. Approval gate shared by plan change and cancellation: fee 0 auto-approve; ≤ threshold advisor; > threshold manager; goodwill waiver mandates justification and always needs approval.
5. Write reciprocal `Case.Request_Link__c`.

**Alternate / exception flows**
- A1: `Info` request → no Case (documented exception, BR-10.7).
- E1: Duplicate in-flight request → suppressed via `Is_Compliant_Request__c`.

**Business rules**

| Rule | Source |
|---|---|
| No service state change outside a request + Case | X1 |
| Impacted engagement resolved at intake | §5.2 |
| `Info` creates no Case | BR-10.7 |
| Fees above threshold require manager approval | X10 |

**Acceptance criteria**
- [x] Every actionable request has a Case and a target subscription.
- [x] Approval routing behaves per threshold, and goodwill waiver always requires approval.
- [x] `Info` saves without a Case.
- [x] `Case.Request_Link__c` is reciprocal and no partial data is committed on error.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Any actionable request | Create | Case linked via `Request_Link__c` |
| TS-2 | Fee > threshold | Create | Awaiting approval |
| TS-3 | Info request | Create | No Case |
| TS-4 | Waiver without justification | Create | Rejected, nothing committed |
| TS-5 | Waiver with justification | Create | Engagement stamped, awaiting approval |
| TS-6 | Actionable request without subscription | Create | Rejected |

`LifecycleRequestServiceTest` passes 6/6 (run `707bm00001X2IyJ`).

**Definition of done**
- [ ] Reused by all E6 flows; BQ9 recorded and the numeric Finance threshold supplied.

**Open questions / risks** — BQ9 numeric value (`Cancellation_Approval_Threshold__c` is currently `0`).
