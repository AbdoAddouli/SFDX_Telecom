/**
 * Manager-approval path for UC-LIF-04. Reuses the repository, validator and
 * fulfilment helper so the approved path cannot drift from intake.
 */
public with sharing class SuspensionApproval {
    public static List<SuspensionService.SuspensionResult> execute(
        List<SuspensionService.ApprovalInput> inputs
    ) {
        List<SuspensionService.SuspensionResult> results =
            new List<SuspensionService.SuspensionResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Set<Id> requestIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new SuspensionService.SuspensionResult());
            if (inputs[i] != null && inputs[i].requestId != null) {
                requestIds.add(inputs[i].requestId);
                results[i].requestId = inputs[i].requestId;
            } else {
                results[i].failed('Request Id is required.');
            }
        }
        if (requestIds.isEmpty()) {
            return results;
        }

        Map<Id, Customer_Request__c> requests =
            SuspensionRepository.requests(requestIds);
        Set<Id> subscriptionIds = new Set<Id>();
        for (Customer_Request__c request : requests.values()) {
            if (request.Subscription__c != null) {
                subscriptionIds.add(request.Subscription__c);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            SuspensionRepository.subscriptions(subscriptionIds);

        List<SuspensionContext> approved = new List<SuspensionContext>();
        for (Integer i = 0; i < inputs.size(); i++) {
            if (inputs[i] == null || inputs[i].requestId == null) {
                continue;
            }
            Customer_Request__c request = requests.get(inputs[i].requestId);
            if (request == null) {
                results[i].failed('Request could not be found.');
                continue;
            }
            results[i].subscriptionId = request.Subscription__c;
            String action = SuspensionPolicy.action(request.Request_Type__c);
            results[i].action = action;
            if (action == null) {
                results[i].failed('This request is not a suspension request.');
                continue;
            }
            if (request.Status__c != SuspensionPolicy.STATUS_APPROVED) {
                results[i].failed(
                    'The request must be approved before it can be applied.'
                );
                continue;
            }
            Subscription__c subscription =
                subscriptions.get(request.Subscription__c);
            String error = SuspensionValidator.statusError(subscription, action);
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
        return results;
    }
}
