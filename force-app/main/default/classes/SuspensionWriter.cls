/**
 * Bulk write path for suspension/unfreeze. Only Subscription, Case and
 * Customer_Request__c are written; Contract and Engagement stay untouched.
 */
public with sharing class SuspensionWriter {
    public static void apply(List<SuspensionContext> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        Date today = Date.today();

        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Case> cases = new List<Case>();
        List<Customer_Request__c> requests = new List<Customer_Request__c>();

        for (SuspensionContext item : items) {
            subscriptions.add(
                new Subscription__c(
                    Id = item.subscription.Id,
                    Status__c = item.targetStatus,
                    External_Status__c = SuspensionPolicy.externalStatus(
                        item.action
                    ),
                    Last_Sync_DateTime__c = now
                )
            );
            if (item.request.Case__c != null) {
                cases.add(
                    new Case(
                        Id = item.request.Case__c,
                        Status = SuspensionPolicy.CASE_CLOSED
                    )
                );
            }
            requests.add(
                new Customer_Request__c(
                    Id = item.request.Id,
                    Status__c = SuspensionPolicy.STATUS_COMPLETED,
                    Completed_On__c = now,
                    Resolution_Summary__c = (
                        item.action +
                        ' applied on ' +
                        today.format() +
                        '. Contract and engagement unchanged.'
                    ).left(1000)
                )
            );
        }

        Database.update(subscriptions, true);
        if (!cases.isEmpty()) {
            Database.update(cases, true);
        }
        Database.update(requests, true);
    }
}
