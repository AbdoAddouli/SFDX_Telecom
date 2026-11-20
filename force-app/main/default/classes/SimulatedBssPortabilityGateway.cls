/**
 * E8 replacement point for number portability. Kept separate from the
 * schedulable provisioning gateway so scheduled ATS jobs never block a port
 * deployment. Deterministic references make phase one and phase two auditable.
 */
public class SimulatedBssPortabilityGateway implements BssPortabilityGateway {
    public List<BssProvisioningResponse> requestPort(
        List<BssPortabilityRequest> requests
    ) {
        return port(requests, 'REQ', 'request');
    }

    public List<BssProvisioningResponse> applyPort(
        List<BssPortabilityRequest> requests
    ) {
        return port(requests, 'APPLY', 'apply');
    }

    private static List<BssProvisioningResponse> port(
        List<BssPortabilityRequest> requests,
        String prefix,
        String operation
    ) {
        List<BssProvisioningResponse> responses =
            new List<BssProvisioningResponse>();
        for (BssPortabilityRequest request : requests) {
            BssProvisioningResponse response = new BssProvisioningResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = true;
            response.externalReference = (
                'SIM-PORT-' + prefix + '-' + request.subscriptionNumber
            ).left(64);
            response.msisdn = request.msisdn;
            response.statusCode = '200';
            response.message =
                'Simulated BSS port ' +
                operation +
                '. E8 callout not connected yet.';
            response.durationMs = 0;
            response.endpoint = 'simulated://bss/port/' + operation;
            responses.add(response);
        }
        return responses;
    }
}
