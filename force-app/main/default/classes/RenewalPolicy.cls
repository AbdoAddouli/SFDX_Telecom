/**
 * UC-LIF-06 constants. BQ4 is resolved as monthly rollover when a customer
 * lets a commitment lapse; the old engagement is always terminal.
 */
public with sharing class RenewalPolicy {
    public static final String REQUEST_TYPE = LifecycleRequestPolicy.TYPE_RENEWAL;

    public static final String DECISION_SAME_TERMS = 'RenewSameTerms';
    public static final String DECISION_NEW_PLAN = 'RenewNewPlan';
    public static final String DECISION_LAPSE = 'LetLapse';
    public static final String DECISION_CANCEL = 'CancelEarly';

    public static final String ENGAGEMENT_ACTIVE = 'Active';
    public static final String ENGAGEMENT_EXPIRED = 'Expired';
    public static final String SUBSCRIPTION_ACTIVE = SubscriptionStateMachine.ACTIVE;

    public static final String STATUS_AWAITING = LifecycleRequestPolicy.STATUS_AWAITING;
    public static final String STATUS_APPROVED = LifecycleRequestPolicy.STATUS_APPROVED;
    public static final String STATUS_COMPLETED = LifecycleRequestPolicy.STATUS_COMPLETED;
    public static final String STATUS_REJECTED = 'Rejected';

    public static final String COMMIT_12 = PlanChangePolicy.COMMIT_12;
    public static final String COMMIT_24 = PlanChangePolicy.COMMIT_24;
    public static final String NO_COMMIT = PlanChangePolicy.NO_COMMIT;
    public static final String FIBER = PlanChangePolicy.FIBER;
    public static final String QUOTE_MARKER = 'Renewal monthly amount: ';

    public static final Set<String> DECISIONS = new Set<String>{
        DECISION_SAME_TERMS,
        DECISION_NEW_PLAN,
        DECISION_LAPSE,
        DECISION_CANCEL
    };
    public static final Set<String> IN_FLIGHT_STATUSES = new Set<String>{
        STATUS_APPROVED,
        STATUS_AWAITING
    };

    public static Boolean renews(String decision) {
        return decision == DECISION_SAME_TERMS || decision == DECISION_NEW_PLAN;
    }
}
