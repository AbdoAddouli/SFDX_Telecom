# E5 — Advisor Experience (Phase 5)

**Objective:** deliver the unified advisor cockpit and the one-component, five-step guided journey that both reuse the single server-side pricing path.
**Exit gate:** *The 5-step journey completes end-to-end from a blank Account* (`ARCHITECTURE.md` §13).
**Source:** `ARCHITECTURE.md` §8.1–8.2; `BUSINESS_PROCESS.md` §5 (Process 03), §13 (Process 11); `DATA_MODEL.md` §8, §10.5.

> Governance note: `customer360Shell` is the largest bespoke artefact and the highest maintenance cost. Keep each zone in its own child component (`ARCHITECTURE.md` §8.1, `R15`).

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-UX-01 | `customer360Shell` — composed container | Must | Front-end Developer (LWC) | 🔲 |
| UC-UX-02 | Customer Information zone + status badge | Must | Front-end Developer (LWC) | 🔲 |
| UC-UX-03 | Subscriptions zone (datatable, Subscribe/Unsubscribe) | Must | Front-end Developer (LWC) | 🔲 |
| UC-UX-04 | Subscriptions & Hardware zone | Must | Front-end Developer (LWC) | 🔲 |
| UC-UX-05 | Interactions zone (timeline) | Should | Front-end Developer (LWC) | 🔲 |
| UC-UX-06 | External API card (contextual data) | Should | Front-end Developer (LWC) | 🔲 |
| UC-UX-07 | `subscriptionWizard` — five-step guided journey | Must | Front-end Developer (LWC) | 🔲 |

---

### UC-UX-01 — `customer360Shell` — composed container

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-DM-02, UC-DM-12 |
| Blocks | UC-UX-02…06 |
| Business process | 11 |
| Architecture ref | §8.1 |
| Data model ref | §3 |
| Status | 🔲 Not started |

**Goal.** Provide the zoned container that declarative related lists cannot reproduce, with each zone isolated as a child component so a change in one does not destabilise the others.

**Preconditions** — permission set `ats_Advisor` assigned; record page exists.

**Main flow**
1. Build `lwc:customer360Shell` composed of four child zones (Information, Subscriptions, Hardware, Interactions) plus the External API card.
2. Add Highlights-panel actions: **Subscribe** (→ wizard) and **Unsubscribe** (→ request, not a direct cancel).
3. Keep zones independent; parent holds only layout/context.
4. Place on the Account record page via FlexiPage.

**Alternate / exception flows**
- E1: A zone's change breaks the shell → caused by coupling; refactor into the child.

**Business rules**

| Rule | Source |
|---|---|
| Largest bespoke artefact; child per zone | §8.1, BR-11.4, R15 |
| Every action inherits customer context — no re-selecting the account | BR-11.3 |

**Acceptance criteria**
- [ ] Shell renders all zones from a single Account context.
- [ ] Subscribe/Unsubscribe actions launch the correct flows.
- [ ] Each zone jest-tested independently.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Account with lines | Open record page | All zones render |
| TS-2 | One zone errors | Load shell | Other zones still render |

**Definition of done**
- [ ] Jest tests per child; FlexiPage deployed.

**Open questions / risks** — `R15` single large LWC.

---

### UC-UX-02 — Customer Information zone + status badge

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-UX-01 |
| Blocks | — |
| Business process | 11 |
| Architecture ref | §8.1 |
| Data model ref | §10.1 |
| Status | 🔲 Not started |

**Goal.** Show identity, segment, computed status badge, and active line count — with the badge derived from live data.

**Preconditions** — `Account` extensions deployed.

**Main flow**
1. Render `lightning-record-field` set for identity + segment.
2. Build `c-statusBadge` computing `Prospect / Subscribed / Suspended / Churned` from live subscription data.
3. Compute the active line count without a per-row relationship traversal.

**Alternate / exception flows**
- E1: Badge stored as a field → drifts; **rejected** (BR-11.1, X5).

**Business rules**

| Rule | Source |
|---|---|
| Status badge computed from live data, never a stored flag | BR-11.1 |
| The 360° status badge is a computed pill, never a stored boolean | §5.3 |

**Acceptance criteria**
- [ ] Badge updates immediately when a line's status changes.
- [ ] No stored status boolean exists.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Last line cancelled | Reload | Badge → Churned |

**Definition of done**
- [ ] Jest test on badge logic; no stored flag in the org.

**Open questions / risks** — BQ12 (any-line vs last-line churn) affects the badge rule.

