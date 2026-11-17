/**
 * Plan-change constants shared by validators, repository and amender.
 */
public with sharing class PlanChangePolicy {
    public static final String REQUEST_TYPE = 'PlanChange';
    public static final String NO_COMMIT = 'NOCOMMIT';
    public static final String COMMIT_12 = 'COMMIT12';
    public static final String COMMIT_24 = 'COMMIT24';
    public static final String FIBER = 'Fiber';
    public static final String ACTIVE_ENGAGEMENT = 'Active';
    public static final String STATUS_AWAITING = 'Awaiting_Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String QUOTE_MARKER = 'New monthly amount: ';
}
