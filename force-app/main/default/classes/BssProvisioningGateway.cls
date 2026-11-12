/**
 * Boundary between activation and the BSS. E8 supplies the real HTTP
 * implementation; tests inject a failing implementation to prove rollback.
 */
public interface BssProvisioningGateway {
    List<BssProvisioningResponse> provision(List<BssProvisioningRequest> requests);
}
