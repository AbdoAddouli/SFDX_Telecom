/**
 * Deterministic reconciliation gateway. By default it reports no drift so the
 * nightly job is inert; tests inject an override map to introduce drift.
 */
public with sharing class SimulatedBssStatusReconciliationGateway
    implements BssStatusReconciliationGateway {
    private final Map<String, String> externalStatusByNumber;

    public SimulatedBssStatusReconciliationGateway() {
        this(new Map<String, String>());
    }

    public SimulatedBssStatusReconciliationGateway(
        Map<String, String> externalStatusByNumber
    ) {
        this.externalStatusByNumber = externalStatusByNumber == null
            ? new Map<String, String>()
            : externalStatusByNumber;
    }

    public List<BssStatusResponse> status(List<BssStatusRequest> requests) {
        List<BssStatusResponse> responses =
            new List<BssStatusResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        for (BssStatusRequest request : requests) {
            BssStatusResponse response = new BssStatusResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = true;
            response.statusCode = '200';
            response.durationMs = 0;
            response.endpoint = 'simulated://bss/status';
            response.externalStatus = String.isBlank(request.subscriptionNumber)
                ? request.localStatus
                : externalStatusByNumber.containsKey(request.subscriptionNumber)
                    ? externalStatusByNumber.get(request.subscriptionNumber)
                    : request.localStatus;
            responses.add(response);
        }
        return responses;
    }
}
