/**
 * E8 replacement point for number portability. BSS is never called directly
 * by the service or Flow layer.
 */
public interface BssPortabilityGateway {
    List<BssProvisioningResponse> requestPort(
        List<BssPortabilityRequest> requests
    );

    List<BssProvisioningResponse> applyPort(
        List<BssPortabilityRequest> requests
    );
}
