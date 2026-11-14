# E10 — Billing *(Conditional)* (Phase 10)

> **This epic is conditional on Q3 / BQ7**: *Do invoicing and revenue recognition live in Salesforce?* Until Finance answers, these use cases are **not started and must not be built**. `DATA_MODEL.md` §18 explicitly lists `Invoice__c` and `Payment__c` as **not to be pre-built** — do not create placeholder objects.

**Objective (if in scope):** own invoicing and revenue recognition in Revenue Cloud Billing so "subscribed customer" carries financial truth rather than being a status flag.
**Exit gate:** *Invoicing and revenue recognition reconciled* (`ARCHITECTURE.md` §13).
**Source:** `ARCHITECTURE.md` §13 (Phase 10), §3.3, `R17`; `BUSINESS_PROCESS.md` §19 BQ7; `DATA_MODEL.md` §18.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-BIL-01 | Billing scope assessment and decision record | Must (if in scope) | Finance + Solution Architect | 🔴 |
| UC-BIL-02 | Revenue Cloud Billing configuration | Must (if in scope) | Pricing Admin + Developer | 🔴 |
| UC-BIL-03 | Invoicing and revenue-recognition reconciliation | Must (if in scope) | Finance + Developer | 🔴 |

---

### UC-BIL-01 — Billing scope assessment and decision record

| Field | Value |
|---|---|
| Priority | Must (if in scope) |
| Phase | 10 |
| Actor(s) | A8 |
| Suggested owner | Finance + Solution Architect |
| Depends on | E9 |
| Blocks | UC-BIL-02, UC-BIL-03 |
| Business process | 05, 08 |
| Architecture ref | §3.3, §13 Phase 10 |
| Data model ref | §18 |
| Status | 🔴 Blocked — Q3/BQ7 |

**Goal.** Decide whether Salesforce owns billing, and record the boundary with any external billing system.

**Preconditions** — Q3/BQ7 answered by Finance.

**Main flow**
1. Confirm scope: invoicing only, revenue recognition only, both, or neither.
2. If external billing stays: define the outbound feed (this may reduce to an integration card in E8, not a billing build).
3. Record which objects are created (`Invoice__c` / `Payment__c` only if Salesforce-owned).
4. Capture the decision and financial rationale.

**Alternate / exception flows**
- E1: Q3 = external billing → **close this epic** and instead raise a data-export requirement; do not build `Invoice__c`.

**Business rules**

| Rule | Source |
|---|---|
| `Invoice__c` / `Payment__c` explicitly not modelled until Q3 | `DATA_MODEL.md` §18 |
| Billing is a separate composable adoption | `ARCHITECTURE.md` §3.2 |

**Acceptance criteria**
- [ ] A written decision exists: Salesforce-owned, external, or hybrid.
- [ ] If external, the boundary and data contract are documented.

**Test scenarios** — N/A (decision card).

**Definition of done**
- [ ] Decision recorded; epic either opened fully or closed.

**Open questions / risks** — `R17` (no billing → "subscribed" stays a flag with no financial truth).

---

### UC-BIL-02 — Revenue Cloud Billing configuration

| Field | Value |
|---|---|
| Priority | Must (if in scope) |
| Phase | 10 |
| Actor(s) | A8, A7 |
| Suggested owner | Pricing Admin + Developer |
| Depends on | UC-BIL-01, UC-COM-03 |
| Blocks | UC-BIL-03 |
| Business process | 05, 08 |
| Architecture ref | §3.3 |
| Data model ref | §18 |
| Status | 🔴 Blocked — Q3 |

**Goal.** Configure billing so activation and cancellation produce correct charges and credits from the pricing the rest of the system already uses.

**Preconditions** — UC-BIL-01 confirms Salesforce-owned billing; RCA Billing SKU available.

**Main flow**
1. Enable Revenue Cloud Billing.
2. Map activation (monthly recurring + one-time device) and cancellation (final proration + early-termination fee) to billing documents.
3. Ensure billing reuses the single pricing path — no second price implementation.
4. Handle the suspended-line billing policy once BQ/suspension billing is decided.

**Alternate / exception flows**
- E1: Billing introduces a second price source → **rejected**; reuse RCA pricing (X2).

**Business rules**

| Rule | Source |
|---|---|
| Price computed once, server-side | X2 |
| Suspended-line billing per policy (pending) | §9.2 |

**Acceptance criteria**
- [ ] An activation generates the expected recurring + one-time charges.
- [ ] A committed cancellation generates the early-termination fee as a billing line.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Committed activation | Bill | Recurring charge correct |
| TS-2 | Early cancellation | Bill | Termination fee charged |

**Definition of done**
- [ ] Billing configuration reproducible and exported like pricing.

**Open questions / risks** — Q3; BQ suspension billing.

---

### UC-BIL-03 — Invoicing and revenue-recognition reconciliation

| Field | Value |
|---|---|
| Priority | Must (if in scope) |
| Phase | 10 |
| Actor(s) | A8 |
| Suggested owner | Finance + Developer |
| Depends on | UC-BIL-02 |
| Blocks | Phase 10 exit gate |
| Business process | 05, 08 |
| Architecture ref | §13 Phase 10 |
| Data model ref | §14.1 |
| Status | 🔴 Blocked — Q3 |

**Goal.** Prove invoiced amounts reconcile to contracted and cancelled amounts, with penalties traceable to snapshots.

**Preconditions** — billing configured.

**Main flow**
1. Reconcile invoiced revenue against `Engagement__c` snapshots and `Breach_Amount__c`.
2. Confirm revenue recognition treatment matches the Finance policy.
3. Verify `Customer_Request__c` (7-year retention) and financial records support audit.
4. Publish the reconciliation to Operations/Finance on a schedule.

**Alternate / exception flows**
- E1: Discrepancy → investigate pricing snapshot drift; block release if systematic.

**Business rules**

| Rule | Source |
|---|---|
| Financial records permanent / 7-year, never hard-deleted | `DATA_MODEL.md` §14.1, X7 |
| Penalites reproducible from snapshots | X4 |

**Acceptance criteria**
- [ ] Invoiced totals reconcile to contract + penalty amounts.
- [ ] No financial record is hard-deleted.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Cancelled engagement | Reconcile | Invoice matches snapshot-derived fee |

**Definition of done**
- [ ] Finance sign-off; Phase 10 exit gate met.

**Open questions / risks** — Q3, `R17`.
