/**
 * UC-LIF-03 intake orchestration: validate a batch, create shared requests,
 * then bulk-schedule the ones that are approved immediately.
 */
public with sharing class CancellationIntake {
    private class Pending {
        Integer resultIndex;
        Id requestId;
        Id subscriptionId;
        Date effectiveDate;
    }

    public static List<CancellationService.CancellationResult> execute(
        List<CancellationService.CancellationInput> inputs
    ) {
        List<CancellationService.CancellationResult> results =
            new List<CancellationService.CancellationResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new CancellationService.CancellationResult());
        }

        Set<Id> subscriptionIds = new Set<Id>();
        for (CancellationService.CancellationInput input : inputs) {
            if (input != null && input.subscriptionId != null) {
                subscriptionIds.add(input.subscriptionId);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            CancellationRepository.subscriptions(subscriptionIds);
        Map<Id, Customer_Request__c> inFlight =
            CancellationRepository.inFlightBySubscription(subscriptionIds);
        Date today = Date.today();

        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        Map<Integer, Integer> resultIndexByIntakeIndex =
            new Map<Integer, Integer>();
        Set<Id> seenSubscriptionIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            String error = CancellationValidator.intakeError(
                inputs[i], subscriptions, inFlight, seenSubscriptionIds, today
            );
            if (error != null) {
                results[i].message = error;
                continue;
            }
            resultIndexByIntakeIndex.put(intakeInputs.size(), i);
            intakeInputs.add(CancellationValidator.toIntakeInput(inputs[i]));
        }
        if (intakeInputs.isEmpty()) {
            return results;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            List<LifecycleRequestService.RequestOutput> outputs =
                LifecycleRequestService.createRequests(intakeInputs);
            List<Pending> pending = new List<Pending>();
            Set<Id> approvedRequestIds = new Set<Id>();

            for (Integer j = 0; j < outputs.size(); j++) {
                Integer i = resultIndexByIntakeIndex.get(j);
                if (i == null) {
                    continue;
                }
                CancellationService.CancellationInput input = inputs[i];
                LifecycleRequestService.RequestOutput output = outputs[j];
                results[i].requestId = output.requestId;
                results[i].caseId = output.caseId;
                results[i].subscriptionId = input.subscriptionId;
                results[i].calculatedFee = output.fee;
                results[i].cancellationEffectiveDate =
                    input.cancellationEffectiveDate;

                if (!output.success || output.requestId == null) {
                    results[i].status = 'Failed';
                    results[i].message = output.message;
                    continue;
                }
                results[i].success = true;
                results[i].status = output.status;
                if (output.status == CancellationPolicy.STATUS_AWAITING) {
                    results[i].message =
                        'Cancellation submitted and awaiting manager approval.';
                    continue;
                }
                results[i].message = 'Cancellation submitted.';
                if (output.status != CancellationPolicy.STATUS_APPROVED) {
                    continue;
                }

                Pending item = new Pending();
                item.resultIndex = i;
                item.requestId = output.requestId;
                item.subscriptionId = input.subscriptionId;
                item.effectiveDate = input.cancellationEffectiveDate;
                pending.add(item);
                approvedRequestIds.add(output.requestId);
            }

            if (!pending.isEmpty()) {
                Map<Id, Customer_Request__c> requests =
                    CancellationRepository.requests(approvedRequestIds);
                List<CancellationScheduler.Item> items =
                    new List<CancellationScheduler.Item>();
                for (Pending entry : pending) {
                    Customer_Request__c request = requests.get(entry.requestId);
                    Subscription__c subscription =
                        subscriptions.get(entry.subscriptionId);
                    if (request == null || subscription == null) {
                        throw new CancellationService.CancellationException(
                            'The approved request or subscription could not be resolved.'
                        );
                    }
                    CancellationScheduler.Item item =
                        new CancellationScheduler.Item();
                    item.resultIndex = entry.resultIndex;
                    item.request = request;
                    item.subscription = subscription;
                    item.effectiveDate = entry.effectiveDate;
                    items.add(item);
                }
                CancellationScheduler.schedule(items);
                for (CancellationScheduler.Item item : items) {
                    results[item.resultIndex].scheduled(item.effectiveDate);
                }
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            for (CancellationService.CancellationResult result : results) {
                if (result.requestId == null) {
                    continue;
                }
                result.success = false;
                result.status = 'Failed';
                result.requestId = null;
                result.caseId = null;
                result.message =
                    'The cancellation could not be scheduled. Review the entries and retry.';
            }
        }
        return results;
    }
}
