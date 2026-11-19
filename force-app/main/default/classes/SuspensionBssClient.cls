/**
 * BSS boundary for suspension/unfreeze. The simulated gateway is the default
 * until E8; tests inject failures and count calls here.
 */
public with sharing class SuspensionBssClient {
    @TestVisible
    private static BssSuspensionGateway gateway =
        new SimulatedBssProvisioningGateway();

    public class CallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    public static CallResult changeState(List<SuspensionContext> items) {
        CallResult result = new CallResult();
        result.responses = new List<BssProvisioningResponse>();
        result.durationMs = 0;
        if (items == null || items.isEmpty()) {
            return result;
        }

        Map<String, List<BssProvisioningRequest>> grouped =
            new Map<String, List<BssProvisioningRequest>>();
        List<BssProvisioningRequest> allRequests =
            new List<BssProvisioningRequest>();
        for (SuspensionContext item : items) {
            BssProvisioningRequest request = request(item);
            if (!grouped.containsKey(item.action)) {
                grouped.put(item.action, new List<BssProvisioningRequest>());
            }
            grouped.get(item.action).add(request);
            allRequests.add(request);
        }

        String correlationId = SuspensionPolicy.correlationId(
            items[0].request.Id
        );
        DateTime started = System.now();
        for (String action : grouped.keySet()) {
            List<BssProvisioningRequest> batch = grouped.get(action);
            List<BssProvisioningResponse> responses = action ==
                SuspensionPolicy.ACTION_UNFREEZE
                ? gateway.resume(batch)
                : gateway.suspend(batch);
            if (responses == null || responses.size() != batch.size()) {
                throw new SuspensionService.SuspensionException(
                    'The BSS returned an incomplete state-change response.'
                );
            }
            result.responses.addAll(responses);
        }
        result.durationMs = elapsedMs(started);

        Map<Id, BssProvisioningResponse> bySubscription =
            new Map<Id, BssProvisioningResponse>();
        for (BssProvisioningResponse response : result.responses) {
            if (response == null || response.subscriptionId == null) {
                throw new SuspensionService.SuspensionException(
                    'The BSS response did not identify a subscription.'
                );
            }
            if (response.success != true) {
                throw new SuspensionService.SuspensionException(
                    String.isBlank(response.message)
                        ? 'The BSS rejected the suspension request.'
                        : response.message
                );
            }
            bySubscription.put(response.subscriptionId, response);
        }
        for (BssProvisioningRequest request : allRequests) {
            if (!bySubscription.containsKey(request.subscriptionId)) {
                throw new SuspensionService.SuspensionException(
                    'The BSS response did not cover every subscription.'
                );
            }
        }
        return result;
    }

    @TestVisible
    public static void setGateway(BssSuspensionGateway replacement) {
        gateway = replacement;
    }

    private static BssProvisioningRequest request(SuspensionContext item) {
        Subscription__c subscription = item.subscription;
        if (String.isBlank(subscription.Name)) {
            throw new SuspensionService.SuspensionException(
                'A subscription number is required for BSS idempotency.'
            );
        }
        BssProvisioningRequest request = new BssProvisioningRequest();
        request.subscriptionId = subscription.Id;
        request.subscriptionNumber = subscription.Name;
        request.idempotencyKey = SuspensionPolicy.idempotencyKey(
            subscription,
            item.action,
            item.request.Id
        );
        request.correlationId = SuspensionPolicy.correlationId(
            item.request.Id
        );
        request.serviceLineType = subscription.Service_Line_Type__c;
        request.productCode = subscription.Product__r == null
            ? null
            : subscription.Product__r.ATS_Product_Code__c;
        return request;
    }

    private static Integer elapsedMs(DateTime start) {
        return (Integer) (System.now().getTime() - start.getTime());
    }
}
