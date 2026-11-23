# E8 — Integration (Phase 8)

**Objective:** make every external boundary idempotent, observable, and reversible — especially the BSS provisioning boundary that the activation transaction depends on.
**Exit gate:** ✅ *Rollback verified against a deliberately failing endpoint* (`ARCHITECTURE.md` §13) — see E8 slice 3 note below.
**Source:** `ARCHITECTURE.md` §9, §7.3; `BUSINESS_PROCESS.md` §7, §17; `DATA_MODEL.md` §7, §9.2.

> **E8 slice 3 (2026-11-21):** Added synthetic `External_Api__mdt.E8_Failure_Test` + `RemoteSiteSetting.Httpbin` and the `E8IntegrationSmoke` harness. A real HTTP 500 from `https://httpbin.org/status/500` produced `ExternalApiException`, 0 DML rows, 1 Publish Immediate DML, and a surviving `Failure`/`500` log row (`a04bm000009h713AAA`, correlation `2d669e93-b9ae-8be1-a130-cd8b90a932f3`). Deploy `0Afbm00000p9PzVCAU` (4/4); targeted test 1/1 (`707bm00001YK9kv`); full suite 236/236 (`707bm00001YK898`). No live gateway switched; no customer PII sent.

> **E8 slice 4 (2026-11-21):** Added `Service_Activated__e` with `PublishAfterCommit` and non-PII fields, `ServiceActivatedEventPublisher` called from `ActivationService`, and a bulk subscriber stub that writes a `ServiceActivatedEvent` audit row. Tests prove exactly one event on success and none on rollback. Deploy `0Afbm00000pFPbpCAG` (13/13); full suite 238/238 (`707bm00001Ya5Zt`).

> **E8 slice 5 (2026-11-22):** Added a flag-off real-gateway scaffold. `BSS_Provisioning_Live__c` defaults to `false`; `BssProvisioningGatewayFactory` keeps the simulated gateway as the default and exposes a tested seam for the real one. `RealBssProvisioningGateway` uses `ExternalApiService`, sends no account name/PII, and fails closed on blank responses. No Named Credential or secret is deployed until endpoint/auth details are supplied. Deploy `0Afbm00000pFgROCA0` (5/5); full suite 243/243 (`707bm00001YZ8qL`).

> **E8 slice 6 (2026-11-22):** Added a flag-off BSS status reconciliation batch (`BssReconciliationBatch` + scheduler), non-PII DTOs, a simulated gateway with drift overrides, and an unreachable real gateway behind `BSS_Status_Live__c=false`. The batch writes only `External_Status__c`/`Last_Sync_DateTime__c` and surfaces drift through rollback-safe audit events. Deploy `0Afbm00000pFnB7CAK` (12/12); full suite 248/248 (`707bm00001YasKL`).

> **E8 slice 7 (2026-11-22):** Added a flag-off `ProductImageSyncBatch` + scheduler. `Product_Image_Live__c` defaults to `false`; the batch writes only `Product2.Device_Image_URL__c` so runtime renders never call out. Placeholder `External_Api__mdt.Product_Image` uses `AuthType=None` with an 86400-second cache TTL. Deploy `0Afbm00000pFsvZCAS` (6/6), metadata correction `0Afbm00000pFjXKCA0` (7/7); full suite 252/252 (`707bm00001YaYf4`).

