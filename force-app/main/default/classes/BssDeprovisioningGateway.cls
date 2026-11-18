/**
 * BSS de-provisioning boundary for cancellation fulfilment. Kept separate from
 * BssProvisioningGateway so activation and cancellation can be swapped
 * independently in tests and in E8.
 */
public interface BssDeprovisioningGateway {
    List<BssProvisioningResponse> deprovision(
        List<BssProvisioningRequest> requests
    );
}
