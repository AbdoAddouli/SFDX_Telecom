/**
 * BSS boundary for UC-LIF-07. The simulated gateway is the default until E8;
 * tests inject failures and count calls here. No Salesforce DML happens here.
 */
public with sharing class PortabilityBssClient {
    @TestVisible
    private static BssPortabilityGateway gateway =
        new SimulatedBssPortabilityGateway();

    public class CallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    public static CallResult requestPort(List<PortabilityContext> contexts) {
        return call(contexts, PortabilityPolicy.OPERATION_REQUEST);
    }

    public static CallResult applyPort(List<PortabilityContext> contexts) {
        return call(contexts, PortabilityPolicy.OPERATION_APPLY);
    }

    public static void setGateway(BssPortabilityGateway replacement) {
        gateway = replacement;
    }

    private static CallResult call(
        List<PortabilityContext> contexts,
        String operation
    ) {
        CallResult result = new CallResult();
        result.responses = new List<BssProvisioningResponse>();
        result.durationMs = 0;
        if (contexts == null || contexts.isEmpty()) {
            return result;
        }

        List<BssPortabilityRequest> payloads =
            new List<BssPortabilityRequest>();
        for (PortabilityContext context : contexts) {
            payloads.add(payload(context, operation));
        }

        List<BssProvisioningResponse> responses;
        try {
            responses = operation == PortabilityPolicy.OPERATION_APPLY
                ? gateway.applyPort(payloads)
                : gateway.requestPort(payloads);
        } catch (Exception ex) {
            throw new PortabilityException(
                'BSS port ' +
                (operation == PortabilityPolicy.OPERATION_APPLY
                    ? 'application'
                    : 'request') +
                ' failed. ' +
                ex.getMessage()
            );
        }

        if (responses == null || responses.size() != payloads.size()) {
            throw new PortabilityException(
                'BSS returned an incomplete port response set.'
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

        for (PortabilityContext context : contexts) {
            BssProvisioningResponse response =
                bySubscription.get(context.subscription.Id);
            if (response == null || response.success != true) {
                String detail = response == null
                    ? 'No response was returned.'
                    : response.message;
                throw new PortabilityException(
                    'BSS rejected the port ' +
                    (operation == PortabilityPolicy.OPERATION_APPLY
                        ? 'application'
                        : 'request') +
                    '. ' +
                    detail
                );
            }
            context.response = response;
            result.responses.add(response);
        }
        return result;
    }

    private static BssPortabilityRequest payload(
        PortabilityContext context,
        String operation
    ) {
        if (context.subscription == null || context.subscription.Id == null) {
            throw new PortabilityException('Subscription is required for BSS.');
        }
        if (String.isBlank(context.subscription.Name)) {
            throw new PortabilityException(
                'Subscription number is required for BSS idempotency.'
            );
        }

        BssPortabilityRequest request = new BssPortabilityRequest();
        request.subscriptionId = context.subscription.Id;
        request.subscriptionNumber = context.subscription.Name;
        request.idempotencyKey = context.subscription.Name;
        request.correlationId = context.correlationId;
        request.msisdn = context.requestedMsisdn;
        request.direction = context.direction;
        request.requestReference = context.requestReference;
        request.confirmationReference = context.confirmationReference;
        return request;
    }
}
