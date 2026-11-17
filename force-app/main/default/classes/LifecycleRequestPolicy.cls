/**
 * Shared lifecycle intake constants and approval threshold resolution.
 */
public with sharing class LifecycleRequestPolicy {
    public static final String TYPE_INFO = 'Info';
    public static final String TYPE_NEW_SUBSCRIPTION = 'NewSubscription';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_AWAITING = 'Awaiting_Approval';

    public static final Set<String> VALID_TYPES = new Set<String>{
        TYPE_NEW_SUBSCRIPTION,
        'PlanChange',
        'Cancellation',
        'EquipmentSwap',
        'Suspension',
        'Portability',
        TYPE_INFO
    };
    public static final Set<String> VALID_CHANNELS = new Set<String>{
        'Portal',
        'Advisor',
        'API',
        'Batch'
    };
    public static final Set<String> PENALTY_TYPES = new Set<String>{
        'Cancellation',
        'Portability'
    };
    public static final Set<String> VALID_PRIORITIES = new Set<String>{
        'Low', 'High', 'Critical'
    };

    public static Decimal approvalThreshold() {
        Decimal threshold = ATS_Feature_Flags__c.getOrgDefaults()
            .Cancellation_Approval_Threshold__c;
        return threshold == null || threshold < 0 ? 0 : threshold;
    }
}