> **E8 slice 8 (2026-11-23):** Enabled CDC on the four custom objects plus `Asset` via legacy v41 metadata. Added a flag-off `CdcReportingService` and five change-event triggers with explicit non-PII allowlists, plus the `CDC` integration-log picklist value. No outbound Data Cloud/Power BI feed is configured. Deploy `0Afbm00000pFOZMCA4` (CDC enablement) and `0Afbm00000pG0GPCA0` (scaffold); targeted tests pass (`707bm00001YalHQ`), full suite 257/257 (`707bm00001Yovlk`).

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-INT-01 | BSS/OSS provisioning callout | Must | Salesforce Developer (Apex) | 🔶 Flag-off scaffold (slice 5) |
| UC-INT-02 | `Integration_Log__c` logging and correlation framework | Must | Salesforce Developer | 🔶 Slice 1 complete |
| UC-INT-03 | Platform events (post-commit outbox) | Must | Salesforce Developer | ✅ Complete (slices 2 + 4) |
| UC-INT-04 | BSS status reconciliation batch | Must | Salesforce Developer | 🔶 Flag-off scaffold (slice 6) |
| UC-INT-05 | Product image sync | Should | Salesforce Developer | 🔶 Flag-off scaffold (slice 7) |
| UC-INT-06 | `ExternalApiService` + `External_Api__mdc` framework | Must | Salesforce Developer | 🔶 Slice 1 complete |
| UC-INT-07 | Reporting / BI feed (Change Data Capture) | Should | Integration Developer | 🔶 Flag-off scaffold (slice 8) |

---

### UC-INT-01 — BSS/OSS provisioning callout

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 8 |
| Actor(s) | A9 |
| Suggested owner | Salesforce Developer (Apex) |
| Depends on | UC-COM-03, UC-INT-06 |
| Blocks | E8 exit gate |
| Business process | 05, 08 |
| Architecture ref | §9, §7.3 |
| Data model ref | §9.2 |
| Status | 🔶 Flag-off scaffold ready; live cutover blocked on endpoint/auth |

**Goal.** Provision and de-provision services over a Named Credential with an idempotency key, rolling back on failure.

**Preconditions** — `BSS_Provisioning` metadata row seeded; Named Credential registered.

> **Cutover note (E8 slice 5):** `RealBssProvisioningGateway` and `BssProvisioningGatewayFactory` exist but are unreachable while `BSS_Provisioning_Live__c = false`. Supply the `BSS_Api` Named Credential endpoint/auth and update `External_Api__mdt.Bss_Provisioning` before enabling the flag. The simulated gateway remains untouched.

**Main flow**
1. Implement provisioning/de-provisioning via `@future(callout=true)` or Batch Apex (the activation boundary).
2. Send idempotency key = `Subscription_Number__c` so a retry cannot duplicate provisioning.
3. On success, persist BSS identifiers (`External_Reference__c`, MSISDN).
4. On failure, raise a rollback-capable exception to `ActivationService`.
5. Never cache the provisioning response (`Cache_Ttl_Seconds__c = 0`).

**Alternate / exception flows**
- E1: HTTP 500 → full rollback; order returns to `Ready`; `Integration_Log__c = Failure` (E1).
- E2: Retry after timeout with the same idempotency key → no duplicate provisioning.
- E3: Feature flag off → activation held in `Ready` (never silently skipped).

**Business rules**

| Rule | Source |
|---|---|
| The activation boundary rolls back on failure | §9, BR-05.1 |
| Idempotent callout (idempotency key) | §7.3 |
| Provisioning callout must never be cached | §9.2 |

**Acceptance criteria**
- [ ] Success persists BSS IDs; failure rolls back everything.
- [ ] Retry with the same key does not duplicate provisioning.
- [ ] All callouts logged with a correlation ID.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Mock 200 | Provision | BSS IDs persisted |
| TS-2 | Mock 500 | Provision | Full rollback, order Ready |
| TS-3 | Same key twice | Retry | One provisioning |

**Definition of done**
- [ ] `HttpCalloutMock` covers every path including failure.

**Open questions / risks** — `R10` outbox + reconciliation.

---

### UC-INT-02 — `Integration_Log__c` logging and correlation framework

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 8 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-06 |
| Blocks | UC-INT-01, UC-INT-04 |
| Business process | 05, 07, 08 |
| Architecture ref | §5.7, §7.3 |
| Data model ref | §7 |
| Status | 🔶 Slice 1 complete (logging + correlation; payload files deferred) |

**Goal.** Give every transaction chain a shared `Correlation_Id__c` and log each step, so a failed callout is diagnosable and reconciliation is automated.

**Preconditions** — `Integration_Log__c` deployed.

