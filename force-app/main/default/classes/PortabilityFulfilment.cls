/**
 * Applies confirmed ports and donor rejections atomically. Confirmed ports
 * call BSS first, then write all Salesforce changes inside one savepoint.
 */
public with sharing class PortabilityFulfilment {
    public static void apply(List<PortabilityContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            PortabilityBssClient.CallResult call =
                PortabilityBssClient.applyPort(contexts);
            for (PortabilityContext context : contexts) {
                if (
                    PortabilityPolicy.DIRECTION_INBOUND == context.direction &&
                    context.response != null &&
                    PortabilityPolicy.validMsisdn(context.response.msisdn)
                ) {
                    context.targetMsisdn = context.response.msisdn;
                }
            }
            PortabilityWriter.apply(contexts);
            PortabilityLogger.success(
                contexts,
                PortabilityPolicy.OPERATION_APPLY,
                call.durationMs
            );
            for (PortabilityContext context : contexts) {
                context.result.applied(context.targetMsisdn);
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            String message = friendlyMessage(ex);
            PortabilityLogger.failure(
                contexts,
                PortabilityPolicy.OPERATION_APPLY,
                message,
                PortabilityPolicy.FAILURE_CODE
            );
            for (PortabilityContext context : contexts) {
                context.result.failed(message);
            }
        }
    }

    public static void reject(List<PortabilityContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            PortabilityWriter.reject(contexts);
            PortabilityLogger.failure(
                contexts,
                PortabilityPolicy.OPERATION_APPLY,
                'Donor rejected the port: ' +
                    contexts[0].confirmation.rejectionReason,
                PortabilityPolicy.REJECTION_CODE
            );
            for (PortabilityContext context : contexts) {
                context.result.rejected(
                    context.confirmation.rejectionReason
                );
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            String message = friendlyMessage(ex);
            PortabilityLogger.failure(
                contexts,
                PortabilityPolicy.OPERATION_APPLY,
                message,
                PortabilityPolicy.FAILURE_CODE
            );
            for (PortabilityContext context : contexts) {
                context.result.failed(message);
            }
        }
    }

    private static String friendlyMessage(Exception ex) {
        if (ex instanceof PortabilityException) {
            return ex.getMessage();
        }
        return 'Port confirmation could not be applied. Please review and retry.';
    }
}
