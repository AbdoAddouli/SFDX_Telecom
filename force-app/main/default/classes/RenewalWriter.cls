/**
 * Bulk write path for renewal fulfilment. One DML statement per related object
 * covers the whole batch; the caller owns the savepoint.
 */
public with sharing class RenewalWriter {
    public static void apply(List<RenewalContext> contexts, Date today) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();

        List<Engagement__c> expiring = new List<Engagement__c>();
        List<Engagement__c> newEngagements = new List<Engagement__c>();
        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Contract> contracts = new List<Contract>();

        for (RenewalContext context : contexts) {
            Subscription__c source = context.subscription;
            Engagement__c oldEngagement = context.engagement;
            expiring.add(
                new Engagement__c(
                    Id = oldEngagement.Id,
                    Status__c = RenewalPolicy.ENGAGEMENT_EXPIRED,
                    Renewal_Contacted__c = true,
                    Renewal_Contacted_On__c = now
                )
            );

            Boolean renews = RenewalPolicy.renews(context.input.decision);
            if (renews) {
                Integer duration = oldEngagement.Duration_Months__c == 24
                    ? 24
                    : 12;
                Date startDate = oldEngagement.End_Date__c == null ||
                    oldEngagement.End_Date__c < today
                    ? today.addDays(1)
                    : oldEngagement.End_Date__c.addDays(1);
                Id rootId = oldEngagement.Root_Engagement__c == null
                    ? oldEngagement.Id
                    : oldEngagement.Root_Engagement__c;
                newEngagements.add(
                    new Engagement__c(
                        Account__c = source.Account__c,
                        Subscription__c = source.Id,
                        Contract__c = source.Contract__c,
                        Asset__c = source.Asset__c,
                        Root_Engagement__c = rootId,
                        Status__c = RenewalPolicy.ENGAGEMENT_ACTIVE,
                        Start_Date__c = startDate,
                        End_Date__c = startDate.addMonths(duration).addDays(-1),
                        Duration_Months__c = duration,
                        Monthly_Amount__c = context.quotedAmount,
                        Renewal_Contacted__c = false
                    )
                );
            }

            Subscription__c subscriptionUpdate =
                new Subscription__c(Id = source.Id);
            if (renews) {
                subscriptionUpdate.Billing_Start_Date__c =
                    oldEngagement.End_Date__c == null ||
                    oldEngagement.End_Date__c < today
                    ? today.addDays(1)
                    : oldEngagement.End_Date__c.addDays(1);
                subscriptionUpdate.Billing_End_Date__c =
                    subscriptionUpdate.Billing_Start_Date__c
                    .addMonths(oldEngagement.Duration_Months__c == 24 ? 24 : 12)
                    .addDays(-1);
                subscriptionUpdate.Monthly_Amount__c = context.quotedAmount;
                if (context.input.decision == RenewalPolicy.DECISION_NEW_PLAN) {
                    subscriptionUpdate.Product__c =
                        context.input.targetProductId;
                }
            } else {
                subscriptionUpdate.Billing_End_Date__c = today.addMonths(1);
            }
            subscriptions.add(subscriptionUpdate);

            if (context.contract != null) {
                contracts.add(
                    new Contract(
                        Id = context.contract.Id,
                        Auto_Renew__c = renews
                    )
                );
            }
        }

        Database.update(expiring, true);
        if (!newEngagements.isEmpty()) {
            Database.insert(newEngagements, true);
        }
        if (!contracts.isEmpty()) {
            Database.update(contracts, true);
        }

        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        List<Case> cases = new List<Case>();
        Integer renewalIndex = 0;
        for (Integer i = 0; i < contexts.size(); i++) {
            RenewalContext context = contexts[i];
            Boolean renews = RenewalPolicy.renews(context.input.decision);
            if (renews) {
                Engagement__c created = newEngagements[renewalIndex++];
                subscriptions[i].Engagement__c = created.Id;
                subscriptions[i].Root_Engagement__c =
                    created.Root_Engagement__c;
            }
            requests.add(
                new Customer_Request__c(
                    Id = context.request.Id,
                    Status__c = RenewalPolicy.STATUS_COMPLETED,
                    Completed_On__c = now,
                    Resolution_Summary__c = (
                        context.input.decision +
                        ' applied. Renewal monthly amount ' +
                        context.quotedAmount +
                        '. Expiring engagement ' +
                        context.engagement.Id +
                        ' is Expired.'
                    ).left(1000)
                )
            );
            if (context.request.Case__c != null) {
                cases.add(
                    new Case(Id = context.request.Case__c, Status = 'Closed')
                );
            }
        }
        Database.update(subscriptions, true);
        Database.update(requests, true);
        if (!cases.isEmpty()) {
            Database.update(cases, true);
        }
    }
}
