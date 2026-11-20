/**
 * Pure UC-LIF-07 validation. No SOQL or DML; safe per batch row.
 */
public with sharing class PortabilityValidator {
    public static String inputError(
        PortabilityService.PortabilityInput input
    ) {
        if (input == null) {
            return 'Portability details are required.';
        }
        if (!PortabilityPolicy.DIRECTIONS.contains(input.direction)) {
            return 'Direction must be Inbound or Outbound.';
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
        if (!PortabilityPolicy.validMsisdn(input.requestedMsisdn)) {
            return 'Requested MSISDN must contain 7 to 15 digits with an optional leading +.';
        }
        if (!LifecycleRequestPolicy.VALID_CHANNELS.contains(input.channel)) {
            return 'A valid Channel is required.';
        }
        if (
            input.goodwillWaiver == true &&
            String.isBlank(input.goodwillJustification)
        ) {
            return 'Goodwill justification is required when a fee is waived.';
        }
        return null;
    }

    public static String subscriptionError(
        Subscription__c subscription,
        PortabilityService.PortabilityInput input
    ) {
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (subscription.Status__c != SubscriptionStateMachine.ACTIVE) {
            return 'Portability can only be requested for an active line.';
        }
        if (subscription.Account__c != input.accountId) {
            return 'Subscription does not belong to the selected account.';
        }
        if (
            PortabilityPolicy.DIRECTION_OUTBOUND == input.direction &&
            String.isBlank(subscription.MSISDN__c)
        ) {
            return 'The line has no MSISDN to port out.';
        }
        if (
            PortabilityPolicy.DIRECTION_OUTBOUND == input.direction &&
            input.requestedMsisdn != subscription.MSISDN__c
        ) {
            return 'For an outbound port, the requested MSISDN must be the number currently on the line.';
        }
        if (
            PortabilityPolicy.DIRECTION_INBOUND == input.direction &&
            input.requestedMsisdn == subscription.MSISDN__c
        ) {
            return 'Requested MSISDN is already assigned to this line.';
        }
        return null;
    }

    public static String duplicateError(
        String msisdn,
        Id subscriptionId,
        Map<String, Id> owners
    ) {
        if (owners == null || String.isBlank(msisdn)) {
            return null;
        }
        Id owner = owners.get(msisdn);
        if (owner != null && owner != subscriptionId) {
            return 'Requested MSISDN is already assigned to another line.';
        }
        return null;
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        PortabilityService.PortabilityInput input
    ) {
        String detail = 'Port ' + input.direction + ' to ' +
            input.requestedMsisdn + '. MSISDN changes only after confirmation.';
        String comment = String.isBlank(input.customerComment)
            ? detail
            : detail + ' Customer comment: ' + input.customerComment;

        LifecycleRequestService.RequestInput intake =
            new LifecycleRequestService.RequestInput();
        intake.requestType = PortabilityPolicy.REQUEST_TYPE;
        intake.accountId = input.accountId;
        intake.contactId = input.contactId;
        intake.subscriptionId = input.subscriptionId;
        intake.channel = input.channel;
        intake.customerComment = comment.left(1000);
        intake.goodwillWaiver = input.goodwillWaiver;
        intake.goodwillJustification = input.goodwillJustification;
        intake.priority = input.priority;
        return intake;
    }

    public static String confirmationError(
        PortabilityService.ConfirmationInput input,
        Customer_Request__c request,
        Subscription__c subscription,
        Map<String, Id> owners
    ) {
        if (input == null || input.requestId == null) {
            return 'Portability request is required.';
        }
        if (request == null) {
            return 'Portability request could not be found.';
        }
        if (request.Request_Type__c != PortabilityPolicy.REQUEST_TYPE) {
            return 'Request is not a portability request.';
        }
        if (!PortabilityPolicy.OUTCOMES.contains(input.outcome)) {
            return 'Outcome must be Confirmed or Rejected.';
        }
        if (
            PortabilityPolicy.OUTCOME_REJECTED == input.outcome &&
            String.isBlank(input.rejectionReason)
        ) {
            return 'Rejection reason is required when the donor rejects a port.';
        }
        if (
            PortabilityPolicy.OUTCOME_CONFIRMED == input.outcome &&
            String.isBlank(input.confirmationReference)
        ) {
            return 'Confirmation reference is required for a confirmed port.';
        }
        if (request.Status__c == PortabilityPolicy.STATUS_AWAITING) {
            return 'Approval is required before this port can be applied.';
        }
        if (
            PortabilityPolicy.STATUS_COMPLETED == request.Status__c ||
            PortabilityPolicy.STATUS_REJECTED == request.Status__c
        ) {
            return null;
        }
        if (
            request.Status__c != PortabilityPolicy.STATUS_APPROVED &&
            request.Status__c != PortabilityPolicy.STATUS_IN_FULFILMENT
        ) {
            return 'Portability request is not in a state that can be confirmed.';
        }
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (
            PortabilityPolicy.OUTCOME_CONFIRMED == input.outcome &&
            !PortabilityPolicy.DIRECTIONS.contains(request.Port_Direction__c)
        ) {
            return 'Port direction is missing from the request.';
        }
        if (
            PortabilityPolicy.OUTCOME_CONFIRMED == input.outcome &&
            PortabilityPolicy.DIRECTION_OUTBOUND == request.Port_Direction__c &&
            String.isBlank(subscription.MSISDN__c)
        ) {
            return 'The line has no MSISDN to release.';
        }
        if (
            PortabilityPolicy.OUTCOME_CONFIRMED == input.outcome &&
            PortabilityPolicy.DIRECTION_INBOUND == request.Port_Direction__c
        ) {
            if (!PortabilityPolicy.validMsisdn(request.Requested_MSISDN__c)) {
                return 'Requested MSISDN on the port request is invalid.';
            }
            if (request.Requested_MSISDN__c == subscription.MSISDN__c) {
                return 'Requested MSISDN is already assigned to this line.';
            }
            String duplicate = duplicateError(
                request.Requested_MSISDN__c,
                subscription.Id,
                owners
            );
            if (duplicate != null) {
                return duplicate;
            }
        }
        return null;
    }
}