**Main flow**
1. Create a logging utility generating a UUID correlation ID per transaction chain.
2. Log direction, system, operation, endpoint, status, status code, duration, retry count, idempotency key.
3. Store full payloads as a `ContentDocument` file (`Payload_Doc__c`) — never a text field.
4. Redact secrets; never log PII.
5. Restrict `Error_Stack__c` FLS to ops/integration users.

**Alternate / exception flows**
- E1: Logging failure must never roll back the business transaction — log defensively.

**Business rules**

| Rule | Source |
|---|---|
| Every activation traceable via one correlation ID | BR-05.7, X13 |
| PII never written to logs / payload fields | X15 |
| `Error_Stack__c` restricted | §7.3 |

**Acceptance criteria**
- [ ] All activation log lines share one correlation ID.
- [ ] Payloads are files, not fields.
- [ ] No PII/secrets in any log field.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Failed activation | Query logs | Same correlation ID across steps |

**Definition of done**
- [ ] Retention job (weekly, 13 months) confirmed active.

**Open questions / risks** — highest-volume object; retention mandatory.

> **E8 slice 1 (2026-11-21):** `IntegrationLogService` now generates 36-character correlation IDs via `IntegrationCorrelation`, normalises/truncates values to schema lengths, defaults unknown systems/statuses safely, and publishes rollback-safe audit events via `IntegrationLogService.publish()` (see UC-INT-03). `ExternalApiService` emits success and failure audit events after the callout, including status code, duration, idempotency key, and a non-PII payload summary. Full payload files via `ContentDocument` remain a later slice. Targeted suite: 10/10 (run `707bm00001YKU7b`).

---

### UC-INT-03 — Platform events (post-commit outbox)

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 8 |
| Actor(s) | A6, downstream |
| Suggested owner | Salesforce Developer |
| Depends on | UC-COM-03, UC-INT-02 |
| Blocks | downstream consumers |
| Business process | 05 |
| Architecture ref | §7.3, §9 |
| Data model ref | — |
| Status | ✅ Complete (audit outbox + post-commit activation event) |

**Goal.** Publish `ats.service.activated.v1` only **after commit**, so consumers never observe phantom state.

**Preconditions** — activation transaction final.

**Main flow**
1. Define the platform event `ats.service.activated.v1`.
2. Publish after commit (outside the transaction) — never inside.
3. Include the correlation ID and subscription reference for consumer dedupe.

**Alternate / exception flows**
- E1: Publish inside the transaction → consumers could act on rolled-back state; **rejected** (§7.3 outbox).

**Business rules**

| Rule | Source |
|---|---|
| Platform event published after commit, not inside | §7.3 |
| Service events are internal, post-commit | §9 |

**Acceptance criteria**
- [ ] Event fires only on committed activations.
- [ ] A rolled-back activation emits no event.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Failing activation | Roll back | No event published |
| TS-2 | Successful activation | Commit | Event published once |

**Definition of done**
- [ ] Event tested with a subscriber stub.

**Open questions / risks** — none.

> **E8 slice 2 (2026-11-21):** Added `Integration_Log_Event__e` (`PublishImmediately`, high volume) plus `IntegrationLogEventTrigger`/`IntegrationLogEventHandler`. `IntegrationLogService.publish()` now emits audit events that survive a business rollback; the handler bulk-inserts `Integration_Log__c` rows. `IntegrationLogServiceTest.failureLogSurvivesBusinessRollback` proves durability across an explicit `Database.rollback`. Deploy `0Afbm00000p9IRlCAM` (29/29), targeted suite 11/11 (run `707bm00001YL0sH`), full suite 235/235 (run `707bm00001YKV8b`). The activation-specific event is now delivered in slice 4 via `Service_Activated__e`.

---

### UC-INT-04 — BSS status reconciliation batch

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 8 |
| Actor(s) | A9, A6 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-INT-01, UC-INT-02 |
| Blocks | KPI: reconciliation drift = 0 |
| Business process | 05, 07, 08 |
| Architecture ref | §9 |
| Data model ref | §14.2 |
| Status | 🔶 Flag-off scaffold ready; live cutover blocked on endpoint/auth |

**Goal.** Nightly compare Salesforce state to the BSS and surface drift, retrying failed de-provisions.