---

### UC-UX-03 — Subscriptions zone (datatable, Subscribe/Unsubscribe)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-UX-01, UC-COM-04 |
| Blocks | E6 (Unsubscribe routing) |
| Business process | 11, 08 |
| Architecture ref | §8.1 |
| Data model ref | §3.2, §5 |
| Status | 🔲 Not started |

**Goal.** List the customer's lines with status pill, plan, and monthly price, and route destructive action through a request.

**Preconditions** — `Subscription__c` populated; `ats_Advisor` FLS.

**Main flow**
1. Render a `lightning-datatable` of `Subscription__c` with a status pill, plan, and `Monthly_Amount__c` (denormalised — no pricebook join).
2. **Unsubscribe** row action → creates `Customer_Request__c` of type `Cancellation`; it **never** cancels directly.
3. Disable Unsubscribe with a reason when an in-flight cancellation exists (`Is_Compliant_Request__c`).
4. **Subscribe** button → launch the wizard.

**Alternate / exception flows**
- E1: Advisor tries to cancel directly → not possible from this zone (BR-08.3).
- E2: In-flight cancellation → Unsubscribe disabled with reason, not hidden (BR-11.2).

**Business rules**

| Rule | Source |
|---|---|
| Unsubscribe creates a request, never a direct cancel | §8.1, BR-08.3 |
| Disable with a reason, do not silently hide | BR-11.2 |
| Denormalised `Monthly_Amount__c` avoids a pricebook join | §12 |

**Acceptance criteria**
- [ ] Datatable renders price without an extra query.
- [ ] Unsubscribe creates a `Customer_Request__c` with a linked Case.
- [ ] In-flight cancellation disables the action with a reason.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Active line | Click Unsubscribe | Request created, no status change |
| TS-2 | In-flight cancellation | View row | Action disabled + reason |

**Definition of done**
- [ ] Jest tests; no direct status write from the component.

**Open questions / risks** — none.

---

### UC-UX-04 — Subscriptions & Hardware zone

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-UX-01, UC-DM-10, E8 image sync |
| Blocks | UC-LIF-05 (equipment swap) |
| Business process | 11, 07 |
| Architecture ref | §8.1 |
| Data model ref | §10.9 |
| Status | 🔲 Not started |

**Goal.** Show provisioned assets — device image, serial, colour, status — and launch equipment swap.

**Preconditions** — `Asset` extensions deployed.

**Main flow**
1. Render a `lightning-datatable` of `Asset` filtered on `Service_Line_Type__c = Device`.
2. Read the **cached** `Device_Image_URL__c` — never a live callout per row.
3. Add an Equipment-swap row action → request (E6).
4. Show `Provisioned_Status__c` (BSS-fed).

**Alternate / exception flows**
- E1: Live image callout per row → would breach governor limits; **rejected** (§8.2).

**Business rules**

| Rule | Source |
|---|---|
| Device images read from cache, never live per row | §8.2, §9 |
| `Asset.Provisioned_Status__c` is BSS-fed, read-only | §10.9 |

**Acceptance criteria**
- [ ] Hardware zone renders images from the cached URL only.
- [ ] Equipment-swap action routes to a request.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | 50 assets | Render zone | Zero live callouts |

**Definition of done**
- [ ] Jest test asserting no callout per row; FlexiPage updated.

**Open questions / risks** — depends on E8 image sync for populated URLs.

---

### UC-UX-05 — Interactions zone (timeline)

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-UX-01 |
| Blocks | — |
| Business process | 11 |
| Architecture ref | §8.1 |
| Data model ref | §10.11 |
| Status | 🔲 Not started |

**Goal.** Give a single timeline of Cases, Opportunities, Quotes, and Orders so any historical request can be opened.

**Preconditions** — `Case` extensions deployed.

**Main flow**
1. Render a timeline / OmniCards of related Case, Opportunity, Quote, Order records.
2. Use `Case.Subscription_Link__c` to speed the query.
3. Allow opening any historical request from the timeline.

**Alternate / exception flows** — none.

**Business rules**

| Rule | Source |
|---|---|
| Full traceability — every request is openable from the timeline | §3.5, X1 |

**Acceptance criteria**
- [ ] Timeline shows the four record types scoped to the account.
- [ ] Query does not scale with total org records.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Account with history | Open zone | Records listed chronologically |

**Definition of done**
- [ ] Jest tests; query selective.

**Open questions / risks** — none.

---

