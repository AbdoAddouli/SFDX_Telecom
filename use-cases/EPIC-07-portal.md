# E7 — Self-Service Portal (Phase 7)

**Objective:** let customers perform high-volume, low-complexity actions on Experience Cloud while pushing the same requests into the same governed back-office processes.
**Exit gate:** *Customer cancels; advisor sees it in the 360° view* (`ARCHITECTURE.md` §13).
**Source:** `ARCHITECTURE.md` §8.3, §10; `BUSINESS_PROCESS.md` §12 (Process 10); `DATA_MODEL.md` §5, §17.

> **Hard rule: no Apex controllers in the portal.** The shared org has 20+ `*Controller` classes for community login/registration — that anti-pattern must not be inherited (`ARCHITECTURE.md` §8.3).

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-POR-01 | Experience Cloud site and digital experience setup | Must | Salesforce Admin + Experience Cloud Dev | 🔲 |
| UC-POR-02 | **My Subscriptions** experience | Must | Experience Cloud Developer | 🔲 |
| UC-POR-03 | **Track My Requests** experience | Must | Experience Cloud Developer | 🔲 |
| UC-POR-04 | **Submit a Request** experience | Must | Experience Cloud Developer | 🔲 |
| UC-POR-05 | Portal security layer (IDOR, FLS, no controllers) | Must | Solution Architect + Developer | 🔲 |
| UC-POR-06 | Portal-to-back-office intake and live status | Must | Salesforce Developer + Admin | 🔲 |

---

### UC-POR-01 — Experience Cloud site and digital experience setup

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2, A6 |
| Suggested owner | Salesforce Admin + Experience Cloud Developer |
| Depends on | UC-FND-02 |
| Blocks | UC-POR-02…06 |
| Business process | 10 |
| Architecture ref | §8.3 |
| Data model ref | — |
| Status | 🔲 Not started |

**Goal.** Stand up the ATS portal site with the three experiences and a clean base (no inherited controller anti-patterns).

**Preconditions** — dedicated org (never `devtospace-stage`, which has 11 foreign Experience sites).

**Main flow**
1. Create the ATS digital experience / site.
2. Add the three experiences (My Subscriptions, Track My Requests, Submit a Request).
3. Configure `ats_PortalUser` guest + authenticated access per the FLS matrix.
4. Apply French/English via Translation Workbench (UC-FND-07).

**Alternate / exception flows**
- E1: Temptation to reuse an existing site in the shared org → **rejected**; prior sites carry foreign components.

**Business rules**

| Rule | Source |
|---|---|
| Dedicated site; do not inherit shared-org components | §2.2, `R6` |

**Acceptance criteria**
- [ ] Site live with three navigable experiences.
- [ ] No pre-existing `*Controller` classes referenced.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Authenticated customer | Navigate site | Three experiences reachable |

**Definition of done**
- [ ] Site deployed; access model applied.

**Open questions / risks** — none.

---

### UC-POR-02 — **My Subscriptions** experience

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2 |
| Suggested owner | Experience Cloud Developer |
| Depends on | UC-POR-01, UC-POR-05 |
| Blocks | — |
| Business process | 10 |
| Architecture ref | §8.3 |
| Data model ref | §3, §10.9, §17 |
| Status | 🔲 Not started |

**Goal.** Show the customer their active plans and equipment, read-mostly, with FLS enforced by default.

**Preconditions** — portal access model configured.

**Main flow**
1. Use LDS wire adapters (FLS enforced by default) to render `Subscription__c` and `Asset`.
2. Derive `AccountId` server-side — never accept it from the client.
3. Paginate with `LIMIT`; the list must not scale with subscription count.

**Alternate / exception flows**
- E1: A customer manipulates a URL to another account → zero rows returned (UC-POR-05).

**Business rules**

| Rule | Source |
|---|---|
| Data access via LDS wire adapters | §8.3 |
| Portal list must not scale with subscription count | §13.3 |

**Acceptance criteria**
- [ ] Only the authenticated customer's lines render.
- [ ] No Apex controller used.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Customer with 2 lines | Open experience | Exactly 2 lines |

**Definition of done**
- [ ] Jest/LWC tests; no controller.

**Open questions / risks** — none.

---

### UC-POR-03 — **Track My Requests** experience

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2 |
| Suggested owner | Experience Cloud Developer |
| Depends on | UC-POR-01, UC-POR-06 |
| Blocks | — |
| Business process | 10 |
| Architecture ref | §8.3 |
| Data model ref | §5.4 |
| Status | 🔲 Not started |

**Goal.** Let customers monitor quotes, orders, and customer requests by status.

**Preconditions** — intake (UC-POR-06) creates request records.

**Main flow**
1. Read-only views of `Customer_Request__c`, `Quote`, `Order`, `Case` scoped to the customer's own account.
2. Reflect request `Status__c` live.
3. `Calculated_Fee__c` rendered **read-only** (server value only).

**Alternate / exception flows**
- E1: Request delivered to another account's data → zero rows (IDOR).

**Business rules**

| Rule | Source |
|---|---|
| Customers cannot set fees | BR-10.3 |
| Live status visible | §13.2 |

**Acceptance criteria**
- [ ] Request statuses render and update with back-office progress.
- [ ] Fee fields are read-only on the portal.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Cancellation in `Awaiting_Approval` | Open experience | Status shown; fee read-only |

**Definition of done**
- [ ] Deployed; read-only enforced by FLS.

**Open questions / risks** — none.

---

### UC-POR-04 — **Submit a Request** experience

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2 |
| Suggested owner | Experience Cloud Developer |
| Depends on | UC-POR-01, UC-POR-05, UC-LIF-08 |
| Blocks | E7 exit gate |
| Business process | 06, 08, 10 |
| Architecture ref | §8.3 |
| Data model ref | §5, §11.2 |
| Status | 🔲 Not started |

