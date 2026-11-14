# E3 — Acquisition (Phase 3)

**Objective:** digitalize lead capture from three channels into one deduplicated, consented, scored lead that converts idempotently into a customer.
**Exit gate:** *Lead `Ready` → Account + Contact + Opportunity, idempotently* (`ARCHITECTURE.md` §13).
**Source:** `BUSINESS_PROCESS.md` §3 (Process 01); `ARCHITECTURE.md` §7.2, §8.3; `DATA_MODEL.md` §10.1–10.4.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-ACQ-01 | `LeadImportService` — bulk lead import | Must | Salesforce Developer (Apex) | 🔲 |
| UC-ACQ-02 | Bulk import home-page LWC | Should | Front-end Developer (LWC) | 🔲 |
| UC-ACQ-03 | Portal contact form (guest, rate-limited) | Must | Front-end Developer (LWC) + Admin | 🔲 |
| UC-ACQ-04 | Dedupe, consent stamping, and scoring | Must | Salesforce Developer | 🔲 |
| UC-ACQ-05 | Lead conversion Flow (Ready → Account/Contact/Opportunity) | Must | Salesforce Admin (Flow) | 🔲 |

---

### UC-ACQ-01 — `LeadImportService` — bulk lead import

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 3 |
| Actor(s) | A1, A10 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-DM-10, UC-DM-12 |
| Blocks | UC-ACQ-02, UC-ACQ-04 |
| Business process | 01 |
| Architecture ref | §7.2 #1 |
| Data model ref | §10.3 |
| Status | 🔲 Not started |

**Goal.** Ingest campaign lists of thousands of prospects safely — a volume Flow cannot handle within DML limits.

**Preconditions** — `Lead` extensions deployed; `ats_IntegrationUser` set exists.

**Main flow**
1. Implement `LeadImportService` as an Apex REST service using the **Bulk API**.
2. Process in batch chunks; remain bulk-safe (no per-row SOQL/DML).
3. Stamp `Duplicate_Checked__c` and `Consent_Given__c` (delegated to UC-ACQ-04).
4. Enforce `WITH USER_MODE` and `Security.stripInaccessible` on externally supplied fields.

**Alternate / exception flows**
- E1: List exceeds limits → chunk and re-queue; never partial-commit silently.
- E2: Malformed rows → reject with row-level error, continue processing the batch.

**Business rules**

| Rule | Source |
|---|---|
| Bulk conversion must handle 10,000+ without governor breach | BR-01.6 |
| Consent before marketing | BR-01.1, X11 |
| Mass assignment protection on external field maps | `ARCHITECTURE.md` §10 |

**Acceptance criteria**
- [ ] Imports 10,000+ leads in one submission without limit breach.
- [ ] No PII written to logs.
- [ ] Idempotent on re-run when keyed by source row.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | 10,000-row file | Import | Completes within limits |
| TS-2 | Same file twice | Import again | No duplicate leads (per BR-01.4 keying) |

**Definition of done**
- [ ] ≥80% coverage; bulk test evidenced.

**Open questions / risks** — none.

---

### UC-ACQ-02 — Bulk import home-page LWC

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 3 |
| Actor(s) | A10, A6 |
| Suggested owner | Front-end Developer (LWC) |
| Depends on | UC-ACQ-01 |
| Blocks | — |
| Business process | 01 |
| Architecture ref | §7.2 #1 |
| Data model ref | §10.3 |
| Status | 🔲 Not started |

**Goal.** Give marketing/admin a home-page component to submit a campaign file to `LeadImportService`.

**Preconditions** — UC-ACQ-01 deployed.

**Main flow**
1. Build a home-page LWC: file input, client-side validation, submit to the Apex REST service.
2. Show a progress/result summary (accepted, rejected, duplicates flagged).
3. Never call a third party directly from the component.

**Alternate / exception flows**
- E1: Oversized file → reject client-side with a clear message before submission.

**Business rules**

| Rule | Source |
|---|---|
| Flow cannot exceed DML limits — this is inherently bulk | §7.2 #1 |

**Acceptance criteria**
- [ ] File submits and returns a per-row result summary.
- [ ] Jest tests cover component logic (no Apex in jest).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Valid CSV | Submit | Summary shows counts |

**Definition of done**
- [ ] Jest tests pass; no live callouts from the component.

**Open questions / risks** — none.

---

### UC-ACQ-03 — Portal contact form (guest, rate-limited)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 3 |
| Actor(s) | A1 |
| Suggested owner | Front-end Developer (LWC) + Admin |
| Depends on | UC-DM-10, UC-ACQ-04 |
| Blocks | E7 guest capture |
| Business process | 01 |
| Architecture ref | §7.2 #2, §8.3 |
| Data model ref | §10.3 |
| Status | 🔲 Not started |

