# ATS Telecom — Business Process Specification

**Status:** Design specification, not implemented
**Companion documents:** [`ARCHITECTURE.md`](./ARCHITECTURE.md) · [`DATA_MODEL.md`](./DATA_MODEL.md)
**Date:** 2026-10-08
**Author:** Solution Architecture

---

## 0. Purpose and Scope

This document specifies **how ATS Telecom does business** on the target platform: the end-to-end processes, the roles that execute them, the hand-offs between them, the business rules that govern them, and the measures that prove they work.

**In scope:** customer acquisition, quotation, subscription, activation, in-life service management (plan change, suspension, equipment swap, portability), cancellation and churn, renewal, self-service, exception handling, and the operational governance around them.

**Out of scope:** implementation detail (see `ARCHITECTURE.md` §7–§8), field-level structure (see `DATA_MODEL.md`), billing and revenue recognition (pending Q2/Q3 open decisions).

### How to read this document

| Section | Answers |
|---|---|
| §1 | Who the players are |
| §2 | The end-to-end value chain |
| §3–§11 | The individual processes, each with trigger, flow, rules, roles, and systems |
| §12 | Cross-cutting business rules |
| §13 | SLAs and KPIs |
| §14 | Exceptions and failure paths |
| §15 | RACI matrix |
| §16 | Open business questions |

---

## 1. Business Context and Actors

### 1.1 What ATS Telecom sells

A consumer telecom portfolio delivered over a single commercial and service platform:

| Portfolio | Products | Commitment options | Notes |
|---|---|---|---|
| **Mobile** | Mobile 5 / 20 / 50 / 100 GB | No commitment, 12-month, 24-month | Unlimited calls + SMS on all tiers |
| **Fibre & Landline** | Fiber 20 Mb, Fiber 100 Mb | No commitment, 12-month, 24-month | Subject to geographic eligibility |
| **Devices** | iPhone 15 Pro, iPhone 13, Samsung S22 | Inherit the plan's commitment | Most devices **require** a commitment |

Commercial rules of record:

- Commitment discount: **−10%** at 12 months, **−20%** at 24 months.
- Bundle discount: **−30%** on a mobile phone when an eligible mobile plan is on the same quote.
- Bundle discount: **−15%** on the mobile line when bundled with fibre.
- Some smartphones cannot be sold without a commitment (`Requires_Commitment__c`).

### 1.2 Actor inventory

| # | Actor | Role | Primary system surface |
|---|---|---|---|
| A1 | **Prospect** | Unknown individual who may subscribe | Portal lead form, bulk import source, marketing |
| A2 | **Customer (self-service)** | Authenticated subscriber managing their own services | Experience Cloud portal |
| A3 | **Advisor (Sales)** | ATS employee selling and configuring subscriptions | Advisor Console — 360° view + guided wizard |
| A4 | **Service Agent** | ATS employee handling requests, cancellations, faults | Advisor Console — service zones, Case |
| A5 | **Advisor Manager** | Approves fee overrides, goodwill waivers, threshold breaches | Approval console |
| A6 | **Operations Admin** | Runs reconciliation, pricing activation, schedulers | Setup + Ops permission set |
| A7 | **Pricing Admin** | Owns catalogue, decision tables, pricing procedures | Revenue Cloud setup |
| A8 | **Finance** | Owns penalty policy, revenue treatment, notice periods | Policy owner — not a daily system user |
| A9 | **Network / BSS** | External provisioning and network inventory systems | BSS/OSS integration boundary |
| A10 | **Marketing** | Receives qualified leads and consented contacts | Marketing Cloud (out of detail scope) |

### 1.3 Customer segments

| Segment (`Account.Segment__c`) | Behaviour | Business impact |
|---|---|---|
| **Consumer** | Individual, Person Account, portal-first | Penalty rules 1–5 in the matrix; self-service is primary channel |
| **Business (SOHO)** | Small business, advisor-assisted | Flat 15% penalty rule; may require contact-level authority checks |

> Under D4 the primary model is **Person Accounts (B2C)**. The Business segment is retained for pricing and penalty differentiation, not as a full B2B account hierarchy.

---

## 2. End-to-End Value Chain

```
  ACQUIRE                SELL                     DELIVER                SERVE                 RETAIN
┌───────────┐      ┌──────────────┐        ┌──────────────┐      ┌───────────────┐     ┌──────────────┐
│ Lead       │ ───► │ Qualify      │ ─────► │ Quote        │ ───► │ Activate      │ ──► │ In-life      │
│ capture    │      │ + convert    │        │ + order      │        │ (provision)   │     │ service      │
└───────────┘      └──────────────┘        └──────────────┘      └───────────────┘     └──────┬───────┘
                                                                                              │
                     ┌──────────────┐        ┌──────────────┐      ┌───────────────┐          │
                     │ Win-back /   │ ◄───── │ Offboard     │ ◄──── │ Change /      │ ◄────────┘
                     │ retention    │        │ (cancel)     │        │ suspend       │
                     └──────────────┘        └──────────────┘      └───────────────┘
```

**Governing business principle:** *no service state changes except through a controlled process.* Every lifecycle change produces a `Customer_Request__c` linked to a `Case`, so the company can always answer "what happened, who asked, what were they told, and what did we charge."

---

## 3. Process 01 — Customer Acquisition & Lead Management

### 3.1 Purpose

Convert unknown interest into a qualified, deduplicated, consented `Lead` ready for conversion into a customer record.

### 3.2 Trigger

An inbound prospect signal from any of three intake channels:

| Channel | Entry path | Volume profile |
|---|---|---|
| **Bulk import** | Home-page LWC → `LeadImportService` (Bulk API) | High — campaign lists of thousands |
| **Portal form** | Experience Cloud contact form → Screen Flow → `Lead` | Medium, continuous |
| **Marketing / API** | Marketing Cloud, web, phone → `Lead` with `Lead_Source_Detail__c` | Medium |

### 3.3 Process flow

