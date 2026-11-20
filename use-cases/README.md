# ATS Telecom — Use Case Backlog

**Status:** Draft for team execution
**Companion documents:** [`ARCHITECTURE.md`](../ARCHITECTURE.md) · [`BUSINESS_PROCESS.md`](../BUSINESS_PROCESS.md) · [`DATA_MODEL.md`](../DATA_MODEL.md)
**Date:** 2026-10-13

> This backlog turns the approved design into assignable, testable units of work. Every use case cites the architecture, business-process, and data-model sections it implements, so a developer never has to re-derive the design and a reviewer can verify coverage against the source documents.

---

## 1. How to use this backlog

1. Pick an epic file under `use-cases/`. Epics map **1:1 to the build sequence** in `ARCHITECTURE.md` §13 (Phase 0 → Phase 10).
2. Each use case is a card with a stable ID (`UC-<EPIC>-<nn>`). Use that ID in branch names, DevOps Center work items, and test classes.
3. A card may only be started when its **Definition of Ready** is met (§6) and is only closed when its **Definition of Done** is met (§7).
4. **Do not skip phases out of order.** Phases 1–2 are the critical path (`ARCHITECTURE.md` §13): the data model and the catalogue are expensive to change later.
5. Blocking questions are tracked in §8. A card that depends on an unresolved question is marked **Blocked** and must not be built on an assumption.

## 2. ID scheme and conventions

| Element | Convention | Example |
|---|---|---|
| Use case ID | `UC-<EPIC>-<nn>` | `UC-DM-03` |
| Stories / tests inside a card | `AC-n` (acceptance), `TS-n` (test scenario) | `AC-2`, `TS-4` |
| Business rules | As defined in `BUSINESS_PROCESS.md` (`BR-xx.y`) and cross-cutting (`X1`–`X15`) | `BR-05.1`, `X8` |
| Architecture references | `ARCHITECTURE.md` section | `§7.3`, `§12` |
| Data model references | `DATA_MODEL.md` section | `§4.2`, `§11.2` |
| Environment names | `ats-dev`, `ats-int`, `ats-uat`, `ats-prod` | `ARCHITECTURE.md` §11.1 |

## 3. Card template

Every use case in an epic file follows this shape:

```
### UC-XXX-nn — Title

| Field | Value |
|---|---|
| Priority | Must / Should / Could |
| Phase | 0–10 |
| Actor(s) | A1–A10 |
| Suggested owner | role |
| Depends on | UC-... |
| Blocks | UC-... |
| Business process | Process nn — name |
| Architecture ref | §… |
| Data model ref | §… |
| Status | Not started / In progress / Blocked / In review / Done |

**Goal.** …
**Preconditions** — …
**Main flow** — numbered steps
**Alternate / exception flows** — A1, E1 …
**Business rules** — table of rule → source
**Acceptance criteria** — checklist
**Test scenarios** — G/W/T table
**Definition of done** — checklist
**Open questions / risks** — …
```

## 4. Actor reference (`BUSINESS_PROCESS.md` §1.2)

| ID | Actor | Primary surface |
|---|---|---|
| A1 | Prospect | Portal lead form, bulk import |
| A2 | Customer (self-service) | Experience Cloud portal |
| A3 | Advisor (Sales) | Advisor Console — 360° + wizard |
| A4 | Service Agent | Advisor Console — service zones, Case |
| A5 | Advisor Manager | Approval console |
| A6 | Operations Admin | Setup + Ops permission set |
| A7 | Pricing Admin | Revenue Cloud setup |
| A8 | Finance | Policy owner |
| A9 | Network / BSS | External provisioning boundary |
| A10 | Marketing | Marketing Cloud |

## 5. Epic index

