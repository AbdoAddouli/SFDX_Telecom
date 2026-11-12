/**
 * UC-COM-04: single write path for Subscription__c lifecycle status.
 *
 * The handler validates inserts and status transitions under USER_MODE DML as
 * well as API, data-load, Flow and integration updates. It also blocks hard
 * deletes so subscription history remains queryable.
 */
public with sharing class SubscriptionTriggerHandler {
    private static final Set<String> INITIAL_STATUSES = new Set<String>{
        SubscriptionStateMachine.DRAFT,
        SubscriptionStateMachine.PENDING_ACTIVATION
    };

    public static void handle(
        System.TriggerOperation operation,
        List<Subscription__c> newRecords,
        Map<Id, Subscription__c> oldRecords
    ) {
        switch on operation {
            when BEFORE_INSERT {
                validateInserts(newRecords);
            }
            when BEFORE_UPDATE {
                validateUpdates(newRecords, oldRecords);
            }
            when BEFORE_DELETE {
                blockDeletes(oldRecords);
            }
            when else {
                return;
            }
        }
    }

    private static void validateInserts(List<Subscription__c> records) {
        if (records == null) {
            return;
        }

        for (Subscription__c record : records) {
            if (String.isBlank(record.Status__c)) {
                record.Status__c = SubscriptionStateMachine.DRAFT;
                continue;
            }
            if (!INITIAL_STATUSES.contains(record.Status__c)) {
                record.addError(
                    Subscription__c.Status__c,
                    'New subscriptions must start in Draft or ' +
                    'PendingActivation; received ' +
                    record.Status__c +
                    '.'
                );
            }
        }
    }

    private static void validateUpdates(
        List<Subscription__c> records,
        Map<Id, Subscription__c> oldRecords
    ) {
        if (records == null || oldRecords == null) {
            return;
        }

        for (Subscription__c record : records) {
            Subscription__c oldRecord = oldRecords.get(record.Id);
            if (oldRecord == null) {
                continue;
            }
            SubscriptionStateMachine.assertAllowed(oldRecord, record);
        }
    }

    private static void blockDeletes(Map<Id, Subscription__c> oldRecords) {
        if (oldRecords == null) {
            return;
        }

        for (Subscription__c record : oldRecords.values()) {
            record.addError(
                'Subscriptions are financial history and cannot be deleted. ' +
                'Set Status to Cancelled or Superseded instead.'
            );
        }
    }
}
