# E0 — Foundation (Phase 0)

**Objective:** stand up the project, the environments, licensing, and the CI/CD spine so every later phase deploys cleanly to an empty org.
**Exit gate:** *Metadata deploys cleanly to an empty org* (`ARCHITECTURE.md` §13).
**Source:** `ARCHITECTURE.md` §2, §3.3, §10, §11, §12; `DATA_MODEL.md` §19.

| ID | Title | Priority | Owner | Status |
|---|---|---|---|---|
| UC-FND-01 | Initialize the SFDX project and repository structure | Must | DevOps / Release Engineer | 🔲 |
| UC-FND-02 | Provision dedicated environments and scratch org definition | Must | DevOps / Release Engineer | 🔲 |
| UC-FND-03 | Enable Revenue Cloud Advanced and required org configuration | Must | Solution Architect + A7 | 🔴 |
| UC-FND-04 | Establish naming, namespace, and scaffolding conventions | Must | Solution Architect | 🔲 |
| UC-FND-05 | Stand up CI/CD with DevOps Center | Must | DevOps / Release Engineer | 🔲 |
| UC-FND-06 | Resolve and record blocking open decisions | Must | Business Analyst + sponsors | 🔴 |
| UC-FND-07 | Configure Translation Workbench scope | Should | Salesforce Admin | 🔲 |

---

### UC-FND-01 — Initialize the SFDX project and repository structure

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A6 |
| Suggested owner | DevOps / Release Engineer |
| Depends on | — |
| Blocks | UC-FND-05, all deployment work |
| Business process | — |
| Architecture ref | §2.2, §11.3 |
| Data model ref | §19 |
| Status | 🔲 Not started |

**Goal.** Create a versioned Salesforce DX project with the package-directory split the release pipeline depends on, replacing the current empty repository (no `sfdx-project.json`, no `force-app/`, no git history).

**Preconditions**
- Repository checkout available; SF CLI installed.

**Main flow**
1. Run `sf project init` with the `ats_` namespace.
2. Create the directory split required by `ARCHITECTURE.md` §11.3:
   - `force-app/` — production metadata
   - `force-app-test/` — test classes and test-data templates
   - `manifest/` — `package.xml` for ad-hoc deploys
   - `scripts/` — idempotent data seed and post-deploy hooks
   - `pricing-export/` — RCA decision tables + pricing procedures artefacts (**mandatory**)
3. Commit the skeleton and a `.forceignore` that excludes `pricing-export/` from normal deploy but tracks it in git.
4. Add a `README` with the branch strategy and the deployment order from `DATA_MODEL.md` §19.

**Alternate / exception flows**
- E1: Namespace already registered to another org → stop; escalate to the architect before creating a second namespace.

**Business rules**

| Rule | Source |
|---|---|
| `pricing-export/` is mandatory, not optional | `ARCHITECTURE.md` §11.3 |

**Acceptance criteria**
- [ ] `sfdx-project.json` exists with package directories matching §11.3.
- [ ] `force-app/`, `force-app-test/`, `manifest/`, `scripts/`, `pricing-export/` all exist and are committed.
- [ ] A placeholder class deploys to a scratch org via `sf project deploy start`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Clean checkout | `sf project deploy start` on empty metadata | Deploys with zero errors |

**Definition of done**
- [ ] Repo structure matches §11.3; CI (UC-FND-05) can read it.

**Open questions / risks** — none.

---

### UC-FND-02 — Provision dedicated environments and scratch org definition

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A6 |
| Suggested owner | DevOps / Release Engineer |
| Depends on | UC-FND-01 |
| Blocks | UC-FND-05, UC-FND-03 |
| Business process | — |
| Architecture ref | §2.2, §11.1 |
| Data model ref | — |
| Status | 🔲 Not started |

**Goal.** Provide the four-environment strategy and stop building against `devtospace-stage`, which holds three unrelated projects and ~250 foreign no-namespace classes.

**Preconditions**
- Licensing decision (Q2) at least provisionally available.

**Main flow**
1. Create `config/` scratch-org definition files (features, settings, edition).
2. Provision `ats-dev` (ephemeral scratch), `ats-int` (integration/SIT), `ats-uat` (business acceptance), `ats-prod` (`ARCHITECTURE.md` §11.1).
3. Document refresh cadence: `ats-dev` on demand, `ats-int` nightly, `ats-uat` per release train.
4. Record each environment's alias and instance URL in a runbook.

**Alternate / exception flows**
- E1: Only a shared sandbox is available → audit existing automation coverage of the new objects before creating them (`R6`), and isolate naming with the `ats_` prefix.

**Business rules**

| Rule | Source |
|---|---|
| Dedicated org required; shared sandbox is not a target | `ARCHITECTURE.md` D2, R6 |

