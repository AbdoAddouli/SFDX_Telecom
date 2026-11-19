/**
 * UC-LIF-04 intake orchestration: validate a batch, create shared requests,
 * then apply the approved state changes in bulk.
 */
public with sharing class SuspensionIntake {
    public static List<SuspensionService.SuspensionResult> execute(
        List<SuspensionService.SuspensionInput> inputs
    ) {
        List<SuspensionService.SuspensionResult> results =
            new List<SuspensionService.SuspensionResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new SuspensionService.SuspensionResult());
        }

        Set<Id> subscriptionIds = new Set<Id>();
        for (SuspensionService.SuspensionInput input : inputs) {
            if (input != null && input.subscriptionId != null) {
                subscriptionIds.add(input.subscriptionId);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            SuspensionRepository.subscriptions(subscriptionIds);
        Map<Id, Customer_Request__c> inFlight =
            SuspensionRepository.inFlightBySubscription(subscriptionIds);
        Set<Id> seenSubscriptionIds = new Set<Id>();

        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        Map<Integer, Integer> resultIndexByIntakeIndex =
            new Map<Integer, Integer>();
        for (Integer i = 0; i < inputs.size(); i++) {
            String error = SuspensionValidator.inputError(inputs[i]);
            if (error == null) {
                error = SuspensionValidator.statusError(
                    subscriptions.get(inputs[i].subscriptionId),
                    inputs[i].action
                );
            }
            if (
                error == null &&
                (inFlight.containsKey(inputs[i].subscriptionId) ||
                seenSubscriptionIds.contains(inputs[i].subscriptionId))
            ) {
                error = 'A suspension request is already in flight for this line.';
            }
            if (error != null) {
                results[i].action = inputs[i] == null ? null : inputs[i].action;
                results[i].failed(error);
                continue;
            }
            seenSubscriptionIds.add(inputs[i].subscriptionId);
            resultIndexByIntakeIndex.put(intakeInputs.size(), i);
            intakeInputs.add(SuspensionValidator.toIntakeInput(inputs[i]));
        }
        if (intakeInputs.isEmpty()) {
            return results;
        }

        List<LifecycleRequestService.RequestOutput> outputs =
            LifecycleRequestService.createRequests(intakeInputs);
        List<SuspensionContext> approved = new List<SuspensionContext>();
        Set<Id> approvedRequestIds = new Set<Id>();

        for (Integer j = 0; j < outputs.size(); j++) {
            Integer i = resultIndexByIntakeIndex.get(j);
            if (i == null) {
                continue;
            }
            SuspensionService.SuspensionInput input = inputs[i];
            LifecycleRequestService.RequestOutput output = outputs[j];
            results[i].action = input.action;
            results[i].requestId = output.requestId;
            results[i].caseId = output.caseId;
            results[i].subscriptionId = input.subscriptionId;
            results[i].calculatedFee = output.fee;

            if (!output.success || output.requestId == null) {
                results[i].failed(output.message);
                continue;
            }
            results[i].success = true;
            results[i].status = output.status;

            if (output.status == SuspensionPolicy.STATUS_AWAITING) {
                results[i].awaiting();
                continue;
            }
            if (output.status != SuspensionPolicy.STATUS_APPROVED) {
                results[i].failed(
                    'The suspension request is not ready for fulfilment.'
                );
                continue;
            }
            approvedRequestIds.add(output.requestId);
        }

        if (!approvedRequestIds.isEmpty()) {
            Map<Id, Customer_Request__c> requests =
                SuspensionRepository.requests(approvedRequestIds);
            for (Integer j = 0; j < outputs.size(); j++) {
                Integer i = resultIndexByIntakeIndex.get(j);
                if (i == null) {
                    continue;
                }
                LifecycleRequestService.RequestOutput output = outputs[j];
                if (
                    output.requestId == null ||
                    output.status != SuspensionPolicy.STATUS_APPROVED
                ) {
                    continue;
                }
                Customer_Request__c request = requests.get(output.requestId);
                String action = request == null
                    ? null
                    : SuspensionPolicy.action(request.Request_Type__c);
                Subscription__c subscription =
                    subscriptions.get(inputs[i].subscriptionId);
                String error = SuspensionValidator.statusError(
                    subscription,
                    action
                );
                if (error != null) {
                    results[i].failed(error);
                    continue;
                }

                SuspensionContext context = new SuspensionContext();
                context.resultIndex = i;
                context.result = results[i];
                context.request = request;
                context.subscription = subscription;
                context.action = action;
                context.targetStatus = SuspensionPolicy.targetStatus(action);
                approved.add(context);
            }
            SuspensionFulfilment.apply(approved);
        }
        return results;
    }
}
