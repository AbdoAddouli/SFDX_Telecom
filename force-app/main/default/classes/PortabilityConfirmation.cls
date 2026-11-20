/**
 * UC-LIF-07 phase two: load the approved port request, validate the donor
 * outcome, then apply or reject it through the atomic fulfilment helpers.
 */
public with sharing class PortabilityConfirmation {
    public static List<PortabilityService.PortabilityResult> execute(
        List<PortabilityService.ConfirmationInput> inputs
    ) {
        List<PortabilityService.PortabilityResult> results =
            new List<PortabilityService.PortabilityResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new PortabilityService.PortabilityResult());
        }

        Set<Id> requestIds = new Set<Id>();
        for (PortabilityService.ConfirmationInput input : inputs) {
            if (input != null && input.requestId != null) {
                requestIds.add(input.requestId);
            }
        }
        Map<Id, Customer_Request__c> requests =
            PortabilityRepository.requests(requestIds);

        Set<Id> subscriptionIds = new Set<Id>();
        Set<String> inboundMsisdns = new Set<String>();
        for (Customer_Request__c request : requests.values()) {
            if (request.Subscription__c != null) {
                subscriptionIds.add(request.Subscription__c);
            }
            if (
                PortabilityPolicy.DIRECTION_INBOUND == request.Port_Direction__c &&
                String.isNotBlank(request.Requested_MSISDN__c)
            ) {
                inboundMsisdns.add(request.Requested_MSISDN__c);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            PortabilityRepository.subscriptions(subscriptionIds);
        Map<String, Id> owners =
            PortabilityRepository.msisdnOwners(inboundMsisdns);

        List<PortabilityContext> apply = new List<PortabilityContext>();
        List<PortabilityContext> reject = new List<PortabilityContext>();

        for (Integer i = 0; i < inputs.size(); i++) {
            PortabilityService.ConfirmationInput input = inputs[i];
            PortabilityService.PortabilityResult result = results[i];
            Customer_Request__c request =
                input == null ? null : requests.get(input.requestId);
            Subscription__c subscription = request == null
                ? null
                : subscriptions.get(request.Subscription__c);

            if (input != null) {
                result.requestId = input.requestId;
            }
            if (request != null) {
                result.direction = request.Port_Direction__c;
                result.requestedMsisdn = request.Requested_MSISDN__c;
                result.portRequestReference =
                    request.Port_Request_Reference__c;
                result.calculatedFee = request.Calculated_Fee__c;
                result.caseId = request.Case__c;
                result.subscriptionId = request.Subscription__c;
            }
            if (subscription != null) {
                result.previousMsisdn = subscription.MSISDN__c;
            }
            if (input != null) {
                result.portConfirmationReference =
                    input.confirmationReference;
            }

            String error = PortabilityValidator.confirmationError(
                input,
                request,
                subscription,
                owners
            );
            if (error != null) {
                result.failed(error);
                continue;
            }
            if (PortabilityPolicy.STATUS_COMPLETED == request.Status__c) {
                result.alreadyApplied(
                    subscription == null ? null : subscription.MSISDN__c
                );
                continue;
            }
            if (PortabilityPolicy.STATUS_REJECTED == request.Status__c) {
                result.alreadyRejected();
                continue;
            }

            PortabilityContext context = new PortabilityContext();
            context.resultIndex = i;
            context.result = result;
            context.confirmation = input;
            context.request = request;
            context.subscription = subscription;
            context.direction = request.Port_Direction__c;
            context.requestedMsisdn = request.Requested_MSISDN__c;
            context.previousMsisdn = subscription.MSISDN__c;
            context.targetMsisdn = PortabilityPolicy.targetMsisdn(
                request.Port_Direction__c,
                request.Requested_MSISDN__c
            );
            context.confirmationReference = input.confirmationReference;
            context.requestReference = request.Port_Request_Reference__c;
            context.correlationId = PortabilityPolicy.correlationId(
                request.Id
            );

            if (PortabilityPolicy.OUTCOME_REJECTED == input.outcome) {
                reject.add(context);
            } else {
                apply.add(context);
            }
        }

        PortabilityFulfilment.reject(reject);
        PortabilityFulfilment.apply(apply);
        return results;
    }
}
