/**
 * E8 replacement point for equipment swaps. Kept separate from the schedulable
 * provisioning gateway so pending ATS jobs never block a swap deployment.
 */
public class SimulatedBssEquipmentSwapGateway implements BssEquipmentSwapGateway {
    public List<BssProvisioningResponse> swap(
        List<BssEquipmentSwapRequest> requests
    ) {
        List<BssProvisioningResponse> responses =
            new List<BssProvisioningResponse>();
        for (BssEquipmentSwapRequest request : requests) {
            BssProvisioningResponse response = new BssProvisioningResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = true;
            response.externalReference = (
                'SIM-SWAP-' + request.subscriptionNumber
            ).left(64);
            response.statusCode = '200';
            response.message =
                'Simulated BSS device swap. E8 callout not connected yet.';
            response.durationMs = 0;
            response.endpoint = 'simulated://bss/device/swap';
            responses.add(response);
        }
        return responses;
    }
}