**Goal.** Capture prospect interest from the public site with declarative validation, consent recording, and abuse protection.

**Preconditions** — Experience Cloud site (E7) or a temporary guest page.

**Main flow**
1. Build a Screen Flow form → create `Lead` with `Status = New`.
2. Add reCAPTCHA or a Flow-based rate limit for guest users.
3. Record consent **timestamp and source** (`Consent_Given__c`, `Lead_Source_Detail__c = PortalForm`).

**Alternate / exception flows**
- E1: Bot/spam submission → reCAPTCHA/rate limit rejects; no Lead created.

**Business rules**

| Rule | Source |
|---|---|
| Consent recorded, not assumed | BR-01.5 |
| Guest lead capture is rate-limited / reCAPTCHA-protected | BR-10.5 |

**Acceptance criteria**
- [ ] Form creates a Lead with consent timestamp and source.
- [ ] Abuse protection active and tested.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Guest submits form | Save | Lead + consent recorded |
| TS-2 | Rapid repeat submissions | Submit | Rate limit blocks |

**Definition of done**
- [ ] Deployed to site; consent fields populated.

**Open questions / risks** — none.

---

### UC-ACQ-04 — Dedupe, consent stamping, and scoring

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 3 |
| Actor(s) | A10, A3 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-ACQ-01 |
| Blocks | UC-ACQ-05 |
| Business process | 01 |
| Architecture ref | §7.2 #1 |
| Data model ref | §10.3 |
| Status | 🔲 Not started |

**Goal.** Ensure leads are deduplicated and scored before an advisor spends time on them.

**Preconditions** — `Lead` fields deployed.

**Main flow**
1. Implement dedupe on name + postal code + phone; **flag**, do not auto-merge (BR-01.3).
2. Stamp `Duplicate_Checked__c`.
3. Compute `Convert_Score__c` (0–100) from configurable signals.
4. Stamp consent fields from the intake channel.

**Alternate / exception flows**
- E1: Exact duplicate of an existing customer → flag for advisor review, no silent merge.

**Business rules**

| Rule | Source |
|---|---|
| Dedupe before create; flag, do not auto-merge | BR-01.3 |
| Consent before marketing sync | BR-01.1 |

**Acceptance criteria**
- [ ] Duplicates flagged with `Duplicate_Checked__c` true.
- [ ] Score populated for every imported lead.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Two leads, same name+postcode+phone | Import | Second flagged, not merged |

**Definition of done**
- [ ] Dedupe proven; scoring deterministic in tests.

**Open questions / risks** — none.

---

### UC-ACQ-05 — Lead conversion Flow (Ready → Account/Contact/Opportunity)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 3 |
| Actor(s) | A3 |
| Suggested owner | Salesforce Admin (Flow) |
| Depends on | UC-ACQ-04, UC-DM-10 |
| Blocks | E5 (wizard starts from a converted Account) |
| Business process | 01 |
| Architecture ref | §7.2 #3 |
| Data model ref | §10.1–10.4 |
| Status | 🔲 Not started |

**Goal.** Convert a `Ready` lead into the three independent records that begin the sales journey — idempotently.

**Preconditions** — Person Account model enabled (D4); `Lead` fields present.

**Main flow**
1. Trigger on `Lead.Status = 'Ready'`.
2. Create `Account` (Person Account) with `Segment__c`, `Legacy_Customer_Id__c`, `Customer_Status__c = Prospect`.
3. Create `Contact` (DNC flag, preferred method, primary).
4. Create `Opportunity` with `Journey_Step__c = Capture`, `Portal_Source__c` as appropriate.
5. Guard against re-run: upsert on `Legacy_Customer_Id__c` so no second Account is produced.

**Alternate / exception flows**
- A1: Insufficient data → disqualify with a recorded reason; no conversion.
- E1: Re-run conversion → no duplicate Account (BR-01.4).

**Business rules**

| Rule | Source |
|---|---|
| Conversion is idempotent | BR-01.4 |
| DNC is global and suppresses outbound call tasks | BR-01.2, X11 |
| Conversion touches 3 independent records, no rollback → Flow is correct | §7.2 #3 |

**Acceptance criteria**
- [ ] `Ready` produces exactly one Account + Contact + Opportunity.
- [ ] Re-running produces no duplicates.
- [ ] `Do_Not_Call__c` set on the Contact and honoured downstream.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Lead status Ready | Save | 3 records created |
| TS-2 | Same lead re-triggered | Save again | Zero new Accounts |
| TS-3 | DNC lead | Outbound task creation | Suppressed |

**Definition of done**
- [ ] Flow tested in a scratch org; idempotency evidenced.

**Open questions / risks** — D4/R12 B2C vs B2B affects the contact/authority model.
