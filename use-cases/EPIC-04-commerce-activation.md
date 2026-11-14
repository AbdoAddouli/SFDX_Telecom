# E4 — Commerce & Activation (Phase 4)

**Objective:** convert an accepted quote into an executable Order, the commercial container, and — atomically and idempotently — a live, provisioned service.
**Exit gate:** *Quote → Order → activate → Asset + Subscription + Engagement, atomically, and safely twice* (`ARCHITECTURE.md` §13).
**Source:** `BUSINESS_PROCESS.md` §6 (Process 04), §7 (Process 05); `ARCHITECTURE.md` §7.1–7.4, §9.

> **Process 05 is the single most critical process in the company** — it is where money starts accruing and where an error creates a customer with no service and a duplicate bill (`BUSINESS_PROCESS.md` §7).

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-COM-01 | `OfferBuilderService` — build the quote | Must | Salesforce Developer (Apex) | ✅ |
| UC-COM-02 | Contract + ContractLineItem — the commercial container | Must | Salesforce Developer | 🔴 |
| UC-COM-03 | `ActivationService` — atomic activation transaction | Must | Salesforce Developer (Apex) | ✅ |
| UC-COM-04 | Subscription state machine (trigger handler) | Must | Salesforce Developer (Apex) | ✅ |
| UC-COM-05 | Activation Flow + "Validate the Order" custom action | Must | Salesforce Admin (Flow) | ✅ |
| UC-COM-06 | Activation idempotency and bulk-safety proof | Must | Salesforce Developer + QA | ✅ |

---

### UC-COM-01 — `OfferBuilderService` — build the quote

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A3, A2 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-CAT-08, UC-DM-10 |
| Blocks | UC-COM-02, UC-COM-03, E5 |
| Business process | 03, 04 |
| Architecture ref | §7.2 #4, §8.2 |
| Data model ref | §10.7 |
| Status | ✅ Complete (2026-11-09) |

**Goal.** Turn a wizard selection into a priced, compliant `Quote` — delegating configuration and pricing to RCA, never reimplementing them.

**Preconditions** — pricing procedure active; `CatalogQueryService` available.

**Main flow**
1. Implement `OfferBuilderService.createQuote(selection)` as an invocable/flow-callable Apex service.
2. Call the RCA Configuration API + Transaction API to build `Quote` and `QuoteLineItem`s.
3. Snapshot `Commitment_Option_Code__c` and `Subscription_Key__c` on each line.
4. Link `Quote.Wizard_Session__c` back to the wizard state.
5. Validate: priced lines exist, commitment option resolved, eligibility still valid (BR-04.4).

**Alternate / exception flows**
- E1: Zero priced lines → reject with a clear error; do not create an Order.
- E2: Eligibility expired between quote and order → block (BR-04.4).

**Business rules**

| Rule | Source |
|---|---|
| Quote line snapshots the commitment option | BR-03.6 |
| Quote with zero priced lines cannot produce an Order | BR-04.4 |
| Price always server-computed | X2 |

**Acceptance criteria**
- [x] `createQuote` returns a Quote with correctly priced lines.
- [x] `Commitment_Option_Code__c` snapshotted and immutable thereafter.
- [x] No price arithmetic in the service beyond RCA's returned values.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Plan + device + COMMIT12 | `createQuote` | Priced quote, 30% device discount present |
| TS-2 | Catalogue price changes after quote | Re-render | Quote price unchanged |

**Definition of done**
- [x] ≥80% coverage; wired into the wizard (E5). `OfferBuilderServiceTest`
  passes 26/26 and the E5 wizard uses the service.

**Open questions / risks** — `R4` API signatures.

---

### UC-COM-02 — Contract + ContractLineItem — the commercial container

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A3, A8 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-COM-01 |
| Blocks | UC-COM-03, E6 |
| Business process | 04, 06, 08 |
| Architecture ref | §5.2 |
| Data model ref | §10.10 |
| Status | 🔴 Blocked — Q1/BQ1 (plan-change semantics) |

**Goal.** Hold the 12/24-month term of record, grouping plan and device under one commitment and carrying adjustments.

**Preconditions** — Q1 default (amend) confirmed or accepted.

**Main flow**
1. Create/amend `Contract` with `ATS_Contract_Type__c` (`Mobile/Fiber/Bundle`), `Signed_On__c`, `Auto_Renew__c`.
2. Create one `ContractLineItem` per quoted line, linked to the `Engagement__c`.
3. Start date = today on activation; set the renewal date.
4. Ensure the contract determines which subscriptions terminate together on cancellation (BR-04.5).

