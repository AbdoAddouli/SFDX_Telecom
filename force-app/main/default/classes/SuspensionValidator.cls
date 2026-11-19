/**
 * Pure UC-LIF-04 validation rules. No SOQL or DML; safe per batch row.
 */
public with sharing class SuspensionValidator {
    public static String inputError(
        SuspensionService.SuspensionInput input
    ) {
        if (input == null) {
            return 'Suspension details are required.';
        }
        if (!SuspensionPolicy.ACTIONS.contains(input.action)) {
            return 'Action must be Suspend or Unfreeze.';
        }
        if (input.accountId == null) {
            return 'Account is required.';
        }
        if (input.contactId == null) {
            return 'Contact is required.';
        }
        if (input.subscriptionId == null) {
            return 'Subscription is required.';
        }
        if (!LifecycleRequestPolicy.VALID_CHANNELS.contains(input.channel)) {
            return 'A valid Channel is required.';
        }
        if (
            input.goodwillWaiver == true &&
            String.isBlank(input.goodwillJustification)
        ) {
            return 'Goodwill justification is required when a waiver is requested.';
        }
        return null;
    }

    public static String statusError(
        Subscription__c subscription,
        String action
    ) {
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (
            action == SuspensionPolicy.ACTION_SUSPEND &&
            subscription.Status__c != SubscriptionStateMachine.ACTIVE
        ) {
            return 'Only an active line can be suspended.';
        }
        if (
            action == SuspensionPolicy.ACTION_UNFREEZE &&
            subscription.Status__c != SubscriptionStateMachine.SUSPENDED
        ) {
            return 'Only a suspended line can be unfrozen.';
        }
        return null;
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        SuspensionService.SuspensionInput input
    ) {
        LifecycleRequestService.RequestInput request =
            new LifecycleRequestService.RequestInput();
        request.requestType = SuspensionPolicy.requestType(input.action);
        request.accountId = input.accountId;
        request.contactId = input.contactId;
        request.subscriptionId = input.subscriptionId;
        request.channel = input.channel;
        request.customerComment = input.customerComment;
        request.goodwillWaiver = input.goodwillWaiver;
        request.goodwillJustification = input.goodwillJustification;
        request.priority = input.priority;
        return request;
    }
}
