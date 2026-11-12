/**
 * E8 replacement point. Until the real BSS named credential and callout are
 * delivered, this gateway records a deterministic simulated confirmation so
 * the activation transaction can be exercised end to end.
 */
public class SimulatedBssProvisioningGateway implements BssProvisioningGateway {
    public List<BssProvisioningResponse> provision(
        List<BssProvisioningRequest> requests
    ) {
        List<BssProvisioningResponse> responses =
            new List<BssProvisioningResponse>();

        for (BssProvisioningRequest request : requests) {
            BssProvisioningResponse response = new BssProvisioningResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = true;
            response.externalReference = (
                'SIM-' + request.subscriptionNumber
            ).left(64);
            response.statusCode = '200';
            response.message =
                'Simulated BSS provisioning. E8 callout not connected yet.';
            response.durationMs = 0;
            response.endpoint = 'simulated://bss/provision';
            responses.add(response);
        }

        return responses;
    }
}