**Alternate / exception flows**
- E1: Q1 = "new contract" → close old contract, open new one, restart the penalty clock. Card must not be built on the wrong branch.

**Business rules**

| Rule | Source |
|---|---|
| The Contract is the term of record | BR-04.1 |
| Contract type determines co-terminating subscriptions | BR-04.5 |
| Default is **amend** until Q1 confirms | BR-04.2, `R3` |

**Acceptance criteria**
- [ ] Contract carries term + renewal date + adjustments.
- [ ] `ContractLineItem` ↔ `Engagement__c` link present.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Bundle quote activated | Inspect contract | One Bundle contract, two line items |

**Definition of done**
- [ ] Deployed; Q1 branch recorded on the card.

**Open questions / risks** — Q1 is the highest-impact unresolved item.

---

### UC-COM-03 — `ActivationService` — atomic activation transaction

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A3, A9 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-COM-01, UC-COM-02, UC-DM-08 |
| Blocks | E6, E8 |
| Business process | 05 |
| Architecture ref | §7.3 |
| Data model ref | §3, §4, §10.8, §10.9 |
| Status | ✅ Complete (2026-11-12) |

**Goal.** Atomically turn a commercial Order into a live service: provisioned `Asset`, active `Subscription__c`, in-force `Engagement__c`, and a confirmed BSS record — all or nothing.

**Preconditions** — Order in `Ready`; BSS feature flag on.

**Main flow** (from `ARCHITECTURE.md` §7.3)
1. **Validate** — Order is activatable, OrderItems exist, not already activated (idempotent exit if so).
2. **Per OrderItem (bulk, 200 at a time):**
   a. Upsert `Asset` keyed on `OrderItemId` (idempotent).
   b. Create `Subscription__c` (`Status = Active`, `Activation_Date__c = today`, `Service_Line_Type__c` from product).
   c. Create `Engagement__c` **only** if commitment option ≠ `NOCOMMIT`; snapshot `Monthly_Amount__c` + `Penalty_Rate__c`; duration 12/24.
   d. Set `Root_Engagement__c` so device lines inherit the plan's engagement.
   e. Bind `Asset ↔ Contract` (`AssetContractRelationship`).
3. `Order.Activation_State__c = Activated`.
4. Contract activated (start = today).
5. **BSS callout** with idempotency key = `Subscription_Number__c`; on failure **full rollback**, Order returns to `Ready`.
6. Persist BSS identifiers (`External_Reference__c`, MSISDN).
7. Publish platform event **after commit** (E8).
8. Schedule confirmation notification.
9. Log every step to `Integration_Log__c` with a shared `Correlation_Id__c`.

**Alternate / exception flows**
- E1: BSS returns 500 → full rollback; nothing partially created; customer not told they have service.
- E2: Order already activated → no-op.
- E3: No OrderItems → surface error, not silent success.
- E4: `NOCOMMIT` → no `Engagement__c` created, therefore no penalty ever.

**Business rules**

| Rule | Source |
|---|---|
| All or nothing (`allOrNone`, rollback on callout failure) | BR-05.1 |
| Double-click safe | BR-05.2 |
| No engagement, no commitment | BR-05.4 |
| Snapshots at inception, never recomputed | BR-05.5 |
| Service live only when BSS confirms | BR-05.6 |
| Traceable via `Correlation_Id__c` | BR-05.7 |

**Acceptance criteria**
- [x] A single successful run produces Asset + Subscription + Engagement + bound contract.
- [x] A failing BSS call leaves **zero** partial records and Order back in `Ready`.
- [x] Two calls produce exactly one subscription.
- [x] 200 OrderItems activate within governor limits.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Valid Ready order | Activate | All records created |
| TS-2 | Same order | Activate twice | One subscription |
| TS-3 | Failing endpoint (mock) | Activate | Full rollback, Order Ready |
| TS-4 | 200 OrderItems | Activate | No limit breach |
| TS-5 | Order with no OrderItems | Activate | Error surfaced |
| TS-6 | NOCOMMIT order | Activate | No Engagement created |

**Definition of done**
- [x] ≥80% coverage; all six scenarios evidenced. `ActivationServiceTest`
  passes 26/26, including BSS rollback, retry idempotency, no-item, and
  commitment cases.