| Epic | File | Phase | Use cases | Primary deliverable | Exit gate (`ARCHITECTURE.md` §13) |
|---|---|---|---|---|---|
| **E0 — Foundation** | [`EPIC-00-foundation.md`](./EPIC-00-foundation.md) | 0 | 7 | Org, repo, RCA enabled, CI/CD, scaffolding | Metadata deploys cleanly to an empty org |
| **E1 — Data Model** | [`EPIC-01-data-model.md`](./EPIC-01-data-model.md) | 1 | 14 | 6 custom objects, metadata, validation, FLS, seeds | Deploy succeeds; seeds load idempotently |
| **E2 — Catalog & Pricing** | [`EPIC-02-catalog-pricing.md`](./EPIC-02-catalog-pricing.md) | 2 | 9 | RCA catalogue, selling models, adjustments, pricing procedure | Committed 5 GB plan prices correctly; 30% device discount fires |
| **E3 — Acquisition** | [`EPIC-03-acquisition.md`](./EPIC-03-acquisition.md) | 3 | 5 | LeadImportService, portal form, conversion Flow | Lead `Ready` → Account + Contact + Opportunity, idempotently |
| **E4 — Commerce & Activation** | [`EPIC-04-commerce-activation.md`](./EPIC-04-commerce-activation.md) | 4 | 6 | OfferBuilderService, ActivationService, state machine | Quote → Order → activate atomically, safely twice |
| **E5 — Advisor Experience** | [`EPIC-05-advisor-experience.md`](./EPIC-05-advisor-experience.md) | 5 | 7 | customer360Shell, subscriptionWizard, CatalogQueryService | 5-step journey completes end-to-end from a blank Account |
| **E6 — Lifecycle** | [`EPIC-06-lifecycle.md`](./EPIC-06-lifecycle.md) | 6 | 8 | EngagementPenaltyService, plan-change & cancellation Flows | Both paths produce correct fees |
| **E7 — Self-Service Portal** | [`EPIC-07-portal.md`](./EPIC-07-portal.md) | 7 | 6 | Site, 3 experiences, request forms, security layer | Customer cancels; advisor sees it in the 360° view |
| **E8 — Integration** | [`EPIC-08-integration.md`](./EPIC-08-integration.md) | 8 | 7 | BSS callout, Integration_Log__c, platform events, image sync | Rollback verified against a deliberately failing endpoint |
| **E9 — Hardening & NFR** | [`EPIC-09-hardening-nfr.md`](./EPIC-09-hardening-nfr.md) | 9 | 8 | Test suite, FLS/IDOR review, translation, performance | All exit criteria met |
| **E10 — Billing *(conditional)*** | [`EPIC-10-billing-conditional.md`](./EPIC-10-billing-conditional.md) | 10 | 3 | Revenue Cloud Billing **if Q3 confirms** | Invoicing and revenue recognition reconciled |

**Total: 80 use cases.**

### Cross-cutting traceability

| Epic | Business processes | Key architecture sections | Key data-model sections |
|---|---|---|---|
| E0 | — | §3.3, §10, §11, §12 | §19, §16 |
| E1 | — | §5 | §3–§11, §13, §17, §19 |
| E2 | 03 | §6 | §10.5–10.6, §15 |
| E3 | 01 | §7.2, §8.3 | §10.1–10.4 |
| E4 | 04, 05 | §7.1–7.4, §9 | §10.7–10.10 |
| E5 | 03, 11 | §8.1–8.2 | §8, §10.5 |
| E6 | 06, 07, 08, 09 | §7.2, §7.4 | §4, §5, §9.1 |
| E7 | 10 | §8.3, §10 | §5, §17 |
| E8 | 05, 07, 08 | §9 | §7 |
| E9 | all | §12, §11.6, §10 | §14, §16, §17 |
| E10 | 05, 08 | §3.3, §13 | §18 (explicitly not modelled until Q3) |

## 6. Definition of Ready (DoR)

A card may enter a sprint only when **all** apply:

- [ ] Dependencies listed on the card are `Done`, or explicitly waived by the architect.
- [ ] Any blocking open question in §8 is resolved and the resolution is recorded on the card.
- [ ] The cited architecture, process, and data-model sections have been read by the implementer.
- [ ] Acceptance criteria are unambiguous and testable.
- [ ] Required org configuration / permissions exist (e.g. RCA enabled, permission set deployed).

## 7. Definition of Done (DoD)

A card is `Done` only when **all** apply (`ARCHITECTURE.md` §17):

- [ ] Deployed to `ats-int` via CI with no manual post-processing.
- [ ] Apex at ≥80% coverage for domain services, ≥75% org-wide; every test uses `SeeAllData=false`.
- [ ] Bulk-safety proven where the card touches DML (200-row test at minimum).
- [ ] Idempotency proven where the card re-runs (call twice, assert one result).
- [ ] FLS/CRUD enforced (`WITH USER_MODE` / `WITH SECURITY_ENFORCED`); no bare DML.
- [ ] Cross-object writes go through a domain service (`X6`); no Flow↔Trigger calls.
- [ ] Status changes obey the state machine (`X8`).
- [ ] No hardcoded URLs or keys — external endpoints via `External_Api__mdc`.
- [ ] No PII in logs, metadata, or payload fields (`X15`).
- [ ] Test scenarios in the card executed and evidenced.
- [ ] Documentation/config export updated (`pricing-export/` where applicable).

