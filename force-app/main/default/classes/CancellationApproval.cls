/**
 * Manager-approval orchestration for UC-LIF-03. Reuses the same repository,
 * validator and scheduler as the intake path so behaviour cannot drift.
 */
public with sharing class CancellationApproval {
    public static List<CancellationService.CancellationResult> execute(
        List<CancellationService.ApprovalInput> inputs
    ) {
        List<CancellationService.CancellationResult> results =
            new List<CancellationService.CancellationResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Set<Id> requestIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new CancellationService.CancellationResult());
            if (inputs[i] != null && inputs[i].requestId != null) {
                requestIds.add(inputs[i].requestId);
            } else {
                results[i].message = 'Request Id is required.';
            }
        }
        if (requestIds.isEmpty()) {
            return results;
        }

        Map<Id, Customer_Request__c> requests =
            CancellationRepository.requests(requestIds);
        Set<Id> subscriptionIds = new Set<Id>();
        for (Customer_Request__c request : requests.values()) {
            if (request.Subscription__c != null) {
                subscriptionIds.add(request.Subscription__c);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            CancellationRepository.subscriptions(subscriptionIds);
        Date today = Date.today();

        List<CancellationScheduler.Item> items =
            new List<CancellationScheduler.Item>();
        Savepoint savepoint = Database.setSavepoint();
        try {
            for (Integer i = 0; i < inputs.size(); i++) {
                CancellationService.ApprovalInput input = inputs[i];
                if (input == null || input.requestId == null) {
                    continue;
                }
                Customer_Request__c request = requests.get(input.requestId);
                Subscription__c subscription = request == null
                    ? null
                    : subscriptions.get(request.Subscription__c);
                populate(results[i], input.requestId, request);

                if (request == null) {
                    results[i].message =
                        'Cancellation request could not be found.';
                    continue;
                }
                if (CancellationValidator.isCompleted(request)) {
                    results[i].success = true;
                    results[i].status = CancellationPolicy.STATUS_COMPLETED;
                    results[i].message = 'Cancellation was already completed.';
                    continue;
                }
                if (CancellationValidator.isAlreadyScheduled(request, subscription)) {
                    results[i].success = true;
                    results[i].status = CancellationPolicy.STATUS_IN_FULFILMENT;
                    results[i].message = 'Cancellation was already scheduled.';
                    continue;
                }
                String error = CancellationValidator.approvalError(
                    request, subscription, today
                );
                if (error != null) {
                    results[i].message = error;
                    continue;
                }

                CancellationScheduler.Item item =
                    new CancellationScheduler.Item();
                item.resultIndex = i;
                item.request = request;
                item.subscription = subscription;
                item.effectiveDate = request.Cancellation_Effective_Date__c;
                items.add(item);
            }

            if (!items.isEmpty()) {
                CancellationScheduler.schedule(items);
                for (CancellationScheduler.Item item : items) {
                    results[item.resultIndex].scheduled(item.effectiveDate);
                }
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            for (CancellationService.CancellationResult result : results) {
                if (result.requestId == null || result.success != true) {
                    continue;
                }
                result.success = false;
                result.status = 'Failed';
                result.message =
                    'The cancellation could not be scheduled. Review the request and retry.';
            }
        }
        return results;
    }

    private static void populate(
        CancellationService.CancellationResult result,
        Id requestId,
        Customer_Request__c request
    ) {
        result.requestId = requestId;
        result.caseId = request == null ? null : request.Case__c;
        result.subscriptionId = request == null ? null : request.Subscription__c;
        result.calculatedFee = request == null ? null : request.Calculated_Fee__c;
        result.cancellationEffectiveDate = request == null
            ? null
            : request.Cancellation_Effective_Date__c;
    }
}
