/**
 * Chooses the reconciliation status gateway. The live path stays unreachable
 * until BSS_Status_Live__c is enabled with real endpoint/auth in place.
 */
public with sharing class BssStatusReconciliationGatewayFactory {
    public static BssStatusReconciliationGateway create() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return create(flags != null && flags.BSS_Status_Live__c == true);
    }

    @TestVisible
    static BssStatusReconciliationGateway create(Boolean useLiveGateway) {
        return useLiveGateway == true
            ? (BssStatusReconciliationGateway)
                new RealBssStatusReconciliationGateway()
            : (BssStatusReconciliationGateway)
                new SimulatedBssStatusReconciliationGateway();
    }
}