**Acceptance criteria**
- [ ] `ats-dev`, `ats-int`, `ats-uat`, `ats-prod` exist and authenticate.
- [ ] Scratch-org definition recreates `ats-dev` deterministically.
- [ ] No ATS work is built in `devtospace-stage`.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Scratch definition | `sf org create scratch -f config/...` | Org is created and authenticated |

**Definition of done**
- [ ] Environments documented and reachable by CI.

**Open questions / risks** — `R6` shared-sandbox coupling if a dedicated org is delayed.

---

### UC-FND-03 — Enable Revenue Cloud Advanced and required org configuration

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A7 |
| Suggested owner | Solution Architect + A7 (Pricing Admin) |
| Depends on | UC-FND-02 |
| Blocks | E2, E4, E5; three RCA-dependent lookups in `DATA_MODEL.md` §1.4 |
| Business process | 03, 04 |
| Architecture ref | §3.3, §6 |
| Data model ref | §1.4, §19 (step 6 caveat) |
| Status | 🔴 Blocked — Q2 |

**Goal.** Enable the sanctioned quoting platform (RCA/RLM), which **cannot be enabled via CLI** and must exist before the RCA-dependent metadata deploys.

**Preconditions**
- Q2 resolved (RCA Growth vs Advanced); RCA SKU secured (`R1`).

**Main flow**
1. Request RCA enablement from the Salesforce account team (`ARCHITECTURE.md` §3.3).
2. Create the **Pricing Admin** permission set/users.
3. Activate decision tables and pricing procedures (inert until activated).
4. Optionally enable **Product Configurator** (CML) if device constraints exceed declarative rules.
5. Register Named Credentials and External Services for BSS and image APIs.
6. Record that pricing recipes, decision tables, and context definitions are **setup-time configuration**, exported to `pricing-export/`.

**Alternate / exception flows**
- E1: RCA not yet licensable → base objects (E1) proceed; the RCA-dependent lookup fields are split into a later deployment increment (`DATA_MODEL.md` §1.4).

**Business rules**

| Rule | Source |
|---|---|
| Only Product Catalog Management, Salesforce Pricing, Transaction Management needed for phases 1–9 | `ARCHITECTURE.md` §3.2 |
| Pricing Admin cannot create/update `PricingRecipe` fields — System Admin only | §3.3 |

**Acceptance criteria**
- [ ] `ProductClassification`, `ProductSellingModel`, `SalesTransactionType` present in `EntityDefinition`.
- [ ] Pricing Admin permission set exists.
- [ ] Decision tables/pricing procedures can be activated.
- [ ] Named Credentials registered.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | RCA enabled | Query `EntityDefinition` for RCA objects | All three present |
| TS-2 | RCA not enabled | Attempt to deploy an RCA lookup field | Deploy fails — proving the split-increment need |

**Definition of done**
- [ ] RCA-dependent metadata can deploy; export step documented.

**Open questions / risks** — `R1` (licensing not secured) is the largest schedule risk; `R4` (field names differ) — verify against the Revenue Management Developer Guide.

---

### UC-FND-04 — Establish naming, namespace, and scaffolding conventions

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A6 |
| Suggested owner | Solution Architect |
| Depends on | UC-FND-01 |
| Blocks | E1 |
| Business process | — |
| Architecture ref | §10 |
| Data model ref | §0 (conventions), §16.1 |
| Status | 🔲 Not started |

**Goal.** Fix the naming and metadata conventions up front so E1 and later epics deploy consistently and pass code review.

**Preconditions**
- UC-FND-01 done.

**Main flow**
1. Adopt conventions: `PascalCase__c` objects, `Pascal_Case__c` fields, relationship names strip `__c`, autonumber `PREFIX-{0000}`.
2. Reserve the `ats_` prefix for all namespaced metadata and all permission sets (`ats_Advisor`, …).
3. Create empty scaffold domains: `force-app/main/default/{objects,classes,triggers,lwc,flows,permissionsets}`.
4. Document the "one write path per object" and "Flow orchestrates, Apex executes" rules as review checklists.

**Alternate / exception flows** — none.

**Business rules**

| Rule | Source |
|---|---|
| Every custom field has a description and data classification | `DATA_MODEL.md` §16.1 |
| No standard field used as scratch space | §16.1 |

**Acceptance criteria**
- [ ] Convention document committed and linked from the README.
- [ ] Scaffold directories exist.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | Scaffold | Deploy empty scaffold | No errors |

**Definition of done**
- [ ] Conventions referenced by E1 cards.

**Open questions / risks** — none.

---

### UC-FND-05 — Stand up CI/CD with DevOps Center

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A6 |
| Suggested owner | DevOps / Release Engineer |
| Depends on | UC-FND-01, UC-FND-02 |
| Blocks | Every deployment thereafter |
| Business process | — |
| Architecture ref | §11.2, §11.4 |
| Data model ref | §19 |
| Status | 🔲 Not started |

**Goal.** Provide component-based deployment and release management so metadata ordering is handled and every phase has a repeatable gate.

