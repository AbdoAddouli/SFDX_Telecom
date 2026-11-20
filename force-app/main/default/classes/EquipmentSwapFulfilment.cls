/**
 * Applies approved device swaps atomically. BSS is called first; every
 * Salesforce write rolls back if BSS rejects the swap. The request stays
 * Approved so a later manager retry can reuse the same idempotency key.
 */
public with sharing class EquipmentSwapFulfilment {
    public static void apply(List<EquipmentSwapContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            EquipmentSwapBssClient.CallResult call =
                EquipmentSwapBssClient.swap(contexts);
            for (EquipmentSwapContext context : contexts) {
                context.bssReference = context.response != null
                    ? context.response.externalReference
                    : null;
            }
            EquipmentSwapWriter.apply(contexts);
            EquipmentSwapLogger.success(contexts, call.durationMs);
            for (EquipmentSwapContext context : contexts) {
                context.result.completed(context);
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            EquipmentSwapLogger.failure(
                contexts,
                ex.getMessage(),
                EquipmentSwapPolicy.FAILURE_CODE
            );
            for (EquipmentSwapContext context : contexts) {
                context.result.failed(
                    'Device swap could not be applied. ' + ex.getMessage()
                );
            }
        }
    }
}
