/**
 * Bulk query boundary for cancellation fulfilment.
 */
public with sharing class CancellationFulfilmentRepository {
    public static Set<Id> activeAccountIds(Set<Id> accountIds) {
        Set<Id> activeAccountIds = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty()) {
            return activeAccountIds;
        }
        for (Subscription__c subscription : [
            SELECT Account__c
            FROM Subscription__c
            WHERE
                Account__c IN :accountIds
                AND Status__c = :SubscriptionStateMachine.ACTIVE
        ]) {
            activeAccountIds.add(subscription.Account__c);
        }
        return activeAccountIds;
    }
}