```
[Signal received]
      │
      ├─ Bulk path ──► LeadImportService (Apex, bulk-safe)
      │                     ├─ dedupe check (Duplicate_Checked__c)
      │                     ├─ consent stamp (Consent_Given__c)
      │                     └─ Convert_Score__c scoring
      │
      └─ Form path ──► Screen Flow validation
                            ├─ reCAPTCHA / rate limit (guest users)
                            └─ create Lead (status = New)
      │
      ▼
[Lead queue — scored & deduplicated]
      │
      ▼
[Advisor review] ── insufficient data ──► Disqualify (reason recorded)
      │
      qualified
      ▼
[Lead.Status = 'Ready']
      │
      ▼
CONVERSION FLOW
      ├─► Account (Person Account, Segment, Legacy ID)
      ├─► Contact (DNC flag, preferred method, primary)
      └─► Opportunity (Journey_Step__c = Capture, Portal_Source__c)
      │
      ▼
[Journey enters Process 02 — Quotation]
```

### 3.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-01.1 | **Consent before marketing.** `Consent_Given__c` must be TRUE before any marketing sync or outbound campaign entry. | Flow entry condition; block sync if false |
| BR-01.2 | **Do-Not-Call is global.** A `Contact.Do_Not_Call__c` of TRUE suppresses all outbound call tasks regardless of campaign. | Task creation flow condition |
| BR-01.3 | **Dedupe before create.** Bulk imports must run a duplicate check against name + postal code + phone; duplicates are flagged, not merged automatically. | `Duplicate_Checked__c` stamp |
| BR-01.4 | **Conversion is idempotent.** Re-running a bulk import or a conversion never produces a second Account for the same source row. | External ID (`Legacy_Customer_Id__c`) upsert |
| BR-01.5 | **Consent is recorded, not assumed.** Portal form submissions record consent timestamp and source. | Field on Lead |
| BR-01.6 | Bulk conversion must handle lists of 10,000+ without governor breach. | `LeadImportService`, Bulk API, batch chunks |

### 3.5 Hand-offs

| From | To | Artefact |
|---|---|---|
| Marketing | Advisor | Qualified `Lead` in queue |
| Advisor | Sales journey | `Opportunity` at `Journey_Step__c = Capture` |

---

## 4. Process 02 — Qualification & Eligibility

### 4.1 Purpose

Establish whether ATS can actually deliver the requested service to the requested address **before** a price is promised. Fibre sales without eligibility checking are the classic source of unfulfillable orders.

### 4.2 Trigger

- Advisor opens the guided journey on a customer Account (step 1 → step 3 for fibre), **or**
- Portal customer requests a fibre plan, **or**
- A `Customer_Request__c` of type `NewSubscription` targets a fibre product.

### 4.3 Process flow

```
[Customer postal code captured]
      │
      ▼
EligibilityService ──► SELECT from Eligibility__c
                        WHERE Postal_Code__c = :code
                          AND Is_Active__c = TRUE
      │
      ├─ No record / Fiber_Available__c = false
      │        └─► RESULT: fibre NOT offered.
      │             Mobile & landline-only catalogue presented.
      │             Customer informed of non-coverage (reason shown verbatim).
      │
      ├─ Fiber available but Max_Downstream_Mbps__c < plan speed
      │        └─► RESULT: plan filtered OUT of the selectable list.
      │             Faster plans still shown.
      │
      ├─ Earliest_Activation_Date__c > today
      │        └─► RESULT: plan selectable but activation BLOCKED at step 5.
      │             Earliest date shown to customer as a promise constraint.
      │
      └─ Service_Restrictions__c populated
               └─► RESULT: restriction displayed verbatim before confirmation.
      │
      ▼
[Eligibility result recorded on the request / opportunity
 Eligibility_Checked__c = TRUE]
```

### 4.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-02.1 | **No promise without coverage.** A fibre plan whose postcode has no active `Eligibility__c` record can never be quoted. | Wizard step 3 filter (server-side) |
| BR-02.2 | **Speed gate.** `Max_Downstream_Mbps__c >= Product2.Speed_Mbps__c` must hold. | `CatalogQueryService` filter |
| BR-02.3 | **Earliest activation is a promise.** If `Earliest_Activation_Date__c` is in the future, the customer must be shown the date and activation must not be represented as immediate. | Step 5 block + UI notice |
| BR-02.4 | **Eligibility is a customer attribute, not a product attribute.** It lives on `Eligibility__c`, never in the catalogue. | Architecture rule §6.3 |
| BR-02.5 | Eligibility results are **read-only snapshots** — coverage changes do not retroactively invalidate a signed contract; they block *new* sales. | No write-back from network to active contracts |
| BR-02.6 | Portal and advisor must return **the same** eligibility answer for the same postcode. | Single `EligibilityService`, no client-side logic |

### 4.5 Hand-off

Eligibility passes → **Process 03 (Quotation)**. Fails → alternative offer (mobile-only) or record an `Info`/`NewSubscription` request with reason.

---

## 5. Process 03 — Quotation & Configuration (Guided Journey)

### 5.1 Purpose

Produce a priced, compliant, customer-specific offer that both the advisor and the portal render identically.

### 5.2 Trigger

Advisor clicks **Subscribe** on the 360° view, or a portal customer starts a subscription request.

### 5.3 The five-step journey

| Step | Name | Actor action | System action | Data written |
|---|---|---|---|---|
| **1** | Confirm information | Verify / correct customer details | Real-time debounced write-back | `Account`, `Contact` |
| **2** | Choose offer type | Mobile or Landline/Fibre | Filters catalogue by `Plan_Type__c` | `Offer_Type__c` |
| **3** | Select plan | Choose plan + **commitment option** | Server-side: `CatalogQueryService` → RCA Configuration API; eligibility filter for fibre | `Product__c`, `Selling_Model_Option__c` |
| **4** | Add device (optional) | Choose a phone | Reads cached `Device_Image_URL__c` (never live callouts); applies `Requires_Commitment__c` constraint | `Device__c` |
| **5** | Confirm & quote | Review authoritative price breakdown | Server-side: RCA Pricing API → `OfferBuilderService.createQuote()` | `Quote`, `QuoteLineItem`, `Price_Breakdown__c` |

**Journey state** is persisted in `Subscription_Wizard_State__c` so a dropped connection, a browser crash, or an end-of-day does not lose the session. Only one active wizard state per advisor.

