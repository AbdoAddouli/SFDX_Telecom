/**
 * Pure lifecycle intake rules. No SOQL or DML; safe to call per batch row.
 */
public with sharing class LifecycleRequestValidator {
    public static String validate(
        LifecycleRequestService.RequestInput input,
        Map<Id, Subscription__c> subscriptions
    ) {
        if (input == null) {
            return 'Request details are required.';
        }
        if (!LifecycleRequestPolicy.VALID_TYPES.contains(input.requestType)) {
            return 'A valid Request Type is required.';
        }
        if (input.accountId == null) {
            return 'Account is required.';
        }
        if (input.contactId == null) {
            return 'Contact is required.';
        }
        if (!LifecycleRequestPolicy.VALID_CHANNELS.contains(input.channel)) {
            return 'A valid Channel is required.';
        }
        Boolean actionable = input.requestType != LifecycleRequestPolicy.TYPE_INFO;
        if (
            actionable &&
            input.requestType != LifecycleRequestPolicy.TYPE_NEW_SUBSCRIPTION &&
            input.subscriptionId == null
        ) {
            return 'Subscription is required for ' + input.requestType + '.';
        }
        if (
            input.subscriptionId != null &&
            !subscriptions.containsKey(input.subscriptionId)
        ) {
            return 'Subscription could not be found.';
        }
        if (input.goodwillWaiver == true && String.isBlank(input.goodwillJustification)) {
            return 'Goodwill justification is required when a waiver is requested.';
        }
        return null;
    }
}
