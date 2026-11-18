/**
 * Pure fulfilment rules. No SOQL or DML; safe to call for every batch row.
 */
public with sharing class CancellationFulfilmentValidator {
    public static String error(Customer_Request__c request, Date today) {
        if (request == null) {
            return 'Cancellation request could not be found.';
        }
        if (request.Status__c != CancellationPolicy.STATUS_IN_FULFILMENT) {
            return 'Request is not ready for fulfilment.';
        }
        if (
            request.Cancellation_Effective_Date__c == null ||
            request.Cancellation_Effective_Date__c > today
        ) {
            return 'The cancellation effective date has not been reached.';
        }
        Subscription__c subscription = request.Subscription__r;
        if (subscription == null || subscription.Id == null) {
            return 'Subscription could not be found.';
        }
        if (
            subscription.Status__c !=
            SubscriptionStateMachine.PENDING_CANCELLATION
        ) {
            return 'Subscription is not awaiting fulfilment.';
        }
        return null;
    }
}
