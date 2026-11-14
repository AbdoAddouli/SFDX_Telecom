# E9 — Hardening & Non-Functional (Phase 9)

**Objective:** prove the platform is safe, fast, observable, tested, and translatable before go-live; close every risk in the register that code and configuration can close.
**Exit gate:** *All exit criteria met* (`ARCHITECTURE.md` §13, §17 Definition of Done).
**Source:** `ARCHITECTURE.md` §10, §11.6, §12, §17; `BUSINESS_PROCESS.md` §14–§18; `DATA_MODEL.md` §14–§17.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-HRD-01 | Apex test suite to coverage targets | Must | QA Engineer + Developers | 🔲 |
| UC-HRD-02 | FLS / CRUD / IDOR security regression | Must | Security Engineer | 🔲 |
| UC-HRD-03 | Translation (apply agreed scope) | Should | Salesforce Admin | 🔲 |
| UC-HRD-04 | Performance and bulk hardening | Must | Salesforce Developer | 🔲 |
| UC-HRD-05 | Observability, reconciliation, and runbooks | Must | Ops Admin | 🔲 |
| UC-HRD-06 | Pricing test harness (configure-price-quote assertions) | Must | QA + Developer | 🔲 |
| UC-HRD-07 | End-to-end test suite (wizard + both portal request types) | Must | QA Engineer | 🔲 |
| UC-HRD-08 | Go-live readiness and Definition of Done validation | Must | Solution Architect | 🔲 |

---

### UC-HRD-01 — Apex test suite to coverage targets

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | QA |
| Suggested owner | QA Engineer + Developers |
| Depends on | E4, E6, E8 |
| Blocks | UC-HRD-08 |
| Business process | all |
| Architecture ref | §12 |
| Data model ref | — |
| Status | 🔲 Not started |

**Goal.** Reach ≥75% org coverage and ≥80% on domain services, with tests that prove behaviour, not lines.

**Preconditions** — domain services complete.

**Main flow**
1. Build `@TestSetup` factories using `SeeAllData=false` and `System.runAs` per persona.
2. Cover the **mandatory non-functional tests** (`ARCHITECTURE.md` §12):
   - `activate()` on an order with no OrderItems → error surfaced;
   - penalty on an engagement with `End_Date__c` in the past → zero fee;
   - portal user querying another AccountId → zero rows;
   - `EngagementPenaltyService` with a missing metadata row → default rule, no exception;
   - pricing procedure run twice after a catalogue change → identical results;
   - BSS callout returning 500 → full rollback, order `Activatable`.
3. Enforce coverage gates in CI.

**Alternate / exception flows**
- E1: Coverage met only by getters → reject; tests must assert behaviour.

**Business rules**

| Rule | Source |
|---|---|
| ≥75% org, ≥80% domain services | §12 |
| `SeeAllData=false` always | §12 |

**Acceptance criteria**
- [ ] Coverage thresholds met and enforced by CI.
- [ ] All six mandatory tests present and passing.

**Test scenarios** — the mandatory tests above *are* the scenarios.

**Definition of done**
- [ ] CI fails on coverage regression.

**Open questions / risks** — none.

---

### UC-HRD-02 — FLS / CRUD / IDOR security regression

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | Security |
| Suggested owner | Security Engineer |
| Depends on | UC-DM-12, UC-POR-05 |
| Blocks | UC-HRD-08 |
| Business process | 10 |
| Architecture ref | §10, §12 |
| Data model ref | §17 |
| Status | 🔲 Not started |

**Goal.** Prove the portal cannot leak, fees cannot be tampered with, and no persona can exceed its grant.

**Preconditions** — permission sets and portal deployed.

**Main flow**
1. Run every query/write as each restricted persona; assert field-level denial where expected.
2. IDOR test: portal user queries another account's subscriptions → zero rows.
3. Fee tampering test: client-supplied fee value is ignored.
4. Mass-assignment test: `stripInaccessible` removes unauthorised fields.
5. Verify no permission set grants delete on financial objects.

**Alternate / exception flows**
- E1: Any leak found → block release; fix and re-run.

**Business rules**

| Rule | Source |
|---|---|
| Portal identity derived server-side | X12 |
| Fee computed server-side only | §10 |
| No delete on financial records | X7 |

**Acceptance criteria**
- [ ] IDOR regression test passes in CI.
- [ ] FLS tests per persona pass.
- [ ] No delete grants exist.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | `ats_PortalUser` | Query other account | Zero rows |
| TS-2 | Client sets `Calculated_Fee__c` | Submit | Server value used |
| TS-3 | Restricted persona | Read manager fields | Denied |

**Definition of done**
- [ ] `R7` closed; security sign-off recorded.