**Preconditions**
- DevOps Center already installed in the org (`ARCHITECTURE.md` §2.2).

**Main flow**
1. Connect the repository to DevOps Center and create the pipeline across `ats-dev → ats-int → ats-uat → ats-prod`.
2. Configure the deploy order check: `CustomObject → CustomField → ValidationRule → CompactLayout → Flow → Apex → LWC → FlexiPage → PermissionSet → CustomTab` (§11.4).
3. Add a validation step running `sf project deploy validate` then tests before promote.
4. Add the **pricing export** step to the release runbook (§11.3).

**Alternate / exception flows**
- E1: DevOps Center unavailable → fall back to GitHub Actions with split package dirs (`ARCHITECTURE.md` §11.2).

**Business rules**

| Rule | Source |
|---|---|
| Deploying an LWC before its Apex dependency fails | §11.4 |
| Pricing must be exported, not only deployed | §11.3, `R2` |

**Acceptance criteria**
- [ ] A commit can be validated and promoted to `ats-int` without manual ordering.
- [ ] CI runs the test suite and fails on coverage regressions.
- [ ] Release runbook includes the pricing export/activation step.

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | A deliberately out-of-order deploy | Run pipeline | Pipeline blocks it |
| TS-2 | A green commit | Promote to `ats-int` | Deploys and tests pass |

**Definition of done**
- [ ] Pipeline green on the E0 scaffold.

**Open questions / risks** — `R2` pricing not in source control without the export step.

---

### UC-FND-06 — Resolve and record blocking open decisions

| Field | Value |
|---|---|
| Priority | Must |
| Phase | 0 |
| Actor(s) | A8, A6 |
| Suggested owner | Business Analyst + sponsors |
| Depends on | — |
| Blocks | Q1→E6/E4, Q2→E2/E4/E5, Q3→E10, Q4→E1/E8, D4→E1/E7 |
| Business process | all — §19 |
| Architecture ref | §0 |
| Data model ref | §20 |
| Status | 🔴 Blocked — awaiting owners |

**Goal.** Close or explicitly defer each decision in the README §8 register, recording the decision, date, and rationale, so no card is built on an unstated assumption.

**Preconditions** — owners identified (Finance, Commercial, Network, sponsor).

**Main flow**
1. Run a decision workshop with A8 (Finance), Commercial, Network, and the sponsor.
2. For each of Q1–Q4 and BQ1–BQ12, record: decision, decider, date, impact.
3. Publish the decision log and update affected cards from 🔴 to 🔲.
4. Escalate anything that cannot be decided before Phase 1 (notably **Q1/BQ1**).

**Alternate / exception flows**
- E1: Q1 unresolved by Phase 1 → freeze `UC-COM-05` and `UC-LIF-02` at the documented default (**amend**), flag as a debt item (`R3`).

**Business rules**

| Rule | Source |
|---|---|
| Plan-change semantics must be decided before Phase 1 | `R3`, `DATA_MODEL.md` Q1 |

**Acceptance criteria**
- [ ] A decision log exists with all Q/BQ items marked decided or deferred.
- [ ] Deferred items name the default assumed and the trigger to revisit.

**Test scenarios** — N/A (governance card).

**Definition of done**
- [ ] Affected use cases unblocked or explicitly frozen.

**Open questions / risks** — this card *is* the open-questions control.

---

### UC-FND-07 — Configure Translation Workbench scope

| Field | Value |
|---|---|
| Priority | Should |
| Phase | 0 |
| Actor(s) | A6 |
| Suggested owner | Salesforce Admin |
| Depends on | UC-FND-04 |
| Blocks | UC-HRD-03 |
| Business process | — |
| Architecture ref | §2.2, §11.6 |
| Data model ref | §9.7, §10 |
| Status | 🔲 Not started |

**Goal.** Decide translation scope deliberately, because the org labels are French (`Account` = `Société`) and standard-object translation causes layout and validation conflict across releases.

**Preconditions**
- Custom labels list agreed (`DATA_MODEL.md` §9.7).

**Main flow**
1. Enable Translation Workbench; add French as a supported language.
2. Decide deliberately **which standard objects** are translated (avoid blanket translation).
3. Translate the 4 business custom objects and the wizard using the 12 custom labels.
4. Register the decision so standard-object translation is reviewed, not assumed.

**Alternate / exception flows** — none.

**Business rules**

| Rule | Source |
|---|---|
| Standard-object translation is a deliberate decision, not a default | `ARCHITECTURE.md` §11.6 |

**Acceptance criteria**
- [ ] French active; custom labels EN/FR populated.
- [ ] Scope decision documented (standard objects in/out).

**Test scenarios**

| # | Given | When | Then |
|---|---|---|---|
| TS-1 | French user | Open wizard | Labels render in French |

**Definition of done**
- [ ] Translation scope documented; E9 translation card consumes it.

**Open questions / risks** — `R16` French org labels.