**Preconditions** — BSS callouts live.

> **Cutover note (E8 slice 6):** `BssReconciliationBatch` and `BssReconciliationScheduler` are deployed and tested with a simulated gateway. `BSS_Status_Live__c` defaults to `false`, so `RealBssStatusReconciliationGateway` is unreachable until the `BSS_Api` endpoint/auth and `External_Api__mdt.Bss_Status` are supplied. The batch never changes `Status__c`; it only writes `External_Status__c`, `Last_Sync_DateTime__c`, and audit findings.

**Main flow**
1. Implement `BssReconciliationBatch` (nightly) comparing `Subscription__c` vs BSS.
2. Write `External_Status__c` and `Integration_Log__c` findings.
3. Retry failed de-provisions; escalate dead letters.
4. Flag any subscription where `External_Status__c ≠` Salesforce status.

**Alternate / exception flows**
- E1: Drift unresolvable automatically → surfaced to ops for triage within SLA-8 (≤1 business day).

**Business rules**

| Rule | Source |
|---|---|
| Nightly reconciliation drift target 0 | §16.3 |
| Discrepancy resolution ≤ 1 business day | SLA-8 |

**Acceptance criteria**
- [x] Batch detects a deliberately introduced drift (slice 6 simulated-drift test).
- [x] `External_Status__c` written only by the batch (slice 6 status-only write test).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Injected drift | Run batch | Drift reported |

**Definition of done**
- [ ] Scheduled and monitored; `R10` mitigation in place.

**Open questions / risks** — none.

---

### UC-INT-05 — Product image sync

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 8 |
| Actor(s) | A7 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-INT-06, UC-DM-10 |
| Blocks | UC-UX-04 images |
| Business process | 03 |
| Architecture ref | §7.2 #14, §9 |
| Data model ref | §10.5 |
| Status | 🔶 Flag-off scaffold ready; live image endpoint not supplied |

**Goal.** Cache device photography onto `Product2.Device_Image_URL__c` so the 360° and wizard never make a live callout per row.

**Preconditions** — `Product_Image` metadata row seeded.

> **Cutover note (E8 slice 7):** `ProductImageSyncBatch` and `ProductImageSyncScheduler` are deployed with `Product_Image_Live__c=false` by default. `External_Api__mdt.Product_Image` is a placeholder (`AuthType=None`, cache TTL 86400). Supply the real image endpoint before enabling the flag. Runtime components read only the cached `Device_Image_URL__c` field.

**Main flow**
1. Scheduled Flow → `ExternalApiService` fetches image URLs.
2. Write to `Product2.Device_Image_URL__c`.
3. Use the `Cache_Ttl_Seconds__c` (86400) for the batch, not per render.

**Alternate / exception flows**
- E1: Image API down → flag off in metadata; keep last good cached URL.

**Business rules**

| Rule | Source |
|---|---|
| Images read from cache; never a live callout per datatable row | §8.2 |
| API disabled via `Is_Active__c` without a deployment | §9 |

**Acceptance criteria**
- [ ] All device products carry a cached image URL after sync (requires the real endpoint).
- [x] No live callout on any datatable render (slice 7 caches onto `Product2.Device_Image_URL__c`).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Image sync run | Query products | URLs populated |

**Definition of done**
- [ ] Scheduled; `Device_Image_URL__c` in source where applicable.

**Open questions / risks** — none.

---

### UC-INT-06 — `ExternalApiService` + `External_Api__mdc` framework

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 8 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Developer |
| Depends on | UC-DM-08 |
| Blocks | UC-INT-01, UC-INT-05, UC-UX-06 |
| Business process | 05, 11 |
| Architecture ref | §9 |
| Data model ref | §9.2 |
| Status | 🔶 Slice 1 complete (callout + kill switches; cache/throttle deferred) |

**Goal.** Provide one callout framework where no URL or key is ever hardcoded, with caching, throttling, timeouts, and a kill switch.

**Preconditions** — `External_Api__mdc` seeded.