**Open questions / risks** — `R7`.

---

### UC-HRD-03 — Translation (apply agreed scope)

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 9 |
| Actor(s) | A3, A2, A4 |
| Suggested owner | Salesforce Admin |
| Depends on | UC-FND-07, E5, E7 |
| Blocks | UC-HRD-08 |
| Business process | all |
| Architecture ref | §11.6 |
| Data model ref | §9.7 |
| Status | 🔲 Not started |

**Goal.** Apply the translation scope decided in E0 without causing standard-object layout/validation conflicts.

**Preconditions** — UC-FND-07 scope decision.

**Main flow**
1. Translate the 4 business custom objects and the wizard using the 12 custom labels.
2. Translate only the standard objects selected in E0.
3. Regression-test layouts and validation rules after translation.

**Alternate / exception flows**
- E1: Blanket standard-object translation causes conflicts → revert to the agreed scope.

**Business rules**

| Rule | Source |
|---|---|
| Standard-object translation is a deliberate decision | §11.6 |
| French org labels | `R16` |

**Acceptance criteria**
- [ ] French renders correctly in the wizard and portal.
- [ ] No layout/validation regression after translation.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | French user | Run wizard | All microcopy in French |

**Definition of done**
- [ ] Translation regression passes; `R16` closed.

**Open questions / risks** — `R16`.

---

### UC-HRD-04 — Performance and bulk hardening

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | A6, QA |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-13, E4, E6 |
| Blocks | UC-HRD-08 |
| Business process | 05, 09, 11 |
| Architecture ref | §12 |
| Data model ref | §13.3 |
| Status | 🔲 Not started |

**Goal.** Ensure the system holds at scale: the 360° query stays selective, renewal scans a high-volume object safely, and activation batches under limits.

**Preconditions** — compound indexes confirmed.

**Main flow**
1. Load representative volume; measure the 360° Subscriptions zone query plan (uses `Account__c + Status__c`).
2. Validate the renewal batch uses a `Database.QueryLocator` and the `Status__c + Next_Renewal_Date__c` index.
3. Re-run the 200-order activation batch and a 500-order chunked batch.
4. Confirm no query scales with total subscription count.

**Alternate / exception flows**
- E1: Non-selective query detected → add/confirm an index; do not ship without it.

**Business rules**

| Rule | Source |
|---|---|
| Renewal batch uses `QueryLocator` + compound index | §13.3 |
| Portal list must not scale with subscription count | §13.3 |

**Acceptance criteria**
- [ ] 360° query selective at volume.
- [ ] Batch jobs complete within limits.
- [ ] No full-table scans.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Large dataset | Open 360° | Selective query, responsive |
| TS-2 | 500 orders | Batch activate | Completes in chunks |

**Definition of done**
- [ ] `R9` closed; performance evidence recorded.

**Open questions / risks** — `R9`.

---

### UC-HRD-05 — Observability, reconciliation, and runbooks

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | A6 |
| Suggested owner | Ops Admin |
| Depends on | UC-INT-02, UC-INT-04 |
| Blocks | UC-HRD-08 |
| Business process | 05, 07, 08 |
| Architecture ref | §5.7, §11.3 |
| Data model ref | §7, §14 |
| Status | 🔲 Not started |

**Goal.** Give operations the dashboards, alerts, and runbooks to run the platform — including the pricing export/activation and dead-letter triage.

**Preconditions** — integration logging live.

**Main flow**
1. Define alerts: activation failure rate, dead-letter count, reconciliation drift, approval backlog, pricing-defect escapes.
2. Write the release runbook: pricing export → activation → decision-table refresh (`R2`, `R13`).
3. Write the incident runbook: BSS outage, feature-flag-off, retry triage (SLA-9 ≤4h).
4. Confirm retention schedulers run (13-month logs; 7-day wizard state).

**Alternate / exception flows**
- E1: Dead-letter growth → alert + triage procedure.

**Business rules**

| Rule | Source |
|---|---|
| Failed callout retry / dead-letter triage ≤ 4h | SLA-9 |
| Activation success rate ≥ 99.5% | §16.3 |

**Acceptance criteria**
- [ ] Alerts configured and tested with a simulated failure.
- [ ] Release + incident runbooks published.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Simulated 500s | Observe | Alert fires |

**Definition of done**
- [ ] Runbooks published; ops sign-off.

**Open questions / risks** — `R2`, `R13`.

---

### UC-HRD-06 — Pricing test harness (configure-price-quote assertions)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | QA, A7 |
| Suggested owner | QA + Developer |
| Depends on | UC-CAT-07, UC-CAT-09, UC-COM-01 |
| Blocks | UC-HRD-08 |
| Business process | 03, 04 |
| Architecture ref | §12 |
| Data model ref | §15 |
| Status | 🔲 Not started |

