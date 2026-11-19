/**
 * BSS boundary for reversible line suspension. Kept separate so activation,
 * cancellation and suspension can be swapped independently in E8 and in tests.
 */
public interface BssSuspensionGateway {
    List<BssProvisioningResponse> suspend(List<BssProvisioningRequest> requests);

    List<BssProvisioningResponse> resume(List<BssProvisioningRequest> requests);
}
