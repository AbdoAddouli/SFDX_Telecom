/**
 * UC-LIF-07 phase one: validate, create the shared request/Case pair, ask BSS
 * for a port reference, and stamp the request without changing the MSISDN.
 */
public with sharing class PortabilityIntake {
    public static List<PortabilityService.PortabilityResult> execute(
        List<PortabilityService.PortabilityInput> inputs
    ) {
        List<PortabilityService.PortabilityResult> results =
            new List<PortabilityService.PortabilityResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new PortabilityService.PortabilityResult());
        }

        Set<Id> subscriptionIds = new Set<Id>();
        Set<String> msisdns = new Set<String>();
        for (PortabilityService.PortabilityInput input : inputs) {
            if (input != null) {
                if (input.subscriptionId != null) {
                    subscriptionIds.add(input.subscriptionId);
                }
                if (
                    PortabilityPolicy.DIRECTION_INBOUND == input.direction &&
                    String.isNotBlank(input.requestedMsisdn)
                ) {
                    msisdns.add(input.requestedMsisdn);
                }
            }
        }

        Map<Id, Subscription__c> subscriptions =
            PortabilityRepository.subscriptions(subscriptionIds);
        Map<Id, Customer_Request__c> inFlight =
            PortabilityRepository.inFlightBySubscription(subscriptionIds);
        Map<String, Id> owners = PortabilityRepository.msisdnOwners(msisdns);

        List<PortabilityContext> contexts = new List<PortabilityContext>();
        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        Set<String> requestedInBatch = new Set<String>();

        for (Integer i = 0; i < inputs.size(); i++) {
            PortabilityService.PortabilityInput input = inputs[i];
            PortabilityService.PortabilityResult result = results[i];
            if (input != null) {
                result.subscriptionId = input.subscriptionId;
                result.direction = input.direction;
                result.requestedMsisdn = input.requestedMsisdn;
            }

            String error = PortabilityValidator.inputError(input);
            if (error == null) {
                error = PortabilityValidator.subscriptionError(
                    subscriptions.get(input.subscriptionId),
                    input
                );
            }
            if (
                error == null &&
                inFlight.containsKey(input.subscriptionId)
            ) {
                error =
                    'An active portability request already exists for this subscription.';
            }
            if (
                error == null &&
                PortabilityPolicy.DIRECTION_INBOUND == input.direction
            ) {
                if (requestedInBatch.contains(input.requestedMsisdn)) {
                    error =
                        'Requested MSISDN is used by another request in this batch.';
                } else {
                    error = PortabilityValidator.duplicateError(
                        input.requestedMsisdn,
                        input.subscriptionId,
                        owners
                    );
                    requestedInBatch.add(input.requestedMsisdn);
                }
            }
            if (error != null) {
                result.failed(error);
                continue;
            }

            Subscription__c subscription =
                subscriptions.get(input.subscriptionId);
            PortabilityContext context = new PortabilityContext();
            context.resultIndex = i;
            context.attempted = true;
            context.result = result;
            context.input = input;
            context.subscription = subscription;
            context.direction = input.direction;
            context.requestedMsisdn = input.requestedMsisdn;
            context.previousMsisdn = subscription.MSISDN__c;
            context.targetMsisdn = PortabilityPolicy.targetMsisdn(
                input.direction,
                input.requestedMsisdn
            );
            contexts.add(context);
            intakeInputs.add(PortabilityValidator.toIntakeInput(input));
        }

        if (intakeInputs.isEmpty()) {
            return results;
        }

        Savepoint savepoint = Database.setSavepoint();
        List<PortabilityContext> ready = new List<PortabilityContext>();
        try {
            List<LifecycleRequestService.RequestOutput> created =
                LifecycleRequestService.createRequests(intakeInputs);
            if (created == null || created.size() != contexts.size()) {
                throw new PortabilityException(
                    'The shared request service returned an incomplete result set.'
                );
            }

            Set<Id> requestIds = new Set<Id>();
            for (LifecycleRequestService.RequestOutput item : created) {
                if (item.requestId != null) {
                    requestIds.add(item.requestId);
                }
            }
            Map<Id, Customer_Request__c> requests =
                PortabilityRepository.requests(requestIds);

            for (Integer j = 0; j < created.size(); j++) {
                LifecycleRequestService.RequestOutput item = created[j];
                PortabilityContext context = contexts[j];
                context.result.requestId = item.requestId;
                context.result.caseId = item.caseId;
                context.result.calculatedFee = item.fee;
                if (item.success == false || item.requestId == null) {
                    context.result.failed(item.message);
                    continue;
                }
                context.request = requests.get(item.requestId);
                if (context.request == null) {
                    throw new PortabilityException(
                        'The portability request could not be reloaded.'
                    );
                }
                context.correlationId = PortabilityPolicy.correlationId(
                    context.request.Id
                );
                ready.add(context);
            }

            if (!ready.isEmpty()) {
                PortabilityBssClient.CallResult call =
                    PortabilityBssClient.requestPort(ready);
                for (PortabilityContext context : ready) {
                    context.requestReference =
                        context.response == null
                            ? null
                            : context.response.externalReference;
                    context.result.submitted(
                        context.request.Status__c,
                        context.requestReference
                    );
                    context.result.previousMsisdn = context.previousMsisdn;
                }
                PortabilityWriter.stampRequests(ready);
                PortabilityLogger.success(
                    ready,
                    PortabilityPolicy.OPERATION_REQUEST,
                    call.durationMs
                );
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            String message = friendlyMessage(ex);
            List<PortabilityContext> attempted = new List<PortabilityContext>();
            for (PortabilityContext context : contexts) {
                if (context.attempted) {
                    attempted.add(context);
                    context.result.failed(message);
                }
            }
            PortabilityLogger.failure(
                attempted,
                PortabilityPolicy.OPERATION_REQUEST,
                message,
                PortabilityPolicy.FAILURE_CODE
            );
        }
        return results;
    }

    private static String friendlyMessage(Exception ex) {
        if (ex instanceof PortabilityException) {
            return ex.getMessage();
        }
        return 'Port request could not be submitted. No request or Case was committed.';
    }
}