**Goal.** Exercise the pricing engine headlessly on **every deployment** and assert the numbers — the highest-value test in the project.

**Preconditions** — pricing procedure active; `OfferBuilderService` live.

**Main flow**
1. Script the full configure-price-quote sequence without a UI (RCA is API-first).
2. Assert: committed 5 GB plan with and without commitment; 30% device discount; 15% fibre-mobile; floor/guardrail.
3. Run in CI on every deployment; fail on any numeric drift.
4. Re-assert after a catalogue change **with** decision-table refresh (proves refresh discipline).

**Alternate / exception flows**
- E1: Numbers drift → release blocked; investigate decision-table activation (`R13`).

**Business rules**

| Rule | Source |
|---|---|
| Pricing defect escape target: 0 | §16.3 |
| Pricing test asserts numbers every deployment | §12 |

**Acceptance criteria**
- [ ] Scripted CPQ assertions pass in CI.
- [ ] A catalogue change with refresh keeps assertions green.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Committed 5 GB | Price | Correct net |
| TS-2 | Plan + device | Price | −30% fires |
| TS-3 | Pricebook change + refresh | Re-run | Identical results |

**Definition of done**
- [ ] Pricing test is a release gate; `R13` closed.

**Open questions / risks** — `R13`, `R2`.

---

### UC-HRD-07 — End-to-end test suite (wizard + both portal request types)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | A3, A2 |
| Suggested owner | QA Engineer |
| Depends on | E5, E7 |
| Blocks | UC-HRD-08 |
| Business process | 03, 05, 06, 08, 10 |
| Architecture ref | §12 |
| Data model ref | — |
| Status | 🔲 Not started |

**Goal.** Prove the two journeys customers and advisors actually perform, end to end, in a browser.

**Preconditions** — wizard and portal complete in `ats-int`.

**Main flow**
1. Playwright/Selenium: complete the 5-step wizard from a blank Account.
2. E2E: portal **plan change**.
3. E2E: portal **cancellation**.
4. Assert the advisor sees both in the 360° view.

**Alternate / exception flows**
- E1: Flaky step → stabilise selectors; do not quarantine silently.

**Business rules**

| Rule | Source |
|---|---|
| Both portal request types must pass E2E | §13, §17 |
| Wizard completes end-to-end from a blank Account | §17 |

**Acceptance criteria**
- [ ] Three E2E journeys pass reliably in CI.
- [ ] Advisor visibility asserted.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Blank Account | Run wizard | Activated |
| TS-2 | Customer | Portal plan change | Request completed |
| TS-3 | Customer | Portal cancellation | Request completed, visible to advisor |

**Definition of done**
- [ ] E2E green on the release candidate.

**Open questions / risks** — none.

---

### UC-HRD-08 — Go-live readiness and Definition of Done validation

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 9 |
| Actor(s) | A6, A8 |
| Suggested owner | Solution Architect |
| Depends on | UC-HRD-01…07 |
| Blocks | Go-live |
| Business process | all |
| Architecture ref | §17 |
| Data model ref | §21 |
| Status | 🔲 Not started |

**Goal.** Walk the Definition of Done and the two build checklists item by item and record evidence.

**Preconditions** — all hardening cards done.

**Main flow**
1. Validate each `ARCHITECTURE.md` §17 item (metadata deploys cleanly; coverage; wizard E2E; portal E2E; 200-order batch; failing BSS rollback; portal IDOR; committed plan prices; bypass-proof 30% discount; pricing reproducible/rollable back; traceability via `Integration_Log__c`).
2. Validate `DATA_MODEL.md` §21 build checklist.
3. Validate `BUSINESS_PROCESS.md` §22 business DoD (owners named; BQ1/BQ2 resolved; penalty seeds signed off; SLA/KPI agreed; one enforcement point per rule; failure paths tested; RACI confirmed; portal/advisor parity).
4. Record residual risks and go/no-go.

**Alternate / exception flows**
- E1: Any item unmet → no-go; create a follow-up card.

**Business rules**

| Rule | Source |
|---|---|
| Every rule has exactly one enforcement point, verified in the build | `BUSINESS_PROCESS.md` §22 |
| Portal and advisor produce identical eligibility and pricing | `BUSINESS_PROCESS.md` §22 |

**Acceptance criteria**
- [ ] Every DoD checklist item has evidence.
- [ ] Residual risks documented with owners.

**Test scenarios** — checklist walkthrough.

**Definition of done**
- [ ] Go/no-go decision recorded.

**Open questions / risks** — residual `R1`–`R17` items.
