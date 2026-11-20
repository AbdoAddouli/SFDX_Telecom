/**
 * UC-LIF-05 constants and pure policy helpers.
 *
 * The commercial decision on a separate restocking fee (BQ5/Q7) is still open,
 * so this path is deliberately fee-free. The breakdown is stamped on the
 * request so a later policy change can be audited without rewriting history.
 */
public with sharing class EquipmentSwapPolicy {
    public static final String REQUEST_TYPE = 'EquipmentSwap';

    public static final String STATUS_AWAITING = LifecycleRequestPolicy.STATUS_AWAITING;
    public static final String STATUS_APPROVED = LifecycleRequestPolicy.STATUS_APPROVED;
    public static final String STATUS_COMPLETED = LifecycleRequestPolicy.STATUS_COMPLETED;
    public static final String STATUS_REJECTED = 'Rejected';

    public static final String OLD_ASSET_STATUS = 'Retired';
    public static final String OLD_ASSET_PROVISIONED_STATUS = 'Superseded';
    public static final String NEW_ASSET_STATUS = 'Installed';
    public static final String NEW_ASSET_PROVISIONED_STATUS = 'Active';

    public static final String OPERATION_SWAP = 'swapDevice';
    public static final String ENDPOINT = 'simulated://bss/device/swap';
    public static final String SUCCESS_CODE = '200';
    public static final String FAILURE_CODE = '500';

    public static final Decimal FEE = 0;
    public static final String FEE_BREAKDOWN =
        'No fee applied. Device swap is fee-free under current policy; ' +
        'BQ5/Q7 restocking-fee decision remains open.';

    public static final Set<String> IN_FLIGHT_STATUSES = new Set<String>{
        STATUS_AWAITING,
        STATUS_APPROVED,
        'In_Fulfilment'
    };

    public static String correlationId(Id requestId) {
        String raw = 'SWAP-' + String.valueOf(requestId);
        return truncate(raw, 64);
    }

    public static String idempotencyKey(String subscriptionNumber) {
        String raw = 'SWAP-' + subscriptionNumber;
        return truncate(raw, 64);
    }

    public static String reference(String requestId) {
        return 'SIM-SWAP-' + String.valueOf(requestId).left(12);
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}
