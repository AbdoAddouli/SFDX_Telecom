/**
 * BSS boundary for cancellation fulfilment. The simulated gateway remains the
 * default until E8 delivers the real callout; tests inject failures here.
 */
public with sharing class CancellationBssClient {
    @TestVisible
    private static BssDeprovisioningGateway gateway =
        new SimulatedBssProvisioningGateway();

    public class CallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    public static CallResult deprovision(
        List<CancellationFulfilmentItem> items,
        String correlationId
    ) {
        CallResult result = new CallResult();
        result.responses = new List<BssProvisioningResponse>();
        result.durationMs = 0;

        List<BssProvisioningRequest> requests =
            new List<BssProvisioningRequest>();
        for (CancellationFulfilmentItem item : items) {
            requests.add(request(item, correlationId));
        }
        if (requests.isEmpty()) {
            return result;
        }

        DateTime started = System.now();
        List<BssProvisioningResponse> responses = gateway.deprovision(requests);
        result.durationMs = elapsedMs(started);

        if (responses == null || responses.size() != requests.size()) {
            throw new CancellationFulfilmentException(
                'The BSS returned an incomplete de-provisioning response.'
            );
        }

        Map<Id, BssProvisioningResponse> bySubscription =
            new Map<Id, BssProvisioningResponse>();
        for (BssProvisioningResponse response : responses) {
            if (response == null || response.subscriptionId == null) {
                throw new CancellationFulfilmentException(
                    'The BSS response did not identify a subscription.'
                );
            }
            if (response.success != true) {
                throw new CancellationFulfilmentException(
                    String.isBlank(response.message)
                        ? 'The BSS rejected the de-provisioning request.'
                        : response.message
                );
            }
            bySubscription.put(response.subscriptionId, response);
        }

        for (BssProvisioningRequest request : requests) {
            if (!bySubscription.containsKey(request.subscriptionId)) {
                throw new CancellationFulfilmentException(
                    'The BSS response did not cover every subscription.'
                );
            }
        }

        result.responses = responses;
        return result;
    }

    @TestVisible
    public static void setGateway(BssDeprovisioningGateway replacement) {
        gateway = replacement;
    }

    private static BssProvisioningRequest request(
        CancellationFulfilmentItem item,
        String correlationId
    ) {
        Subscription__c subscription = item.subscription;
        if (String.isBlank(subscription.Name)) {
            throw new CancellationFulfilmentException(
                'A subscription number is required for BSS idempotency.'
            );
        }
        BssProvisioningRequest request = new BssProvisioningRequest();
        request.subscriptionId = subscription.Id;
        request.subscriptionNumber = subscription.Name;
        request.idempotencyKey = CancellationFulfilmentPolicy.idempotencyKey(
            subscription,
            item.request.Cancellation_Effective_Date__c
        );
        request.correlationId = correlationId;
        request.serviceLineType = subscription.Service_Line_Type__c;
        request.productCode = subscription.Product__r == null
            ? null
            : subscription.Product__r.ATS_Product_Code__c;
        request.accountName = item.request.Account__r == null
            ? null
            : item.request.Account__r.Name;
        return request;
    }

    private static Integer elapsedMs(DateTime start) {
        return (Integer) (System.now().getTime() - start.getTime());
    }
}
