# Revenue Core — what you need from Revenue Cloud, and what you build instead

> **Context:** the ATS Telecom blueprint (`docs/index.html`, `use-cases/*.md`) was written **assuming Revenue Cloud Advanced (RCA) is enabled** in the org. Your org is a **Developer Edition** with **no RCA, no Experience Cloud licence, no sandboxes, 5 MB data storage, 2 licences**. This folder documents every place the blueprint depends on Revenue Cloud, and the replacement you build yourself — the working name **"Revenue Core"**.

## Read in this order

| # | File | What it answers |
|---|---|---|
| 1 | [`01-REVENUE-CLOUD-DEPENDENCIES.md`](./01-REVENUE-CLOUD-DEPENDENCIES.md) | Every use case that needs Revenue Cloud, with the documented fallback |
| 2 | [`02-DE-ORG-CONSTRAINTS.md`](./02-DE-ORG-CONSTRAINTS.md) | Your real org limits and what each one forces you to change |
| 3 | [`03-REVENUE-CORE-SPEC.md`](./03-REVENUE-CORE-SPEC.md) | The engine you build to replace RCA — components, objects, services |
| 4 | [`04-OPEN-DECISIONS.md`](./04-OPEN-DECISIONS.md) | The decisions that must be answered before/while building |
| 5 | [`05-BUILD-ORDER.md`](./05-BUILD-ORDER.md) | The order to build in, and where the blueprint's sequence changes |
| 6 | [`06-REVENUE-CORE-PACKAGE.md`](./06-REVENUE-CORE-PACKAGE.md) | **The metadata package on disk** — 3 Custom Metadata Types + 10 seed records, deploy steps, and every deviation from file 03 |
| 7 | [`07-PRICING-EXPORT-RUNBOOK.md`](./07-PRICING-EXPORT-RUNBOOK.md) | Export, offline verification, rollback drill, and refresh discipline for pricing metadata |

## The short answer

**Revenue Cloud would have given you six things.** You build three, get two free from standard Salesforce, and one you cannot have:

| What Revenue Cloud gives you | Verdict | Replacement |
|---|---|---|
| Pricing procedures + decision tables | **Build** | `Pricing_Procedure__mdt` + `Pricing_Rule__mdt` + `PricingService` Apex |
| Product configuration rules (bundle constraints) | **Build** | `Config_Rule__mdt` + evaluation in `CatalogQueryService` |
| Product classification (attribute-based catalogue) | **Build** | `Product_Classification__c` custom hierarchy (or keep `Product2.Family`) |
| Quote / Order construction | **Free** | Standard `Quote`, `QuoteLineItem`, `Order`, `OrderItem` |
| Catalogue + prices | **Free** | Standard `Product2`, `Pricebook2`, `PricebookEntry` |
| Billing / invoicing / revenue recognition | **Blocked** | Not buildable in your scope — E10 stays conditional |

**Two corrections to what I told you earlier in this conversation:**

1. **Do NOT build `Invoice__c` / `Invoice_Line__c`.** `DATA_MODEL.md` §18 explicitly forbids pre-building them, and E10 (Billing) is conditional on decision **Q3 / BQ7** — *"Do invoicing and revenue recognition live in Salesforce?"* Until Finance answers, those use cases must not be started.
2. **`ActivationService` and the subscription state machine are not new work** — they are already use cases `UC-COM-03` and `UC-COM-04` in the blueprint. The genuinely *new* work created by the missing licence is the **pricing engine**, the **configuration rules**, and the **classification hierarchy**.

## What is permanently blocked

- **E7 — Self-Service Portal** needs an Experience Cloud licence (a public Site still requires one for authenticated customer access). No workaround gives you the real thing; defer or demonstrate with a public unauthenticated form only (which is already `UC-ACQ-03`).
- **Scratch orgs / sandboxes** — a DE org is not a Dev Hub with meaningful allocation, and has no sandboxes. All testing happens **in the dev org itself**, with careful reset scripts.
- **5 GB of prices** in E2's exit gate cannot be tested literally. Test the *pattern* at small scale and document the scaling strategy (see file 02).

## Non-negotiable rule

The scope stays frozen at the **80 use cases** in `docs/index.html`. Revenue Core is not a generic pricing engine — it implements exactly the pricing, configuration and classification behaviour those 80 use cases demand, and nothing more.
