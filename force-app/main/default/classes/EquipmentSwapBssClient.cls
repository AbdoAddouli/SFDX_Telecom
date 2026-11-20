/**
 * BSS boundary for UC-LIF-05. The simulated gateway is the default until E8;
 * tests inject failures and count calls here. No Salesforce DML happens here.
 */
public with sharing class EquipmentSwapBssClient {
    @TestVisible
    private static BssEquipmentSwapGateway gateway =
        new SimulatedBssEquipmentSwapGateway();

    public class CallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    public static CallResult swap(List<EquipmentSwapContext> contexts) {
        CallResult result = new CallResult();
        result.responses = new List<BssProvisioningResponse>();
        result.durationMs = 0;
        if (contexts == null || contexts.isEmpty()) {
            return result;
        }

        List<BssEquipmentSwapRequest> payloads =
            new List<BssEquipmentSwapRequest>();
        for (EquipmentSwapContext context : contexts) {
            payloads.add(payload(context));
        }

        List<BssProvisioningResponse> responses;
        try {
            responses = gateway.swap(payloads);
        } catch (Exception ex) {
            throw new EquipmentSwapException(
                'BSS device swap failed. ' + ex.getMessage()
            );
        }

        if (responses == null || responses.size() != payloads.size()) {
            throw new EquipmentSwapException(
                'BSS returned an incomplete device-swap response set.'
            );
        }

        Map<Id, BssProvisioningResponse> bySubscription =
            new Map<Id, BssProvisioningResponse>();
        for (BssProvisioningResponse response : responses) {
            if (response != null && response.subscriptionId != null) {
                bySubscription.put(response.subscriptionId, response);
            }
            if (response != null && response.durationMs != null) {
                result.durationMs = Math.max(
                    result.durationMs,
                    response.durationMs
                );
            }
        }

        for (EquipmentSwapContext context : contexts) {
            BssProvisioningResponse response =
                bySubscription.get(context.subscription.Id);
            if (response == null || response.success != true) {
                String detail = response == null
                    ? 'No response was returned.'
                    : response.message;
                throw new EquipmentSwapException(
                    'BSS rejected the device swap. ' + detail
                );
            }
            context.response = response;
            result.responses.add(response);
        }
        return result;
    }

    public static void setGateway(BssEquipmentSwapGateway replacement) {
        gateway = replacement;
    }

    private static BssEquipmentSwapRequest payload(
        EquipmentSwapContext context
    ) {
        if (context.subscription == null || context.subscription.Id == null) {
            throw new EquipmentSwapException('Subscription is required for BSS.');
        }
        if (String.isBlank(context.subscription.Name)) {
            throw new EquipmentSwapException(
                'Subscription number is required for BSS idempotency.'
            );
        }

        BssEquipmentSwapRequest request = new BssEquipmentSwapRequest();
        request.subscriptionId = context.subscription.Id;
        request.subscriptionNumber = context.subscription.Name;
        request.oldAssetId = context.oldAsset != null ? context.oldAsset.Id : null;
        request.oldSerialNumber = context.oldAsset != null
            ? context.oldAsset.SerialNumber
            : null;
        request.newProductCode = context.device != null
            ? context.device.productCode
            : null;
        request.newSerialNumber = context.serialNumber;
        request.newColour = context.colour;
        request.newImageUrl = context.imageUrl;
        request.idempotencyKey = EquipmentSwapPolicy.idempotencyKey(
            context.subscription.Name
        );
        request.correlationId = context.correlationId;
        return request;
    }
}