**Main flow**
1. Implement `ExternalApiService` reading base URL, auth type, Named Credential, timeout, cache TTL, rate limit, and `Is_Active__c` from metadata.
2. Route all callouts through it.
3. Cache per `Cache_Ttl_Seconds__c` (except provisioning = 0).
4. Allow disabling a dead API without a deployment.

**Alternate / exception flows**
- E1: Missing metadata row → fail fast with a clear error; never fall back to a hardcoded URL.

**Business rules**

| Rule | Source |
|---|---|
| No URL or key hardcoded in Apex | §9, anti-pattern |
| Secret never leaves the platform (Named Credential) | §9.2 |

**Acceptance criteria**
- [ ] All callouts resolve endpoints from metadata.
- [ ] Toggling `Is_Active__c` disables an API without deploy.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | `Is_Active__c = false` | Call | Blocked gracefully |

**Definition of done**
- [ ] Framework used by every integration card; no hardcoded endpoints remain.

**Open questions / risks** — none.

> **E8 slice 1 (2026-11-21):** `ExternalApiService` resolves `External_Api__mdt` rows by `DeveloperName`, honours `Is_Active__c` plus the `ATS_Feature_Flags__c.External_Api_Enabled__c` global switch, validates auth type and Named Credential presence, joins base URL + path without duplicate slashes, applies configured timeout, sets `X-Correlation-Id` and optional `Idempotency-Key`, and throws `ExternalApiException` on transport errors or non-2xx responses. No URL or credential is hardcoded. `Cache_Ttl_Seconds__c` and `Rate_Limit_Per_Minute__c` are read into config but enforcement is deferred; no live gateway is switched over yet. Deploy `0Afbm00000p8zx0CAA` (6/6), refactored into a short façade + collaborators in deploy `0Afbm00000p9CRBCA2` (11/11), targeted suite 10/10 (run `707bm00001YJjyZ`), full suite 234/234 after refactor (run `707bm00001YJxK9`).

---

### UC-INT-07 — Reporting / BI feed (Change Data Capture)

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 8 |
| Actor(s) | A8, A6 |
| Suggested owner | Integration Developer |
| Depends on | UC-DM-01 |
| Blocks | KPI reporting |
| Business process | all |
| Architecture ref | §9 |
| Data model ref | §14 |
| Status | 🔶 Flag-off scaffold ready; outbound feed not configured |

**Goal.** Stream the four custom objects plus `Asset` to Data Cloud / Power BI for churn, penalty, and operational KPIs.

**Preconditions** — objects deployed.

> **Cutover note (E8 slice 8):** CDC is enabled on `Subscription__c`, `Engagement__c`, `Customer_Request__c`, `Eligibility__c`, and `Asset`. `CDC_Reporting_Live__c` defaults to `false`; five change-event triggers call `CdcReportingService`, which publishes one sanitised audit event per batch from explicit non-PII allowlists. The `CDC` system value was added to `IntegrationLogService` and the `Integration_Log__c.System__c` picklist. Object enablement used a legacy v41 deploy and is intentionally absent from v68 source metadata. Configure the authorised Data Cloud / Power BI consumer before enabling the flag.

**Main flow**
1. Enable Change Data Capture on `Subscription__c`, `Engagement__c`, `Customer_Request__c`, `Eligibility__c` (+ `Asset`).
2. Configure the outbound feed to Data Cloud / Power BI.
3. Ensure no PII is exposed beyond authorised consumers.

**Alternate / exception flows**
- E1: Volume spike → CDC tuning; do not degrade transactional performance.

**Business rules**

| Rule | Source |
|---|---|
| CDC on the 4 custom objects + `Asset` | §9 |
| PII never leaves the platform unredacted | X15 |

**Acceptance criteria**
- [x] CDC enabled on the four custom objects plus `Asset`; a sanitised audit event is produced (slice 8).
- [ ] Outbound feed to Data Cloud / Power BI configured and a change appears downstream.
- [x] Salesforce-side field selection excludes restricted PII (explicit allowlists; slice 8).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Subscription status change | Inspect feed | Change published |

**Definition of done**
- [ ] Feed live; KPI definitions agreed (§16).

**Open questions / risks** — none.