### UC-UX-06 — External API card (contextual data)

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 5 |
| Actor(s) | A3, A4 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-UX-01, E8 `ExternalApiService` |
| Blocks | — |
| Business process | 11 |
| Architecture ref | §8.1, §9 |
| Data model ref | §9.2 |
| Status | 🔲 Not started |

**Goal.** Demonstrate the integration pattern on the cockpit without hardcoding a vendor — e.g. a weather/context card served through `ExternalApiService`.

**Preconditions** — `External_Api__mdc` seeded with the `Weather` row; Named Credential registered.

**Main flow**
1. Build `c-externalApiCard` calling `ExternalApiService` (server-side).
2. Cache per `Cache_Ttl_Seconds__c`.
3. Never place a server secret in the component; resolve via Named Credential.

**Alternate / exception flows**
- E1: API dead → toggle `Is_Active__c` off without a deployment; card degrades gracefully.

**Business rules**

| Rule | Source |
|---|---|
| No hardcoded URL or key in Apex or LWC | §15, anti-pattern |
| Secret never reaches a client component | §8.3 |

**Acceptance criteria**
- [ ] Card renders contextual data via the service.
- [ ] Disabling the API in metadata degrades cleanly with no deploy.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | `Weather.Is_Active__c = false` | Render card | Graceful empty state |

**Definition of done**
- [ ] Depends on E8 service; jest test for degraded state.

**Open questions / risks** — none.

---

### UC-UX-07 — `subscriptionWizard` — five-step guided journey

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 5 |
| Actor(s) | A3 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-CAT-08, UC-COM-01, UC-DM-07, UC-LIF-01 |
| Blocks | E5 exit gate, E9 E2E |
| Business process | 03, 11 |
| Architecture ref | §8.2 |
| Data model ref | §8 |
| Status | 🔲 Not started |

**Goal.** Deliver **one component, five steps** with persisted state — five record pages would mean five layouts, five permission sets, and no resumable state.

**Preconditions** — `CatalogQueryService` + `OfferBuilderService` live; wizard state object deployed.

**Main flow** (states per `ARCHITECTURE.md` §8.2)
1. **Step 1 — Confirm information:** Account/Contact with real-time **debounced** write-back via an `Is_Autosync__c` flag (not per keystroke).
2. **Step 2 — Offer type:** Mobile | Landline.
3. **Step 3 — Select plan:** `CatalogQueryService.getPlans(type, commitment)`; option-aware filtering via the RCA Configuration API; fibre filtered against `Eligibility__c`.
4. **Step 4 — Add device:** `getDevices()`; images from cache; `Requires_Commitment__c` constraint applied.
5. **Step 5 — Confirm:** server-side RCA price breakdown (rendered read-only) → `OfferBuilderService.createQuote()` → **Finish & Activate** → `ActivationService`.
6. Persist state in `Subscription_Wizard_State__c` after each step; resume at the last step after a dropped connection.
7. Block activation at step 5 if `Earliest_Activation_Date__c` is in the future.

**Alternate / exception flows**
- E1: Connection lost mid-journey → resumes at the last step (E11/BR-03.7).
- E2: Session inactive 7 days → hard-deleted; advisor restarts.
- E3: Fibre plan with future activation date → selectable but activation blocked with the date shown.

**Business rules**

| Rule | Source |
|---|---|
| One component, persisted state | §8.2 |
| Pricing server-side only; LWC renders | §6.5, BR-03.5 |
| Step 3 option-aware filtering via service | §8.2 |
| Real-time sync debounced — not a save per keystroke | §8.2 |
| Sessions expire after 7 days and hard-delete | BR-03.7 |

**Acceptance criteria**
- [ ] The five steps complete end-to-end from a blank Account.
- [ ] Closing the browser and reopening resumes at the last step.
- [ ] `getPriceBreakdown` is the only source of any displayed price.
- [ ] Fibre speed/eligibility filters and the future-activation block work.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Blank Account | Complete all 5 steps | Quote + activation |
| TS-2 | Drop connection at step 4 | Reopen wizard | Resumes at step 4 |
| TS-3 | Fibre postcode capped at 20 Mbps | Step 3 | 100 Mb not selectable |
| TS-4 | Future earliest activation | Step 5 | Activation blocked with date |
| TS-5 | Rapid typing in step 1 | Observe DML | Debounced, not per keystroke |

**Definition of done**
- [ ] E5 exit gate met; Playwright E2E in E9.

**Open questions / risks** — `R4` API signatures; wizard state ownership (BR-11.3).
