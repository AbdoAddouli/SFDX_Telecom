/**
 * Applies an approved suspension/unfreeze batch atomically: BSS state change
 * first, then all Salesforce writes inside one savepoint.
 */
public with sharing class SuspensionFulfilment {
    public static void apply(List<SuspensionContext> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        String correlationId = SuspensionPolicy.correlationId(
            items[0].request.Id
        );
        Savepoint savepoint = Database.setSavepoint();
        try {
            SuspensionBssClient.CallResult call =
                SuspensionBssClient.changeState(items);
            Map<Id, BssProvisioningResponse> responses =
                new Map<Id, BssProvisioningResponse>();
            for (BssProvisioningResponse response : call.responses) {
                responses.put(response.subscriptionId, response);
            }
            for (SuspensionContext item : items) {
                item.response = responses.get(item.subscription.Id);
            }

            SuspensionWriter.apply(items);
            SuspensionLogger.success(items, correlationId, call.durationMs);
            for (SuspensionContext item : items) {
                item.result.completed(item.targetStatus);
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            String message = friendlyMessage(exceptionRecord);
            SuspensionLogger.failure(items, correlationId, message);
            for (SuspensionContext item : items) {
                item.result.failed(message);
            }
        }
    }

    private static String friendlyMessage(Exception exceptionRecord) {
        if (exceptionRecord instanceof SuspensionService.SuspensionException) {
            return exceptionRecord.getMessage().left(255);
        }
        return 'The suspension could not be applied. Review the request and retry.';
    }
}