## 8. Open decisions register (blocking)

These must be resolved and recorded before dependent cards are built. Sources: `ARCHITECTURE.md` §0, `DATA_MODEL.md` §20, `BUSINESS_PROCESS.md` §19.

| ID | Question | Owner | Blocks use cases |
|---|---|---|---|
| **Q1 / BQ1** | **Resolved 2026-11-17 —** plan change amends the existing contract. | Finance + Sales Ops | `UC-LIF-02`, `UC-COM-05`, `UC-DM-04` unblocked. |
| **Q2** | Target org type & licensing (RCA Growth vs Advanced) | Project sponsor | `UC-FND-03`, all of E2/E4/E5 |
| **Q3 / BQ7** | Do invoicing & revenue recognition live in Salesforce? | Finance | Entire E10 |
| **Q4 / BQ8** | Source system for fibre eligibility data | Network team | `UC-DM-05`, `UC-LIF-01`, `UC-INT-06` |
| **BQ2 / Q5** | **Resolved 2026-11-18 —** 30-day notice applies to all products and segments. | Commercial | `UC-DM-10`, `UC-LIF-03` unblocked. |
| **BQ3** | **Resolved 2026-11-19 —** suspension does NOT pause the commitment clock; Contract and Engagement remain unchanged. | Commercial + Finance | `UC-LIF-04` unblocked. |
| **BQ4** | **Resolved 2026-11-17, implemented 2026-11-19 —** expired commitments roll over monthly through `RenewalService.LetLapse`. | Commercial | `UC-LIF-06` complete. |
| **BQ5 / Q7** | Restocking fee separate from engagement penalty? | Commercial | `UC-LIF-05`, `UC-LIF-03` |
| **BQ6 / Q3-DM** | Same pricebook for Consumer and Business? | Commercial | `UC-CAT-04` |
| **BQ9** | **Resolved 2026-11-17 —** goodwill waiver threshold equals the approval threshold. | Finance | `UC-LIF-03` unblocked. |
| **BQ10 / Q6** | **Resolved 2026-11-06 —** MSISDN is globally unique (not per account). | Commercial | `UC-DM-13` and `UC-LIF-07` unblocked. |
| **BQ11** | **Resolved 2026-11-17 —** 14-day device penalty-free window. | Commercial | `UC-DM-08`, `UC-LIF-01` unblocked. |
| **BQ12** | **Resolved 2026-11-18 —** set `Churned` only when the last active line cancels. | Sales Ops | `UC-LIF-03` unblocked. |
| **D4/R12** | B2C (Person Accounts) confirmed vs B2B | Project sponsor | `UC-DM-09`, `UC-POR-05` |

## 9. Cross-cutting rules quick reference

| Rule | Statement | Enforcement home |
|---|---|---|
| X1 | No service state change outside a `Customer_Request__c` + `Case` | E6/E7 intake |
| X2 | Price computed once, server-side, by RCA | E2/E4/E5 |
| X3 | Commitment variants are product options, not products | E2 |
| X4 | Penalties reproducible from inception snapshots | E6 |
| X5 | Commitment state is a formula, never stored | E1/E6 |
| X6 | Every cross-object write passes through a domain service | all epics |
| X7 | Financial records soft-closed, never deleted | E1/E6 |
| X8 | Status transitions obey the state machine from every DML path | E1/E4 |
| X9 | Cancellation reason + 30-day notice non-bypassable | E1/E6 |
| X10 | Fees above threshold require manager approval | E6 |
| X11 | Consent precedes marketing; DNC suppresses outbound | E3 |
| X12 | Portal identity derived server-side | E7 |
| X13 | Every external callout idempotent + logged with correlation ID | E8 |
| X14 | Eligibility confirmed before a fibre promise | E3/E5 |
| X15 | PII never written to logs/metadata/payloads | all epics |

## 10. Progress legend

| Symbol | Meaning |
|---|---|
| 🔲 | Not started |
| 🟡 | In progress |
| 🔴 | Blocked (open question or dependency) |
| 🔍 | In review |
| ✅ | Done |

> Update the per-card **Status** field and this legend as work progresses. The epic files are the single source of truth for execution state.
