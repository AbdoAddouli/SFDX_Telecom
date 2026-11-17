# Salesforce Support Request — Custom Indexes

**Status:** Prepared 2026-11-06; not submitted  
**Source:** `DATA_MODEL.md` §13.2, `use-cases/EPIC-01-data-model.md` UC-DM-13  
**Target org:** production org with a Salesforce Support entitlement

> Custom indexes can't be created with the Metadata API alone. Salesforce's
> `CustomIndex` metadata type exposes only `allowNullValues` and
> `booleanIndexedValue` (plus the inherited `fullName`); it does not define the
> indexed fields. Per the Metadata API documentation, create custom indexes
> through Salesforce Customer Support.

## Why these indexes are needed

`Subscription__c` is the high-volume custom object (millions of records). The
360° subscriber view, renewal outreach, hardware filtering, work queues, and
integration triage all filter on low-selectivity fields or use two-field
predicates. At production volume these queries need custom indexes to avoid
full-table scans.

This is a scale-hardening request, not a functional change. The Developer
Edition build org has only a handful of records, so the benefit can only be
validated after volume exists.

## Requested indexes

| # | Object | Fields (leading field first) | Field types | Query / feature served |
|---|---|---|---|---|
| 1 | `Subscription__c` | `Account__c` + `Status__c` | Lookup(Account) + Picklist | 360° Subscriptions zone; highest-frequency query |
| 2 | `Subscription__c` | `Account__c` + `Service_Line_Type__c` | Lookup(Account) + Picklist | Hardware zone filter |
| 3 | `Subscription__c` | `Status__c` + `Next_Renewal_Date__c` | Picklist + Date | Renewal outreach batch |
| 4 | `Engagement__c` | `Subscription__c` + `Status__c` | Lookup(`Subscription__c`) + Picklist | Active-commitment lookup during plan change |
| 5 | `Customer_Request__c` | `Status__c` + `Due_Date__c` | Picklist + Date | Work queue and SLA breach scan |
| 6 | `Eligibility__c` | `Postal_Code__c` + `Is_Active__c` | Text(10) + Checkbox | Geography lookup when inactive rows are retained |
| 7 | `Integration_Log__c` | `Correlation_Id__c` + `Status__c` | Text(36) + Picklist | Failure triage |

### Query patterns

```soql
-- 1. 360° Subscriptions zone
SELECT Id, Name, Status__c, Service_Line_Type__c, Monthly_Amount__c
FROM Subscription__c
WHERE Account__c = :accountId AND Status__c = :status
ORDER BY Name;

-- 2. Hardware zone
SELECT Id, Name, Asset__c, Monthly_Amount__c
FROM Subscription__c
WHERE Account__c = :accountId AND Service_Line_Type__c = 'Device';

-- 3. Renewal outreach
SELECT Id, Name, Account__c, Billing_End_Date__c
FROM Subscription__c
WHERE Status__c = 'Active' AND Next_Renewal_Date__c = :today;

-- 4. Active commitment for a subscription
SELECT Id, Name, End_Date__c
FROM Engagement__c
WHERE Subscription__c = :subscriptionId AND Status__c = 'Active';

-- 5. SLA work queue
SELECT Id, Name, Priority__c, Due_Date__c
FROM Customer_Request__c
WHERE Status__c IN ('New', 'In Progress') AND Due_Date__c <= :cutoff
ORDER BY Due_Date__c;

-- 6. Active eligibility by postcode
SELECT Id, Name, Region__c
FROM Eligibility__c
WHERE Postal_Code__c = :postalCode AND Is_Active__c = true;

-- 7. Integration failure triage
SELECT Id, Name, Error_Message__c, CreatedDate
FROM Integration_Log__c
WHERE Correlation_Id__c = :correlationId AND Status__c = 'Failed';
```

## Scale assumptions to include in the case

- `Subscription__c`: millions of records; daily 360° reads by service and sales.
- `Engagement__c`: high volume; read during every plan change and penalty check.
- `Customer_Request__c`: work queue scanned continuously by service agents.
- `Integration_Log__c`: high volume, retained for 13 months and then hard-deleted.
- `Eligibility__c`: small reference table, but filtered by postcode and active flag.

## Case text

> **Subject:** Custom index request — ATS Telecom data model (7 indexes)
>
> We are preparing a Salesforce data model for a telecom subscriber platform.
> Our design review requires custom indexes on the following objects/fields to
> keep production queries selective at multi-million-record volumes:
>
> 1. `Subscription__c`: `Account__c`, `Status__c`
> 2. `Subscription__c`: `Account__c`, `Service_Line_Type__c`
> 3. `Subscription__c`: `Status__c`, `Next_Renewal_Date__c`
> 4. `Engagement__c`: `Subscription__c`, `Status__c`
> 5. `Customer_Request__c`: `Status__c`, `Due_Date__c`
> 6. `Eligibility__c`: `Postal_Code__c`, `Is_Active__c`
> 7. `Integration_Log__c`: `Correlation_Id__c`, `Status__c`
>
> Please create the custom indexes with the leading field as listed. Confirm
> any Salesforce limits that apply, the maximum number of fields per index, and
> whether ascending/descending order matters for these predicates. We will
> validate the indexes with the Query Plan API after they are active.

## Acceptance and verification

- [ ] Support case number recorded here.
- [ ] Support confirms all seven custom indexes are active in the target org.
- [ ] `CustomIndex` metadata is retrieved into the repository if Salesforce
      exposes the created indexes.
- [ ] Query Plan API shows index use for the 360° and renewal queries once the
      org has representative data volume.

## External ID pre-check (2026-11-06)

The external-ID portion of UC-DM-13 was rechecked in the Developer Edition org.

| Object | Field | Type | External ID | Unique |
|---|---|---|---|---|
| `Subscription__c` | `External_Reference__c` | Text(64) | Yes | Yes |
| `Subscription__c` | `MSISDN__c` | Text(20) | Yes | Yes |
| `Account` | `Legacy_Customer_Id__c` | Text(40) | Yes | Yes |
| `Product2` | `ATS_Product_Code__c` | Text(40) | Yes | Yes |
| `Order` | `BSS_Order_Key__c` | Text(64) | Yes | Yes (set 2026-11-06) |
| `Eligibility__c` | `Postal_Code__c` | Text(10) | Yes | Yes |
| `Engagement__c` | `Engagement_Number__c` | — | Not deployed | — |

`Engagement__c` uses the auto-number `Name` field (`ENG-{0000}`) as its
reference. The field dictionary requires an Auto Number, while §13.1 asks for
an External ID; an auto-number field can't also be an External ID. If a true
external ID is required for Engagement upserts, add a separate Text(30)
External ID field and populate it from `Name`; that is a design decision, not a
prerequisite for the index request.
