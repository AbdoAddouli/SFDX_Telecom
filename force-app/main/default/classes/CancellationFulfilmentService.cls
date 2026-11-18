/**
 * UC-LIF-03 step 2 façade. Fulfils due cancellations atomically: BSS
 * de-provision first, then all Salesforce writes inside one savepoint.
 */
public with sharing class CancellationFulfilmentService {
    public static List<CancellationFulfilmentResult> fulfil(
        List<Customer_Request__c> requests
    ) {
        List<CancellationFulfilmentResult> results =
            new List<CancellationFulfilmentResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < requests.size(); i++) {
            CancellationFulfilmentResult result =
                new CancellationFulfilmentResult();
            result.requestId = requests[i] == null ? null : requests[i].Id;
            results.add(result);
        }

        Date today = Date.today();
        List<CancellationFulfilmentItem> items =
            new List<CancellationFulfilmentItem>();
        for (Integer i = 0; i < requests.size(); i++) {
            String error =
                CancellationFulfilmentValidator.error(requests[i], today);
            if (error != null) {
                results[i].failed(error);
                continue;
            }
            CancellationFulfilmentItem item = new CancellationFulfilmentItem();
            item.resultIndex = i;
            item.request = requests[i];
            item.subscription = requests[i].Subscription__r;
            items.add(item);
        }
        if (items.isEmpty()) {
            return results;
        }

        String correlationId = CancellationFulfilmentPolicy.correlationId(
            items[0].request.Id
        );
        Savepoint savepoint = Database.setSavepoint();
        try {
            CancellationBssClient.CallResult call =
                CancellationBssClient.deprovision(items, correlationId);
            Map<Id, BssProvisioningResponse> responses =
                new Map<Id, BssProvisioningResponse>();
            for (BssProvisioningResponse response : call.responses) {
                responses.put(response.subscriptionId, response);
            }
            for (CancellationFulfilmentItem item : items) {
                item.response = responses.get(item.subscription.Id);
                if (item.response == null) {
                    throw new CancellationFulfilmentException(
                        'The BSS response did not cover every subscription.'
                    );
                }
            }

            CancellationFulfilmentWriter.apply(items);
            CancellationFulfilmentLogger.success(
                items,
                correlationId,
                call.durationMs
            );
            for (CancellationFulfilmentItem item : items) {
                results[item.resultIndex].completed();
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            String message = friendlyMessage(exceptionRecord);
            CancellationFulfilmentLogger.failure(items, correlationId, message);
            for (CancellationFulfilmentItem item : items) {
                results[item.resultIndex].failed(message);
            }
        }
        return results;
    }

    private static String friendlyMessage(Exception exceptionRecord) {
        if (exceptionRecord instanceof CancellationFulfilmentException) {
            return exceptionRecord.getMessage().left(255);
        }
        return 'Cancellation fulfilment could not be completed. Review the request and retry.';
    }
}