### 5.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-03.1 | **One product, many commitment options.** `Mobile 5 GB` is a single `Product2`; 12/24/no-commitment are `ProductSellingModelOption` variants. Never separate products. | Catalogue design |
| BR-03.2 | **Commitment choice binds the engagement.** Selecting `COMMIT12` sets `Engagement__c.Duration_Months__c = 12`; `NOCOMMIT` creates no engagement. | Quote line snapshot `Commitment_Option_Code__c` |
| BR-03.3 | **Device commitment constraint.** A device with `Requires_Commitment__c = true` cannot appear on a quote whose plan option is `NOCOMMIT`. | RCA `ProductConfigurationRule` |
| BR-03.4 | **Bundle discount is automatic and non-bypassable.** 30% off the device appears whenever plan + device are both on the quote. | RCA `BundleBasedAdjustment` |
| BR-03.5 | **Price is never computed client-side.** The wizard and portal render a server-returned breakdown only. | Architectural rule §6.5 |
| BR-03.6 | **Quote line snapshots the commitment option.** A later catalogue change never alters an issued quote. | `QuoteLineItem.Commitment_Option_Code__c` |
| BR-03.7 | Wizard sessions expire after 7 days of inactivity and are hard-deleted — they are not financial records. | `Expires_On__c` + cleanup batch |
| BR-03.8 | Advisors may view margin only with `ats_View_Margin__c`; customers never see cost. | Custom permission |

### 5.5 Outputs and hand-offs

| Output | Meaning | Goes to |
|---|---|---|
| `Quote` (accepted by customer) | Commercial offer on the table | Process 04 |
| `Quote` (rejected / abandoned) | Closed no-quote; reason captured if available | Reporting only |
| `Subscription_Wizard_State__c` | Resumable session | Cleanup job after 7 days |

---

## 6. Process 04 — Order & Contract Creation

### 6.1 Purpose

Convert an accepted quote into an executable `Order` and the commercial container (`Contract` + `ContractLineItem`) that will hold the term of record.

### 6.2 Trigger