**Implementation note.** The activation path inserts
`Subscription__c = PendingActivation`, then moves to `Active` only after BSS
success. Contract binding reuses `Order.ContractId` when present; otherwise it
creates a minimal `Contract`. `ContractLineItem` is not written because standard
`ContractLineItem` belongs to `ServiceContract` (Q1/BQ1 remains open). The
synchronous cap is 10 orders per call; `ActivationBatchJob` supplies 10-order
chunking for larger BSS batches (UC-COM-06). The service is split into focused
collaborators: `ActivationService` owns the transaction, `ActivationReader`
loads and builds context, `ActivationProvisioner` writes local service records,
`ActivationBssClient` owns the BSS boundary, `ActivationWriter` handles the Order
lifecycle and audit, and `ActivationContext` holds pure rules. Query and DML
order is unchanged, so the 10-order governor-limit profile is preserved.

**Open questions / risks** — `R8`/`R9` are addressed by the 10-order cap and
chunking; `R10` (ContractLineItem) remains blocked on Q1/BQ1.

---

### UC-COM-04 — Subscription state machine (trigger handler)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-DM-02 |
| Blocks | E6, E7, E8 |
| Business process | 05, 06, 07, 08 |
| Architecture ref | §7.4 |
| Data model ref | §3.3, §5.6 |
| Status | ✅ Complete (2026-11-12) |

**Goal.** Enforce the allowed `Status__c` transitions from **every** DML path — API, data load, Flow, integration — not just the UI.

**Preconditions** — `Subscription__c` deployed; global value set in place.

**Main flow**
1. Implement `SubscriptionTriggerHandler` with an explicit allowed-transition map:
   ```
   Draft → PendingActivation → Active ⇄ Suspended
                              ├──→ PendingCancellation → Cancelled (terminal)
                              └──→ Superseded          (terminal)
   ```
2. Reject illegal transitions with a clear error (including data loads and integrations).
3. Ensure no hard delete — soft-close only (X7).
4. Ensure no other automation writes `Status__c`.

**Alternate / exception flows**
- E1: A Flow or integration attempts `Cancelled → Active` → blocked.

**Business rules**

| Rule | Source |
|---|---|
| Status transitions obey the state machine from every DML path | X8, §7.4 |
| `Cancelled`/`Superseded` are terminal | §3.3 |
| Never hard-delete | X7 |

**Acceptance criteria**
- [x] Illegal transitions blocked regardless of entry path.
- [x] Terminal states cannot be reopened.
- [x] One handler per object is the sole writer of `Status__c`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active subscription | Set `Cancelled` directly | Blocked or routed via request |
| TS-2 | Cancelled subscription | Set `Active` | Blocked |

**Definition of done**
- [x] Deployed; every transition from §7.4 tested. `SubscriptionTriggerHandlerTest`
  passes 11/11 and targeted state-machine coverage is 18/18.

**Open questions / risks** — `R11` (derived vs stored commitment state).

---

### UC-COM-05 — Activation Flow + "Validate the Order" custom action

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A3, A4 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-COM-03, UC-COM-04 |
| Blocks | E5, E6 |
| Business process | 05, 06 |
| Architecture ref | §7.2 #5–6 |
| Data model ref | §10.8 |
| Status | ✅ Complete (2026-11-13) |

**Goal.** Provide the entry point and error surface for activation while Apex guarantees atomicity.

**Preconditions** — `ActivationService` deployed.

**Main flow**
1. Build the **"Validate the Order"** custom action → `ActivationService` invocable.
2. Surface failures to the user without exposing stack traces (`Order.Failure_Reason__c`).
3. Gate on `ATS_Feature_Flags__c.BSS_Provisioning_Enabled__c` and `Wizard_Enabled__c`.
4. Ensure the Flow orchestrates and Apex executes — never the reverse.

**Alternate / exception flows**
- E1: BSS feature flag off → activation held in `Ready`, surfaced to ops, customers told honestly (BR-05.8) — never silently skipped.

**Business rules**

| Rule | Source |
|---|---|
| Flow provides entry point + error surface; Apex guarantees atomicity | §7.2 #5 |
| If BSS flag is off, hold in `Ready` and surface — never skip silently | BR-05.8 |
| Flows invoke Apex; never the reverse | §7.1 |

**Acceptance criteria**
- [x] Custom action triggers activation and shows a friendly error on failure.
- [x] Flag off → held in `Ready` with an ops-visible signal.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Ready order | Click action | Activates |
| TS-2 | BSS flag false | Click action | Held in Ready, ops notified |

**Definition of done**
- [x] Flow tested; no stack trace exposed to users.

