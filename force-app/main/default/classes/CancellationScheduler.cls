/**
 * Single bulk write path for scheduling a cancellation. Two DML statements
 * handle the whole batch regardless of how many requests were approved.
 */
public with sharing class CancellationScheduler {
    public class Item {
        public Integer resultIndex;
        public Date effectiveDate;
        public Customer_Request__c request;
        public Subscription__c subscription;
    }

    public static void schedule(List<Item> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (Item item : items) {
            if (
                item.request == null ||
                item.subscription == null ||
                item.effectiveDate == null
            ) {
                throw new CancellationService.CancellationException(
                    'The approved request or subscription could not be resolved.'
                );
            }
            item.subscription.Status__c =
                SubscriptionStateMachine.PENDING_CANCELLATION;
            subscriptions.add(item.subscription);

            item.request.Status__c = CancellationPolicy.STATUS_IN_FULFILMENT;
            item.request.Due_Date__c = item.effectiveDate;
            item.request.Resolution_Summary__c = (
                'Cancellation approved; service continues until ' +
                item.effectiveDate.format() + '.'
            ).left(1000);
            requests.add(item.request);
        }

        Database.update(subscriptions, true);
        Database.update(requests, true);
    }
}