**Goal.** Let a customer submit plan change and cancellation (and suspension/info) forms that land in the same back-office processes as advisor requests.

**Preconditions** — intake flow (UC-LIF-08) reusable; portal security layer (UC-POR-05).

**Main flow**
1. Screen Flow (LDS-based) with request-type selection: Plan Change | Cancellation | Suspension | Info.
2. `AccountId` derived **server-side** from the authenticated user.
3. Subscription picker scoped to the customer's own account.
4. Cancellation: mandatory reason + effective date ≥ 30 days.
5. Create `Customer_Request__c` (`Channel = Portal`) + `Case`.
6. Confirmation shown immediately (SLA-7).

**Alternate / exception flows**
- E1: Effective date < today+30 → blocked by the validation rule.
- E2: Reason blank → blocked.
- E3: Portal submissions disabled (`Portal_Requests_Enabled__c = false`) → friendly maintenance state.

**Business rules**

| Rule | Source |
|---|---|
| A portal request is never a different process — same queue, same rules | BR-10.1 |
| Identity derived server-side | BR-10.2, X12 |
| Customers cannot approve | BR-10.4 |

**Acceptance criteria**
- [ ] Both plan change and cancellation submit successfully from the portal.
- [ ] Requests land with `Channel = Portal` and a Case.
- [ ] Advisor sees the request in the 360° view (E7 exit gate).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Authenticated customer | Submit cancellation | Request + Case, Channel=Portal |
| TS-2 | Effective date too soon | Submit | Blocked |
| TS-3 | Submitted request | Advisor opens 360° | Request visible |

**Definition of done**
- [ ] E7 exit gate met; Playwright E2E in E9.

**Open questions / risks** — none.

---

### UC-POR-05 — Portal security layer (IDOR, FLS, no controllers)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2, Security |
| Suggested owner | Solution Architect + Developer |
| Depends on | UC-DM-12 |
| Blocks | UC-POR-02…04, E9 security test |
| Business process | 10 |
| Architecture ref | §8.3, §10 |
| Data model ref | §17 |
| Status | 🔲 Not started |

**Goal.** Make cross-account data access impossible and secrets unreachable — the portal *is* the primary attack surface.

**Preconditions** — `ats_PortalUser` FLS matrix applied.

**Main flow**
1. Enforce: **no Apex controllers in the portal**; LDS wire adapters for reads.
2. Writes only via Apex with `WITH USER_MODE`; never bare `insert`/`update`.
3. Filtering via `WITH SECURITY_ENFORCED` + `AccountId` derived from the authenticated user — **never** trust a client-supplied AccountId.
4. External APIs only via Named Credential; a server secret must never reach a client component.
5. Deny `ats_PortalUser` any `Integration_Log__c` or manager-level field access.

**Alternate / exception flows**
- E1 (IDOR): Customer changes the AccountId in a request → server ignores it; zero rows / request rejected.
- E2 (mass assignment): `Security.stripInaccessible` on externally supplied field maps.
- E3 (fee tampering): client value is display-only.

**Business rules**

| Rule | Source |
|---|---|
| Portal identity derived server-side, never client-supplied | X12, BR-10.2 |
| No portal Apex controllers | §8.3 |
| Portal never holds integration-log access | §17.1 |

**Acceptance criteria**
- [ ] A portal user querying another account returns zero rows.
- [ ] No secret is reachable client-side.
- [ ] Writes use `WITH USER_MODE`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Portal user A | Query user B's AccountId | Zero rows |
| TS-2 | Client supplies AccountId in payload | Submit | Ignored, server-derived |
| TS-3 | Sign up as new portal user | Attempt fee write | Denied |

**Definition of done**
- [ ] IDOR regression test in CI (`R7`); FLS tests per persona.

**Open questions / risks** — `R7` reportable breach if wrong.

---

### UC-POR-06 — Portal-to-back-office intake and live status

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 7 |
| Actor(s) | A2, A3, A4 |
| Suggested owner | Salesforce Developer + Admin |
| Depends on | UC-LIF-08, UC-POR-04 |
| Blocks | UC-POR-03 |
| Business process | 10, 06, 08 |
| Architecture ref | §8.3 |
| Data model ref | §5.5, §9.4 |
| Status | 🔴 Blocked — BQ (channel reporting) minor |

**Goal.** Ensure a portal request enters exactly the same governed process and its status is reflected back to the customer.

**Preconditions** — intake flow + portal forms live.

**Main flow**
1. Stamp `Channel__c = Portal` for portal-vs-advisor reporting.
2. Route the request into the same queue as an advisor request.
3. On each back-office status change, the customer's Track My Requests view reflects it.
4. `Portal_Requests_Enabled__c` feature flag gates submissions.

**Alternate / exception flows**
- E1: Back-office processing delayed → status remains truthful; SLA/KPI tracked (`BR-10`).

**Business rules**

| Rule | Source |
|---|---|
| Only `Channel__c` differs between portal and advisor requests | BR-10.1 |
| Portal pricing is the identical server-side RCA price | BR-10.6 |
| Channel mix KPI: Portal ≥ 50% | §16.1 |

**Acceptance criteria**
- [ ] Portal requests appear in the advisor queue with `Channel = Portal`.
- [ ] Status changes propagate to the portal view.
- [ ] Channel reporting produces the portal/advisor split.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Portal plan change | Advisor queue | Appears with Channel=Portal |
| TS-2 | Status → Completed | Customer view | Reflects Completed |

**Definition of done**
- [ ] Deployed; channel KPI measurable.

**Open questions / risks** — none.
