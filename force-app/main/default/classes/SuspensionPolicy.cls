/**
 * UC-LIF-04 constants. BQ3 is resolved as "no pause": the commitment clock,
 * Contract and Engagement are never changed by a suspension.
 */
public with sharing class SuspensionPolicy {
    public static final String ACTION_SUSPEND = 'Suspend';
    public static final String ACTION_UNFREEZE = 'Unfreeze';

    public static final String REQUEST_SUSPENSION = 'Suspension';
    public static final String REQUEST_UNFREEZE = LifecycleRequestPolicy.TYPE_UNFREEZE;

    public static final String STATUS_AWAITING = LifecycleRequestPolicy.STATUS_AWAITING;
    public static final String STATUS_APPROVED = LifecycleRequestPolicy.STATUS_APPROVED;
    public static final String STATUS_COMPLETED = LifecycleRequestPolicy.STATUS_COMPLETED;
    public static final String STATUS_FAILED = 'Failed';

    public static final String TARGET_SUSPENDED = SubscriptionStateMachine.SUSPENDED;
    public static final String TARGET_ACTIVE = SubscriptionStateMachine.ACTIVE;

    public static final String EXTERNAL_SUSPENDED = 'Suspended';
    public static final String EXTERNAL_ACTIVE = 'Active';
    public static final String CASE_CLOSED = 'Closed';

    public static final String OPERATION_SUSPEND = 'suspendSubscription';
    public static final String OPERATION_RESUME = 'resumeSubscription';
    public static final String ENDPOINT_SUSPEND = 'simulated://bss/suspend';
    public static final String ENDPOINT_RESUME = 'simulated://bss/resume';
    public static final String SUCCESS_CODE = '200';
    public static final String FAILURE_CODE = '500';

    public static final Set<String> ACTIONS = new Set<String>{
        ACTION_SUSPEND,
        ACTION_UNFREEZE
    };
    public static final Set<String> REQUEST_TYPES = new Set<String>{
        REQUEST_SUSPENSION,
        REQUEST_UNFREEZE
    };
    public static final Set<String> IN_FLIGHT_STATUSES = new Set<String>{
        STATUS_APPROVED,
        STATUS_AWAITING
    };

    public static String requestType(String action) {
        return action == ACTION_UNFREEZE ? REQUEST_UNFREEZE : REQUEST_SUSPENSION;
    }

    public static String action(String requestType) {
        if (requestType == REQUEST_UNFREEZE) {
            return ACTION_UNFREEZE;
        }
        return requestType == REQUEST_SUSPENSION ? ACTION_SUSPEND : null;
    }

    public static String targetStatus(String action) {
        return action == ACTION_UNFREEZE ? TARGET_ACTIVE : TARGET_SUSPENDED;
    }

    public static String externalStatus(String action) {
        return action == ACTION_UNFREEZE ? EXTERNAL_ACTIVE : EXTERNAL_SUSPENDED;
    }

    public static String operation(String action) {
        return action == ACTION_UNFREEZE ? OPERATION_RESUME : OPERATION_SUSPEND;
    }

    public static String endpoint(String action) {
        return action == ACTION_UNFREEZE ? ENDPOINT_RESUME : ENDPOINT_SUSPEND;
    }

    public static String correlationId(Id requestId) {
        return ('SUSPEND-' + requestId).left(64);
    }

    public static String idempotencyKey(
        Subscription__c subscription,
        String action,
        Id requestId
    ) {
        return (subscription.Name + ':' + action + ':' + requestId).left(64);
    }
}