Customer (or advisor on the customer's behalf) accepts the quote — "Finish & Activate" is pressed, or the portal customer confirms.

### 6.3 Process flow

```
[Accepted quote]
      │
      ▼
OfferBuilderService (Apex, invoked from Flow)
      ├─ Validate quote: priced lines, commitment option resolved, eligibility still valid
      ├─ Create / amend Contract
      │     ├─ ATS_Contract_Type__c = Mobile | Fiber | Bundle
      │     ├─ Term = 12 / 24 months (or rolling if NOCOMMIT)
      │     └─ ContractLineItem per quoted line, linked to Engagement
      ├─ Create Order  → Activation_State__c = Ready
      ├─ Create OrderItem per line (Subscription_Number__c pre-allocated)
      └─ Opportunity.Journey_Step__c = Ordered
      │
      ▼
[Order ready for activation] ──► Process 05
```

### 6.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-04.1 | **The Contract is the term of record.** Duration, renewal date and adjustments live on `Contract`/`ContractLineItem`, not on the subscription. | Data model §5.2 |
| BR-04.2 | **Plan change semantics are pending (Q1).** Default: plan change **amends** the existing contract rather than creating a new one. This must be confirmed by Finance before Phase 1. | Open decision Q1 |
| BR-04.3 | **Order cannot be activated twice.** `Activation_State__c` moves `Ready → Activating → Activated`, and any state other than `Ready` blocks re-entry. | Idempotency guard |
| BR-04.4 | A quote with zero priced lines, or an eligibility that has expired, cannot produce an Order. | Service validation |
| BR-04.5 | Contract type determines which subscriptions terminate together on cancellation. | `ATS_Contract_Type__c` |

### 6.5 Hand-off

Order in `Ready` state → **Process 05 (Activation & Provisioning)**.

---

## 7. Process 05 — Activation & Provisioning

> **The single most critical process in the company.** It is where money starts accruing, where the network is touched, and where an error creates a customer with no service and a duplicate bill.

### 7.1 Purpose

Atomically turn a commercial Order into a live service: provisioned asset, active subscription, engagement in force, and a confirmed BSS record.

### 7.2 Trigger

Advisor clicks **Finish & Activate**, a portal customer confirms, or a BSS batch activates a queue of orders.

### 7.3 Process flow

```
[Activate(orderId)]
      │
      ▼
1. VALIDATE
   ├─ Order.Activation_State__c = Ready?
   ├─ OrderItems exist?
   └─ Not already activated?  ── YES ──► EXIT (no-op, idempotent)
      │
      ▼
2. PER ORDER ITEM (bulk, 200 at a time)
   ├─ Upsert Asset            (keyed on OrderItemId — idempotent)
   ├─ Create Subscription__c  (Status = PendingActivation → Active,
   │                           Activation_Date = today,
   │                           Service_Line_Type from product)
   ├─ Create Engagement__c    (ONLY if commitment option ≠ NOCOMMIT;
   │                           Duration = 12/24, Start = today,
   │                           Monthly_Amount + Penalty_Rate SNAPSHOT)
   ├─ Set Root_Engagement__c  (device lines inherit the plan's engagement)
   └─ Bind Asset ↔ Contract   (AssetContractRelationship)
      │
      ▼
3. ORDER → Activation_State__c = Activated
4. CONTRACT activated (start date = today)
      │
      ▼
5. BSS CALLOUT  (Named Credential, idempotency key = Subscription_Number__c)
      ├─ Success ──► persist BSS identifiers (External_Reference__c, MSISDN)
      └─ Failure ──► FULL ROLLBACK. Order returns to Ready.
                     Integration_Log__c = Failure.
                     Nothing is partially created. Customer is NOT
                     told they have service.
      │
      ▼
6. PUBLISH platform event 'ats.service.activated.v1'  (AFTER commit)
7. SCHEDULE confirmation notification to customer
8. LOG every step to Integration_Log__c with shared Correlation_Id__c
```

### 7.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-05.1 | **All or nothing.** Partial activation (asset exists, no subscription; or Salesforce live, BSS not provisioned) is a business failure, not an accepted state. | Single transaction, `allOrNone`, rollback on callout failure |
| BR-05.2 | **Double-click safe.** Pressing activate twice produces exactly one subscription and one BSS provisioning. | `Activation_State__c` + External IDs + test |
| BR-05.3 | **Bulk safe.** A 500-order batch must complete within governor limits. | Apex bulk design; 200-row test |
| BR-05.4 | **No engagement, no commitment.** `NOCOMMIT` orders never create an `Engagement__c` — and therefore never incur a penalty. | Conditional creation |
| BR-05.5 | **Snapshots at inception.** `Monthly_Amount__c` and `Penalty_Rate__c` are written once at activation and never recomputed. | Service-enforced immutability |
| BR-05.6 | **Service is live only when BSS confirms.** The customer notification fires after a successful BSS response, not before. | Step ordering |
| BR-05.7 | Every activation is traceable end-to-end via `Correlation_Id__c` across all log entries. | `Integration_Log__c` |
| BR-05.8 | If the BSS feature flag is off (network incident), activation is held in `Ready` and surfaced to operations — never silently skipped. | `ATS_Feature_Flags__c.BSS_Provisioning_Enabled__c` |

### 7.5 Post-activation state

| Object | State reached |
|---|---|
| `Order` | `Activated` |
| `Contract` | Active, start = today |
| `Asset` | Provisioned, linked to contract |
| `Subscription__c` | `Active`, `Activation_Date__c` = today |
| `Engagement__c` | `Active` (if committed), `End_Date__c` = today + 12/24 months |
| `Account.Customer_Status__c` | `Subscribed` |
| `Opportunity` | `Journey_Step__c = Activated` |

### 7.6 Hand-off

**Process 08 (In-life Service)** for the duration of the term; **Process 10 (Renewal)** at T−60 days.

---

## 8. Process 06 — Plan Change

### 8.1 Purpose

Let a customer upgrade or downgrade their plan mid-term while correctly repricing the contract, superseding the old service instance, and preserving commitment integrity.

### 8.2 Trigger

- Portal: **Submit a Request → Plan Change**
- Advisor: 360° view → request action
- Service agent: inbound call

### 8.3 Process flow

```
[Plan change request raised]
      │  (creates Customer_Request__c + Case, Channel stamped)
      ▼
INTAKE
      ├─ Resolve Subscription__c (target line)
      ├─ Resolve Impacted_Engagement__c (current active commitment)
      ├─ Re-check eligibility if fibre is involved
      ▼
ELIGIBILITY CHECK ── fail ──► Rejected (reason), alternative offered
      │ pass
      ▼
RE-QUOTE
      ├─ CatalogQueryService → new plan, commitment option
      ├─ RCA Pricing API → authoritative new monthly price
      └─ OfferBuilderService → new Quote (linked to the request)
      │
      ▼
[Decision: is this an amendment or a new contract? — Q1, default AMEND]
      │
      ├─ AMEND (default): ContractLineItem rate adjusted;
      │     old Subscription__c → Superseded (terminal);
      │     new Subscription__c → Active, Parent_Subscription__c set;
      │     Engagement UNCHANGED (same term continues)
      │
      └─ NEW CONTRACT: close old contract; open new one; engagement
            restarts — full term, new penalty clock
      │
      ▼
APPROVAL (conditional)
      ├─ No fee / no term change ──► auto-approved
      └─ Fee above ATS_Feature_Flags__c.Cancellation_Approval_Threshold__c
            ──► Awaiting_Approval ──► Advisor Manager
      │
      ▼
FULFILMENT ──► Order → ActivationService (existing service reused)
      │
      ▼
Customer notified · Case closed · Request Completed
```

### 8.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-06.1 | **The engagement does not restart on a plan upgrade by default.** The customer's 12/24-month clock continues; only the rate changes. | Amendment path (pending Q1 confirmation) |
| BR-06.2 | **Old line is superseded, never deleted.** `Superseded` is terminal; history remains queryable. | State machine |
| BR-06.3 | **Target subscription is mandatory** for a plan change request. | Validation rule |
| BR-06.4 | **Device-only plans cannot be changed independently** of their parent engagement — the root engagement governs penalty once, not twice. | `Root_Engagement__c` |
| BR-06.5 | The new price is always server-computed; the request's `Calculated_Fee__c` is display-only for the client. | `EngagementPenaltyService` / RCA pricing |
| BR-06.6 | A plan change is only possible while `Impacted_Engagement__c.Status__c = Active` and not past `End_Date__c`. | `Is_Compliant_Request__c` computed server-side |
| BR-06.7 | Every plan change carries a `Case` for traceability (except `Info` requests). | Required lookup |

### 8.5 Hand-off

Completed change → notification; if a fee applied → Finance reporting on `Calculated_Fee__c`.

---

## 9. Process 07 — Suspension, Equipment Swap & Portability

Three smaller lifecycle processes share a common intake skeleton.

### 9.1 Common intake

```
Request raised (Portal | Advisor | API)
   └─► Customer_Request__c + Case
         ├─ Request_Type__c = Suspension | EquipmentSwap | Portability
         ├─ Subscription__c required (validation rule)
         ├─ Status: Draft → Submitted → In_Fulfilment → Completed
         └─ Impacted_Engagement__c resolved at intake
```

### 9.2 Suspension (freeze / unfreeze)

| Aspect | Rule |
|---|---|
| Effect on `Subscription__c` | `Active → Suspended` (reversible transition) |
| Effect on `Contract` | **Unchanged** — the commercial term continues to run |
| Effect on `Engagement__c` | **Unchanged** — a freeze does not stop the commitment clock (default policy, confirm with Commercial) |
| Effect on billing | Suspended lines bill a suspension fee or nothing per policy — **out of scope pending Q2/Q3** |
| BSS | Callout to suspend the line; failure rolls back the status change |
| Exit | `Suspended → Active` via the reverse request |

### 9.3 Equipment swap

| Aspect | Rule |
|---|---|
| Effect on `Subscription__c` | **Unchanged** — the service instance survives |
| Effect on `Asset` | Old asset → `Retired`; new asset → created, `Parent` relationship preserved |
| Effect on `Engagement__c` | **Unchanged** unless the swap changes the device's commitment tier |
| Stock/serial | New `Asset` records serial, colour, image; lineage via `OrderItem` |
| BSS | Device IMEI swap callout |

### 9.4 Number portability (inbound and outbound)

| Aspect | Rule |
|---|---|
| Effect on `Subscription__c` | `MSISDN__c` updated **only after** the donor network confirms |
| Ordering | Two-phase: request → wait for confirmation → apply. Never optimistically overwrite the number |
| Uniqueness | `MSISDN__c` is unique when populated — enforced by duplicate rule + trigger |
| BSS | Port request callout with idempotency key = subscription number |

### 9.5 Business rules common to all three

| # | Rule | Enforcement |
|---|---|---|
| BR-07.1 | All three require an existing `Subscription__c`. | Validation rule |
| BR-07.2 | All three create a `Case`. | Required lookup |
| BR-07.3 | None of the three may be executed as a direct field edit from a list view — they go through a request so the reason and approval are captured. | UI + permission design |
| BR-07.4 | Status transitions are enforced by the state machine, not by the Flow. | Trigger handler |

---

## 10. Process 08 — Cancellation & Offboarding

> The highest-risk, highest-scrutiny process. It is where churn data, regulatory notice periods, penalty revenue, and customer goodwill all converge.

### 10.1 Purpose

Terminate a service in a way that is legally compliant (notice period), financially correct (penalty), fully traceable (case + reason), and operationally clean (network released, no orphan records).

### 10.2 Trigger

- Portal: **Submit a Request → Cancellation**
- Advisor 360°: **Unsubscribe** button — *creates a request; it never cancels directly*
- Service agent on an inbound call

### 10.3 Process flow

```
[Cancellation intent]
      │
      ▼
1. INTAKE  (always a Customer_Request__c + Case — never a direct status edit)
      ├─ Channel = Portal | Advisor | API | Batch
      ├─ Cancellation_Reason__c  ◄── MANDATORY (validation rule)
      ├─ Cancellation_Effective_Date__c ◄── must be ≥ today + 30 days
      ├─ Customer_Comment__c captured
      └─ Subscription__c targeted
      │
      ▼
2. FEE CALCULATION  (EngagementPenaltyService — server-side only)
      ├─ Resolve Engagement__c (current active commitment)
      ├─ Resolve Engagement_Penalty__mdt row by
      │     (segment, category, duration, activity date), lowest Priority wins
      ├─ If within penalty-free window (Penalty_Applicable_After_Months__c)
      │     ──► fee = 0
      ├─ Else fee = MIN(Months_Remaining × Monthly_Amount × Penalty_Rate,
      │                Max_Penalty_Cap × contract value)
      ├─ Snapshots: Monthly_Amount, Penalty_Rate, Penalty_Rule stamped
      ├─ Fee_Breakdown__c written in plain language
      └─ Calculated_Fee__c written (server-computed ONLY)
      │
      ▼
4. APPROVAL GATE
      ├─ Fee = 0                          ──► auto-proceed
      ├─ Fee ≤ threshold                  ──► advisor may proceed
      ├─ Fee > threshold                  ──► Awaiting_Approval → Advisor Manager
      └─ Goodwill_Waiver__c = TRUE        ──► Manager approval + mandatory
                                              Goodwill_Justification__c
      │
      ▼
5. DECISION
      ├─ Approved ──► Fulfilment
      └─ Rejected ──► Rejection_Reason__c mandatory; customer informed
      │
      ▼
6. FULFILMENT  (effective on Cancellation_Effective_Date__c)
      ├─ Subscription__c → PendingCancellation  (today → effective date)
      ├─ On effective date (scheduled job):
      │     ├─ Subscription__c → Cancelled      (TERMINAL)
      │     ├─ Asset         → Retired
      │     ├─ Contract      → Terminated
      │     ├─ Engagement__c → Breached
      │     │     ├─ Early_Termination_Fee__c = calculated fee
      │     │     ├─ Breach_Amount__c = charged (may differ after waiver)
      │     │     └─ Status terminal
      │     └─ Account.Customer_Status__c → Churned (if no other lines)
      ├─ BSS de-provision callout (rollback on failure)
      └─ Platform event published after commit
      │
      ▼
7. CLOSE
      ├─ Resolution_Summary__c written
      ├─ Completed_On__c stamped
      ├─ Case closed
      └─ Cancellation reason feeds churn analytics
```

### 10.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-08.1 | **A cancellation reason is always mandatory.** Field-level required is deliberately OFF (it would demand the field on non-cancellation requests); a validation rule enforces it. | Validation rule |
| BR-08.2 | **30-day notice period.** `Cancellation_Effective_Date__c` must be ≥ today + 30 (confirm scope with Commercial — Q5). | Validation rule |
| BR-08.3 | **No direct cancel from the 360° view.** The Unsubscribe button opens a request. This is what preserves reason, fee, approval and case linkage. | UI design + permission |
| BR-08.4 | **Fee is server-computed and reproducible.** Because `Monthly_Amount__c` and `Penalty_Rate__c` are snapshots, recalculating a 2-year-old engagement today yields the same number as then. | Snapshot policy |
| BR-08.5 | **Penalty-free window respected.** Cancelling in month 1 of a 12-month contract (window = 1 month) produces fee 0. | `Engagement_Penalty__mdt` |
| BR-08.6 | **Waiver requires justification.** `Goodwill_Waiver__c = TRUE` without `Goodwill_Justification__c` is rejected. | Validation rule |
| BR-08.7 | **Cancelled and Superseded are terminal.** Records are soft-closed, never hard-deleted — they are financial history. | State machine + no-delete permission |
| BR-08.8 | **Effective-date discipline.** Between request and effective date the line is `PendingCancellation` — service continues and remains visible in the 360° view. | State machine |
| BR-08.9 | If the commitment has already **expired**, fee = 0 and the engagement moves to `Expired`, not `Breached`. | Service logic |
| BR-08.10 | Duplicate in-flight cancellation requests against the same subscription are blocked (`Is_Compliant_Request__c`). | Computed condition |
| BR-08.11 | BSS de-provision failure must not leave the Salesforce record cancelled while the network still serves the line — rollback and retry via `Integration_Log__c`. | Transaction + reconciliation |

### 10.5 Hand-off

Churn analytics ← `Cancellation_Reason__c`; Finance ← `Breach_Amount__c`; win-back ← churned accounts (Process 11).

---

## 11. Process 09 — Renewal Management

### 11.1 Purpose

Convert the natural end of a commitment into a deliberate commercial event: renew, re-price, or let lapse — before the customer drifts away uncontacted.

### 11.2 Trigger

Scheduled daily job scans `Subscription__c.Next_Renewal_Date__c` (formula over `Billing_End_Date__c`) with a compound index.

### 11.3 Process flow

```
[Daily renewal scan]
      │
      ├─ T−60 days ──► Outreach task #1 (if Renewal_Contacted__c = false)
      ├─ T−30 days ──► Outreach task #2 + renewal offer prepared
      ├─ T−7  days ──► Final outreach + escalation to advisor queue
      │
      ▼
[Customer decision]
      ├─ Renew (same terms)   ──► Contract Auto_Renew path; engagement extended
      ├─ Renew (new plan)     ──► Process 06 (Plan Change) with renewal context
      ├─ Do nothing           ──► Engagement → Expired; subscription →
      │                            rolling / churn per policy
      └─ Cancel early         ──► Process 08
      │
      ▼
[Renewal_Contacted__c = TRUE, Renewal_Contacted_On__c stamped]
   (idempotency guard — the daily job cannot re-contact the same customer)
```

### 11.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-09.1 | **No duplicate outreach.** `Renewal_Contacted__c` guards against the daily job re-creating tasks. | Checkbox + job filter |
| BR-09.2 | Renewal campaigns never contact a customer with `Do_Not_Call__c` by phone. | DNC filter |
| BR-09.3 | `Months_Remaining__c` and `Is_Committed__c` are **formulas**, never stored — a stored value drifts the moment a date changes and produces wrong renewal and penalty decisions. | Formula fields |
| BR-09.4 | An expired engagement is terminal (`Expired`); the renewal creates a **new** engagement, it does not resurrect the old one. | State machine |
| BR-09.5 | Renewal offers use the same server-side pricing path as new sales — no separate renewal price list logic. | RCA Pricing API |

---

## 12. Process 10 — Self-Service Portal

### 12.1 Purpose

Let customers perform high-volume, low-complexity actions without an advisor, while pushing the same requests into the same governed back-office processes.

### 12.2 The three experiences

| # | Experience | Read/Write | Underlying objects | Process entered |
|---|---|---|---|---|
| 1 | **My Subscriptions** | Read-mostly | `Subscription__c`, `Asset` via LDS | — (browse) |
| 2 | **Track My Requests** | Read | `Customer_Request__c`, `Quote`, `Order`, `Case` | — (monitor) |
| 3 | **Submit a Request** | Write | Creates `Customer_Request__c` + `Case` | Process 06 / 08 |

### 12.3 Portal request flow

```
[Authenticated customer]
      │
      ▼
Select request type (Plan Change | Cancellation | Suspension | Info)
      │
      ▼
Form (LDS + Screen Flow — no portal Apex controllers)
      ├─ AccountId derived SERVER-SIDE from the authenticated user
      │    ── never accepted from the client  (IDOR defence)
      ├─ Subscription picker scoped to the customer's own Account
      ├─ Cancellation: reason + effective date (≥ 30 days)
      └─ Comment captured
      │
      ▼
Customer_Request__c (Channel = Portal) + Case created
      │
      ▼
Same back-office processes as advisor-initiated requests
      │
      ▼
[Track My Requests shows live status]
```

### 12.4 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-10.1 | **A portal request is never a different process.** It lands in exactly the same queue, with the same rules, as an advisor request — only `Channel__c` differs (for portal-vs-advisor reporting). | Single intake |
| BR-10.2 | **Customers cannot see each other.** A query for another account's subscriptions returns zero rows. | Server-side account derivation + explicit test |
| BR-10.3 | **Customers cannot set fees.** `Calculated_Fee__c` is read-only on the portal; the displayed value is the server's. | FLS |
| BR-10.4 | **Customers cannot approve.** `Approved_By__c`, `Goodwill_Waiver__c` and override fields are inaccessible to `ats_PortalUser`. | FLS matrix |
| BR-10.5 | Guest lead capture is rate-limited / reCAPTCHA-protected. | Flow |
| BR-10.6 | Portal pricing is the identical server-side RCA price — an advisor and a customer see the same number. | Single pricing path |
| BR-10.7 | `Info` requests create no Case — the one documented exception to the traceability guarantee. | Conditional case requirement |

---

## 13. Process 11 — The Advisor 360° Cockpit (Continuous Process)

### 13.1 Purpose

Give advisors one screen from which every process above can be launched with full context — the operational home of A3 and A4.

### 13.2 Zones and the actions they trigger

| Zone | Content | Actions launched |
|---|---|---|
| **Customer Information** | Identity, segment, status badge, active line count | Edit profile |
| **Subscriptions** | Lines with status pill, plan, monthly price | **Subscribe** → Process 03; **Unsubscribe** → Process 08 (via request) |
| **Subscriptions & Hardware** | Assets with image, serial, status | Equipment swap → Process 07 |
| **Interactions** | Cases, opportunities, quotes, orders timeline | Open any historical request |
| **External API** | Weather / contextual data card | Demonstrates the integration pattern |

### 13.3 Business rules

| # | Rule | Enforcement |
|---|---|---|
| BR-11.1 | The status badge (`Subscribed / Prospect / Suspended / Churned`) is **computed from live data**, never a stored flag that can drift. | Formula / derived |
| BR-11.2 | While an in-flight cancellation request exists against a line, the Unsubscribe action is **disabled with a reason shown** — not silently hidden. | `Is_Compliant_Request__c` hint |
| BR-11.3 | Every action launched from the cockpit inherits the customer context — the advisor never re-selects the account. | Component state |
| BR-11.4 | The cockpit is the largest bespoke artefact; each zone is a separate component so a change in one does not destabilise the others. | Architecture §8.1 |

---

## 14. Cross-Cutting Business Rules

Consolidated register. Each rule names its single enforcement point.

| # | Rule | Enforced by | Owner |
|---|---|---|---|
| **X1** | No service state changes outside a `Customer_Request__c` + `Case` | UI/permissions + Flow intake | Sales Ops |
| **X2** | Price is computed once, server-side, by RCA — never by any client | `CatalogQueryService` | Pricing Admin |
| **X3** | Commitment variants are product options, not products | Catalogue design | Pricing Admin |
| **X4** | Penalty amounts are reproducible from inception snapshots | Snapshot policy | Finance |
| **X5** | Commitment state is derived (formula), never stored | Formula fields | Solution Architect |
| **X6** | Every cross-object write passes through a domain service | Architecture rule | Solution Architect |
| **X7** | Financial records are soft-closed, never deleted | Permission sets (no delete) | Solution Architect |
| **X8** | Status transitions obey the state machine from every DML path | Trigger handler | Solution Architect |
| **X9** | Cancellation reason + 30-day notice are non-bypassable | Validation rules | Sales Ops |
| **X10** | Fees above threshold require manager approval | Flow approval gate | Finance |
| **X11** | Consent precedes marketing; DNC suppresses outbound call | Flow conditions | Compliance |
| **X12** | Portal identity is derived server-side, never client-supplied | Apex / LDS security | Solution Architect |
| **X13** | Every external callout is idempotent and logged with a correlation ID | `Integration_Log__c` | Ops |
| **X14** | Eligibility must be confirmed before a fibre promise | `EligibilityService` | Network |
| **X15** | PII is never written to logs, metadata, or payload fields | Logging policy | Compliance |

---

## 15. Service Level Agreements

| # | Process step | Audience | Target | Measurement |
|---|---|---|---|---|
| SLA-1 | Lead response after qualification | Prospect | ≤ 4 business hours | Lead convert time |
| SLA-2 | Quote production (wizard completion) | Customer | ≤ 15 minutes assisted | Wizard session duration |
| SLA-3 | **Activation after order acceptance** | Customer | **≤ 4 hours** (fibre: ≤ earliest activation date) | Order → Activated |
| SLA-4 | Cancellation fee quote after request | Customer | ≤ 1 business hour | Request → `Fee_Quoted` |
| SLA-5 | Cancellation approval (threshold cases) | Customer | ≤ 1 business day | `Awaiting_Approval` → `Approved` |
| SLA-6 | Plan-change fulfilment | Customer | ≤ 1 business day | Request → `Completed` |
| SLA-7 | Portal request acknowledgement | Customer | Immediate | Case auto-response |
| SLA-8 | BSS reconciliation discrepancy resolution | Internal | ≤ 1 business day | Reconciliation batch findings |
| SLA-9 | Failed callout retry / dead-letter triage | Internal | ≤ 4 hours | `Integration_Log__c` status |
| SLA-10 | Renewal outreach at T−60 | Customer | On schedule | `Renewal_Contacted__c` |

> SLA-3 is the one the customer actually feels. Everything else is internal hygiene.

---

## 16. Key Performance Indicators

### 16.1 Commercial

| KPI | Definition | Source | Target |
|---|---|---|---|
| Activation conversion | Activated orders ÷ accepted quotes | `Order`, `Quote` | ≥ 90% |
| Average time to activate | Order accepted → Active subscription | `Order.Activated_On__c` | ≤ 4 h |
| Bundle attach rate | Quotes containing plan + device ÷ all quotes | `QuoteLineItem` | ≥ 40% |
| Commitment mix | Share of new subscriptions with 12/24-month engagement | `Engagement__c` | ≥ 60% |
| Average revenue per user | Sum `Subscription__c.Monthly_Amount__c` ÷ active lines | `Subscription__c` | Trend |
| Channel mix | Requests by `Channel__c` (Portal vs Advisor) | `Customer_Request__c` | Portal ≥ 50% |

### 16.2 Retention

| KPI | Definition | Source | Target |
|---|---|---|---|
| Churn rate | Cancellations in period ÷ active lines at start | `Subscription__c.Status__c` | ≤ monthly target |
| Churn reason distribution | Count by `Cancellation_Reason__c` | `Customer_Request__c` | Monitored |
| Penalty revenue | Sum `Breach_Amount__c` where engagement `Breached` | `Engagement__c` | Monitored |
| Renewal contact coverage | Engagements contacted before expiry ÷ expiring | `Renewal_Contacted__c` | 100% |
| Early churn (within 6 months) | Cancellations where `Months_Remaining > 0` and age < 6 mo | `Engagement__c` | ≤ target |

### 16.3 Operational

| KPI | Definition | Source | Target |
|---|---|---|---|
| Activation success rate | First-attempt successes ÷ activation attempts | `Integration_Log__c` | ≥ 99.5% |
| Idempotency incidents | Duplicate subscriptions detected | Reconciliation | 0 |
| Reconciliation drift | Subscriptions where `External_Status__c` ≠ Salesforce status | Nightly batch | 0 unresolved > 1 day |
| Portal request completion time | Submitted → Completed | `Customer_Request__c` | Per SLA-6 |
| Approval backlog | Requests in `Awaiting_Approval` > 1 day | `Customer_Request__c` | 0 |
| Pricing defect escape | Pricing discrepancies found after release | Test suite | 0 |

---

## 17. Exception & Failure Handling

| # | Failure | Business consequence | Handling | Owner |
|---|---|---|---|---|
| E1 | **BSS callout fails during activation** | Customer believes they have service but network is not provisioned | Full Salesforce rollback; order returns to `Ready`; customer notified of delay; `Integration_Log__c = Failure` | Ops |
| E2 | **Activation partial by bug** | Orphan asset or double subscription | Idempotency guard prevents recurrence; reconciliation batch detects and reports drift | Ops |
| E3 | **Double-clicked activate** | Double billing | `Activation_State__c` guard; second attempt is a no-op | System |
| E4 | **Eligibility data stale** | Fibre promised where unavailable | `Last_Synced_On__c` staleness monitor; network batch refresh; restriction text shown verbatim | Network |
| E5 | **Pricing decision table not activated** | Silent wrong prices, no error | Activation is an explicit release-runbook step; pricing test asserts numbers every deployment | Pricing Admin |
| E6 | **Catalogue change after a quote is issued** | Divergent price on re-render | Quote line snapshots the commitment option; signed quotes are immutable | Pricing Admin |
| E7 | **Customer cancels and network does not de-provision** | Service continues, no revenue | Rollback on callout failure; nightly reconciliation retries; never a one-way Salesforce-only cancel | Ops |
| E8 | **Portal user attempts cross-account access** | Data breach | Server-side account derivation; zero-row guarantee tested explicitly | Security |
| E9 | **Penalty metadata row missing** | Exception on cancellation | Default rule applied, never an exception surfaced to the customer | System |
| E10 | **Fee dispute by customer** | Complaint / regulatory exposure | `Fee_Breakdown__c` gives plain-language justification; snapshots make the figure reproducible | Service Agent |
| E11 | **Wizard session lost mid-journey** | Advisor must restart, customer waits | `Subscription_Wizard_State__c` resumes at the last step | System |
| E12 | **BSS feature flag off (network incident)** | New sales cannot be provisioned | Activation held in `Ready`, surfaced to ops, customers told honestly; no silent skip | Ops |
| E13 | **Renewal outreach not sent** | Silent churn at term end | `Renewal_Contacted__c` coverage KPI reviewed daily | Sales Ops |
| E14 | **Duplicate request against same line** | Conflicting instructions to the network | `Is_Compliant_Request__c` suppresses duplicate actions | System |

---

## 18. RACI Matrix

**R** = Responsible · **A** = Accountable · **C** = Consulted · **I** = Informed

| Process | Prospect | Customer | Advisor | Service Agent | Manager | Ops Admin | Pricing Admin | Finance |
|---|---|---|---|---|---|---|---|---|
| 01 Lead acquisition | R | I | C | — | I | — | — | — |
| 02 Qualification & eligibility | I | C | R | C | I | C | — | — |
| 03 Quotation | I | R | R | I | I | — | C | — |
| 04 Order & contract | I | A | R | — | C | — | — | C |
| 05 Activation | I | I | R | — | I | R | — | — |
| 06 Plan change | — | R | R | C | A (if fee) | — | C | C |
| 07 Suspend / swap / port | — | C | R | R | I | C | — | — |
| 08 Cancellation | — | R | R | R | **A** (approval) | C | — | C (penalty policy) |
| 09 Renewal | — | R | R | I | A | — | C | C |
| 10 Portal self-service | — | R | I | A | I | — | — | — |
| 11 360° cockpit | — | — | R | R | A | — | — | — |
| Catalogue & pricing config | — | — | I | I | — | C | **A/R** | C |
| Reconciliation & incident | — | — | I | I | — | **A/R** | — | I |
| Penalty policy definition | — | — | C | C | C | — | — | **A/R** |

---

## 19. Open Business Questions

These block or shape the processes above. They are the business-side counterparts to Q1–Q4 in `ARCHITECTURE.md`.

| # | Question | Process affected | Owner | Blocking |
|---|---|---|---|---|
| **BQ1** | Is a plan change an **amendment** of the existing contract or a **new contract**? | 06 | Finance + Sales Ops | **Phase 1.** Determines commitment clock restart and revenue treatment |
| **BQ2** | Is the 30-day cancellation notice correct for **all** product categories and segments? | 08 | Commercial | Notice-period validation rule |
| **BQ3** | Does a suspension **pause** the commitment clock or let it run? | 07 | Commercial + Finance | Engagement handling on suspend |
| **BQ4** | Do expired commitments roll automatically, lapse, or trigger a re-price? | 09 | Commercial | Renewal fulfilment path |
| **BQ5** | Is there a restocking fee on device returns, separate from the engagement penalty? | 07 / 08 | Commercial | May need a second fee line |
| **BQ6** | Are consumers and businesses priced from the same pricebook? | 03 / 06 | Commercial | Pricebook topology |
| **BQ7** | Do invoicing and revenue recognition live in Salesforce? | 05 / 08 | Finance | Whether billing is in scope at all |
| **BQ8** | What is the source of truth for fibre eligibility, and how fresh must it be? | 02 | Network | Eligibility sync SLA |
| **BQ9** | Is the goodwill waiver threshold the same as the approval threshold, or lower? | 08 | Finance | Approval routing |
| **BQ10** | Is `MSISDN` unique globally or per account? | 07 | Commercial | **Resolved 2026-11-06 — globally unique.** Duplicate rule scope is org-wide. |
| **BQ11** | What is the penalty-free window for **device** commitments specifically? | 08 | Commercial | `Engagement_Penalty__mdt` seed |
| **BQ12** | Is `Account.Customer_Status__c = Churned` set when *any* line cancels or only when the *last* line cancels? | 08 | Sales Ops | Status derivation rule |

---

## 20. Process → System Traceability

| Process | Primary objects | Primary services / automation |
|---|---|---|
| 01 Acquisition | `Lead`, `Account`, `Contact`, `Opportunity` | `LeadImportService`, conversion Flow |
| 02 Eligibility | `Eligibility__c`, `Opportunity` | `EligibilityService` |
| 03 Quotation | `Quote`, `QuoteLineItem`, `Subscription_Wizard_State__c` | `CatalogQueryService`, RCA Pricing API, `OfferBuilderService` |
| 04 Order | `Contract`, `ContractLineItem`, `Order`, `OrderItem` | `OfferBuilderService` |
| 05 Activation | `Order`, `Asset`, `Subscription__c`, `Engagement__c`, `Integration_Log__c` | `ActivationService`, activation Flow, BSS callout |
| 06 Plan change | `Customer_Request__c`, `Subscription__c`, `Quote` | Plan-change Flow + `OfferBuilderService` |
| 07 Suspend/swap/port | `Customer_Request__c`, `Subscription__c`, `Asset` | Lifecycle Flows + BSS callout |
| 08 Cancellation | `Customer_Request__c`, `Engagement__c`, `Contract`, `Asset` | Cancellation Flow + `EngagementPenaltyService` |
| 09 Renewal | `Subscription__c`, `Engagement__c`, `Contract` | Scheduled Flow + outreach tasks |
| 10 Portal | `Customer_Request__c`, `Case` | LDS, Screen Flow, secured thin Apex |
| 11 Cockpit | All | `customer360Shell` LWC |

---

## 21. Case Study Coverage Map

| Case study section | Business process here |
|---|---|
| §1 Modernize to grow | Value chain (§2) + KPIs (§16) |
| §2 Unified advisor cockpit | Process 11 (§13) |
| §3 Hybrid data model | Underpins all processes — see `DATA_MODEL.md` |
| §4 Product catalog and rules | Process 03 (§5) + cross-cutting X2/X3 |
| §5 Digitalize acquisition | Process 01 (§3) |
| §6 360° customer view | Process 11 (§13) |
| §7 Five-step guided journey | Process 03 (§5.3) |
| §8 Quote to active service | Processes 04 + 05 (§6, §7) |
| §9 Experience Cloud portal | Process 10 (§12) |
| §10 Plan change and cancellation | Processes 06 + 08 (§8, §10) |
| §11 Unified platform | Single intake for all requests (X1) |
| §12 Best practices | Cross-cutting rules (§14) + exceptions (§17) |

---

## 22. Business Process Definition of Done

- [ ] Every process above has a named business owner from §1.2
- [ ] BQ1 (plan-change semantics) resolved with Finance before Phase 1
- [ ] BQ2 (notice period) resolved before the cancellation validation rule is built
- [ ] Penalty matrix seeds agreed with Finance and signed off
- [ ] SLA targets in §15 agreed with Operations, not just assumed
- [ ] KPI definitions in §16 agreed with the reporting owner
- [ ] Every rule in §14 has exactly one enforcement point, verified in the build
- [ ] Every failure path in §17 has been tested, not just designed
- [ ] RACI in §18 confirmed by the process owners
- [ ] Portal and advisor produce identical eligibility and pricing results for identical inputs
