/**
 * Pure cancellation rules. No SOQL, DML or state; safe to call for every row
 * in a bulk request and easy to unit test.
 */
public with sharing class CancellationValidator {
    public static String intakeError(
        CancellationService.CancellationInput input,
        Map<Id, Subscription__c> subscriptions,
        Map<Id, Customer_Request__c> inFlight,
        Set<Id> seenSubscriptionIds,
        Date today
    ) {
        if (input == null) {
            return 'Cancellation details are required.';
        }
        if (
            input.accountId == null ||
            input.contactId == null ||
            input.subscriptionId == null ||
            String.isBlank(input.channel)
        ) {
            return 'Account, Contact, Subscription and Channel are required.';
        }
        if (!CancellationPolicy.VALID_REASONS.contains(input.cancellationReason)) {
            return 'A valid Cancellation Reason is required.';
        }
        if (input.cancellationEffectiveDate == null) {
            return 'A Cancellation Effective Date is required.';
        }
        if (input.cancellationEffectiveDate < CancellationPolicy.earliestEffectiveDate(today)) {
            return 'At least ' + CancellationPolicy.NOTICE_DAYS +
                ' days notice is required for cancellation.';
        }
        if (input.goodwillWaiver == true && String.isBlank(input.goodwillJustification)) {
            return 'Goodwill justification is required when a waiver is requested.';
        }

        Subscription__c subscription = subscriptions.get(input.subscriptionId);
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (subscription.Status__c != SubscriptionStateMachine.ACTIVE) {
            return 'Only an active line can be cancelled.';
        }
        if (
            inFlight.containsKey(input.subscriptionId) ||
            !seenSubscriptionIds.add(input.subscriptionId)
        ) {
            return 'A cancellation request is already in progress for this line.';
        }
        return null;
    }

    public static String approvalError(
        Customer_Request__c request,
        Subscription__c subscription,
        Date today
    ) {
        if (request.Status__c != CancellationPolicy.STATUS_APPROVED) {
            return 'Request must be approved before cancellation can be scheduled.';
        }
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (
            request.Cancellation_Effective_Date__c == null ||
            request.Cancellation_Effective_Date__c <
                CancellationPolicy.earliestEffectiveDate(today)
        ) {
            return 'The requested effective date no longer satisfies ' +
                CancellationPolicy.NOTICE_DAYS + ' days notice.';
        }
        if (
            subscription.Status__c != SubscriptionStateMachine.ACTIVE &&
            subscription.Status__c != SubscriptionStateMachine.PENDING_CANCELLATION
        ) {
            return 'Only an active line can be cancelled.';
        }
        return null;
    }

    public static Boolean isCompleted(Customer_Request__c request) {
        return request != null &&
            request.Status__c == CancellationPolicy.STATUS_COMPLETED;
    }

    public static Boolean isAlreadyScheduled(
        Customer_Request__c request,
        Subscription__c subscription
    ) {
        return request != null &&
            subscription != null &&
            subscription.Status__c == SubscriptionStateMachine.PENDING_CANCELLATION &&
            (
                request.Status__c == CancellationPolicy.STATUS_APPROVED ||
                request.Status__c == CancellationPolicy.STATUS_IN_FULFILMENT
            );
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        CancellationService.CancellationInput input
    ) {
        LifecycleRequestService.RequestInput request =
            new LifecycleRequestService.RequestInput();
        request.requestType = CancellationPolicy.REQUEST_TYPE;
        request.accountId = input.accountId;
        request.contactId = input.contactId;
        request.subscriptionId = input.subscriptionId;
        request.channel = input.channel;
        request.cancellationReason = input.cancellationReason;
        request.cancellationEffectiveDate = input.cancellationEffectiveDate;
        request.customerComment = input.customerComment;
        request.goodwillWaiver = input.goodwillWaiver;
        request.goodwillJustification = input.goodwillJustification;
        request.priority = input.priority;
        return request;
    }
}
