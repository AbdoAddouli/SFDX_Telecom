/**
 * UC-COM-04: explicit Subscription__c status transition map.
 *
 * This class is the single source of truth for allowed lifecycle moves. It is
 * called by SubscriptionTriggerHandler, never by a Flow, so every DML path
 * (UI, API, data load, integration) is validated consistently.
 */
public with sharing class SubscriptionStateMachine {
    public static final String DRAFT = 'Draft';
    public static final String PENDING_ACTIVATION = 'PendingActivation';
    public static final String ACTIVE = 'Active';
    public static final String SUSPENDED = 'Suspended';
    public static final String PENDING_CANCELLATION = 'PendingCancellation';
    public static final String CANCELLED = 'Cancelled';
    public static final String SUPERSEDED = 'Superseded';

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS =
        new Map<String, Set<String>>{
            DRAFT => new Set<String>{ PENDING_ACTIVATION },
            PENDING_ACTIVATION => new Set<String>{ ACTIVE },
            ACTIVE => new Set<String>{
                SUSPENDED,
                PENDING_CANCELLATION,
                SUPERSEDED
            },
            SUSPENDED => new Set<String>{ ACTIVE },
            PENDING_CANCELLATION => new Set<String>{ CANCELLED },
            CANCELLED => new Set<String>(),
            SUPERSEDED => new Set<String>()
        };

    /**
     * @description True when the requested status move is legal. A no-op
     * update (same status) is allowed so unrelated field edits do not fail.
     */
    public static Boolean isAllowed(String fromStatus, String toStatus) {
        if (String.isBlank(fromStatus) || String.isBlank(toStatus)) {
            return false;
        }
        if (fromStatus == toStatus) {
            return true;
        }
        Set<String> allowed = ALLOWED_TRANSITIONS.get(fromStatus);
        return allowed != null && allowed.contains(toStatus);
    }

    /**
     * @description Cancelled and Superseded are terminal lifecycle states.
     */
    public static Boolean isTerminal(String status) {
        return status == CANCELLED || status == SUPERSEDED;
    }

    /**
     * @description Adds a field-level error when an update attempts an
     * illegal transition. The trigger framework calls this for every row.
     */
    public static void assertAllowed(
        Subscription__c oldRecord,
        Subscription__c newRecord
    ) {
        if (oldRecord == null || newRecord == null) {
            return;
        }

        String fromStatus = oldRecord.Status__c;
        String toStatus = newRecord.Status__c;

        if (String.isBlank(fromStatus) || String.isBlank(toStatus)) {
            newRecord.addError(
                Subscription__c.Status__c,
                'Subscription status cannot be blank.'
            );
            return;
        }

        if (!isAllowed(fromStatus, toStatus)) {
            newRecord.addError(
                Subscription__c.Status__c,
                'Illegal subscription status transition: ' +
                fromStatus +
                ' -> ' +
                toStatus +
                '.'
            );
        }
    }
}
