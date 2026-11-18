/**
 * Cancellation fulfilment constants. Keeping terminal status values in one
 * place prevents drift between the batch, writer and tests.
 */
public with sharing class CancellationFulfilmentPolicy {
    public static final String ASSET_RETIRED = 'Retired';
    public static final String CONTRACT_TERMINATED = 'Terminated';
    public static final String ENGAGEMENT_BREACHED = 'Breached';
    public static final String EXTERNAL_CANCELLED = 'Cancelled';
    public static final String CASE_CLOSED = 'Closed';
    public static final String ACCOUNT_CHURNED = 'Churned';
    public static final String OPERATION = 'cancelSubscription';
    public static final String ENDPOINT = 'simulated://bss/deprovision';
    public static final String SUCCESS_CODE = '200';
    public static final String FAILURE_CODE = '500';

    public static String correlationId(String requestId) {
        return ('CANCEL-' + requestId).left(64);
    }

    public static String idempotencyKey(
        Subscription__c subscription,
        Date effectiveDate
    ) {
        return (subscription.Name + ':' + effectiveDate).left(64);
    }
}
