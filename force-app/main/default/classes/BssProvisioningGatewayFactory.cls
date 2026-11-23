/**
 * Chooses the activation BSS gateway.
 *
 * The live path is a flag-off scaffold: the default remains the existing
 * simulated gateway so current activations are unchanged. Flip
 * BSS_Provisioning_Live__c only after the real BSS_Api endpoint/auth and
 * External_Api__mdt.Bss_Provisioning configuration are supplied.
 */
public with sharing class BssProvisioningGatewayFactory {
    public static BssProvisioningGateway create() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return create(flags != null && flags.BSS_Provisioning_Live__c == true);
    }

    /** Pure selection seam for tests and future cutover tooling. */
    @TestVisible
    static BssProvisioningGateway create(Boolean useLiveGateway) {
        return useLiveGateway == true
            ? (BssProvisioningGateway) new RealBssProvisioningGateway()
            : (BssProvisioningGateway) new SimulatedBssProvisioningGateway();
    }
}
