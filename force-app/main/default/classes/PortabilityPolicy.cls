/**
 * UC-LIF-07 constants and pure policy helpers.
 *
 * Q6/BQ10 is resolved org-wide: Subscription__c.MSISDN__c is unique when
 * populated. A port request never changes the number; only a confirmed port
 * applies the target value, and BSS remains behind a gateway until E8.
 */
public with sharing class PortabilityPolicy {
    public static final String REQUEST_TYPE = 'Portability';

    public static final String DIRECTION_INBOUND = 'Inbound';
    public static final String DIRECTION_OUTBOUND = 'Outbound';

    public static final String OUTCOME_CONFIRMED = 'Confirmed';
    public static final String OUTCOME_REJECTED = 'Rejected';

    public static final String STATUS_AWAITING = LifecycleRequestPolicy.STATUS_AWAITING;
    public static final String STATUS_APPROVED = LifecycleRequestPolicy.STATUS_APPROVED;
    public static final String STATUS_IN_FULFILMENT = 'In_Fulfilment';
    public static final String STATUS_COMPLETED = LifecycleRequestPolicy.STATUS_COMPLETED;
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String STATUS_FAILED = 'Failed';

    public static final String CASE_CLOSED = 'Closed';

    public static final String OPERATION_REQUEST = 'requestPort';
    public static final String OPERATION_APPLY = 'applyPort';

    public static final String ENDPOINT_REQUEST = 'simulated://bss/port/request';
    public static final String ENDPOINT_APPLY = 'simulated://bss/port/apply';

    public static final String SUCCESS_CODE = '200';
    public static final String FAILURE_CODE = '500';
    public static final String REJECTION_CODE = '400';

    public static final Set<String> DIRECTIONS = new Set<String>{
        DIRECTION_INBOUND,
        DIRECTION_OUTBOUND
    };
    public static final Set<String> OUTCOMES = new Set<String>{
        OUTCOME_CONFIRMED,
        OUTCOME_REJECTED
    };
    public static final Set<String> IN_FLIGHT_STATUSES = new Set<String>{
        STATUS_APPROVED,
        STATUS_AWAITING,
        STATUS_IN_FULFILMENT
    };

    /**
     * MSISDN format matches the Subscription__c.MSISDN_Format validation rule:
     * optional leading + followed by 7 to 15 digits.
     */
    public static Boolean validMsisdn(String value) {
        return String.isNotBlank(value) &&
            Pattern.matches('^\\+?[0-9]{7,15}$', value);
    }

    /**
     * Inbound ports set the requested number on the line. Outbound ports
     * release the current number, so the target is null.
     */
    public static String targetMsisdn(String direction, String requested) {
        return direction == DIRECTION_OUTBOUND ? null : requested;
    }

    public static String endpoint(String operation) {
        return operation == OPERATION_APPLY ? ENDPOINT_APPLY : ENDPOINT_REQUEST;
    }

    public static String correlationId(Id requestId) {
        return ('PORT-' + requestId).left(64);
    }
}
