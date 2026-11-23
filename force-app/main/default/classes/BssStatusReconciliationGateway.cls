/**
 * Boundary for nightly BSS status reconciliation. The simulated implementation
 * is the default until the real endpoint/auth is supplied and the live flag is
 * enabled.
 */
public interface BssStatusReconciliationGateway {
    List<BssStatusResponse> status(List<BssStatusRequest> requests);
}