**Implementation note.** `Order_Activation_Validate` is a screen Flow invoked by
the `Order.Validate_the_Order` Flow quick action. The action is exposed through
the Order layout `platformActionList` because Salesforce rejects Flow quick
actions in `quickActionList`. The Flow gates both feature flags and delegates all
writes to `ActivationService`; the BSS-off path still calls Apex so the Order
stays `Ready` with an ops-visible `Failure_Reason__c`.

**Open questions / risks** — none.

---

### UC-COM-06 — Activation idempotency and bulk-safety proof

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 4 |
| Actor(s) | A6, QA |
| Suggested owner | Salesforce Developer + QA |
| Depends on | UC-COM-03, UC-COM-05 |
| Blocks | E9 exit gate |
| Business process | 05 |
| Architecture ref | §7.3, §12 |
| Data model ref | §10.8 |
| Status | ✅ Complete (2026-11-14) |

**Goal.** Prove the two failure modes that cause double billing and production-only limit breaches.

**Preconditions** — activation live in `ats-int`.

**Main flow**
1. Test double activation (two rapid calls) → exactly one subscription and one BSS provisioning.
2. Test a 200-order batch within limits (100 SOQL / 150 DML / 10,000 CPU ms).
3. Test a 500-order batch across chunks; prove fan-out, error isolation, and shared correlation.
4. Assert `Integration_Log__c` entries share a `Correlation_Id__c`.

**Alternate / exception flows**
- E1: Duplicate detected post-hoc → reconciliation batch reports drift (E8).

**Business rules**

| Rule | Source |
|---|---|
| Double-click safe | BR-05.2, R8 |
| Bulk safe | BR-05.3, R9 |
| Idempotent callout (idempotency key) | §7.3 |

**Acceptance criteria**
- [x] Two calls → one subscription.
- [x] 200-order batch passes; 500-order batch executes across 50 chunks and rejects 501.
- [x] Correlation ID present across all log lines.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Ready order | Duplicate IDs in one invocable call | One subscription, one BSS request |
| TS-2 | 10 Ready orders | Activate synchronously | Under 100 SOQL / 150 DML / 10,000 ms |
| TS-3 | 200 Ready orders | `ActivationBatchJob.enqueue` | 20 chunks, 200 activated, shared correlation |
| TS-4 | 500 Ready orders | `ActivationBatchJob.enqueue` | 50 chunks, 500 isolated failures, 50 summaries, shared correlation |
| TS-5 | 500 order IDs | `planChunks` | Exactly 50 chunks of 10 |
| TS-6 | 501 order IDs | `enqueue` | Friendly batch-size rejection |

**Definition of done**
- [x] Bulk + idempotency tests in the Apex suite (repo has no CI pipeline yet); `R8`/`R9` closed.

**Implementation note.** `ActivationService.activate` now caps a synchronous
call at 10 orders. Each order owns a savepoint and roughly seven SOQL/DML
statements, so the old 80-order ceiling was not safe: a 20-order probe hit
`Too many DML statements: 151`. `ActivationBatchJob` fans a 200/500-order
request out into independent queueable jobs of 10 orders, keeps every
transaction within the synchronous limits, and shares one correlation ID across
every order log and chunk summary. The unique `Order.BSS_Order_Key__c` is derived
from the shared correlation plus `OrderNumber` so batch orders do not collide.
The 200-order test activates 200 subscriptions/assets/contracts across 20 chunks.
The 500-order test executes 50 chunks, leaves 500 orders `Ready` with failure
reasons, writes 500 isolated failure logs and 50 summaries, and shares one
correlation ID. The 501-order test covers the ceiling. The activation service is
also split into focused collaborators: `ActivationService` owns the transaction,
`ActivationReader` loads and builds context, `ActivationProvisioner` writes local
service records, `ActivationBssClient` owns the BSS boundary, `ActivationWriter`
handles the Order lifecycle and audit, and `ActivationContext` holds pure rules.
The query and DML order is unchanged, so the 10-order budget is preserved. See
`ActivationServiceTest` cases `tenOrdersInOneCallStayWithinLimits`,
`doubleClickInOneCallIsIdempotent`,
`batchActivatesTwoHundredOrdersWithSharedCorrelation`,
`batchExecutesFiveHundredOrdersAcrossFiftyChunks`,
`batchPlansFiveHundredOrdersAcrossFiftyChunks`, and
`batchRejectsMoreThanFiveHundredOrders`.

**Open questions / risks** — `R9` production-only limit failure is closed by the
10-order cap and the executed 50-chunk test. The 200- and 500-order execution
tests add roughly 4.5 minutes to the local suite; they are kept because they
prove both fan-out and the 50-job queueable limit. The planner test remains as a
cheap chunk-math guard.
