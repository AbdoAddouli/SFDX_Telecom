/**
 * @description Catalogue data access. Each method performs exactly one SOQL
 * query and enforces user mode, so object- and field-level access applies.
 * The service never queries inside a product or plan loop.
 */
public with sharing class CatalogQueryRepository {
    private static final String FAMILY_DEVICE = 'TELCO_DEVICE';

    public static List<Product2> findPlans(String planType) {
        return [
            SELECT Id, Name, Family, ATS_Product_Code__c, Plan_Type__c,
                Data_GB__c, Speed_Mbps__c, Unlimited_Calls__c, Unlimited_SMS__c,
                Recurring__c, Requires_Commitment__c, Device_Image_URL__c, Specs__c
            FROM Product2
            WHERE IsActive = true
                AND Is_Active__c = true
                AND Plan_Type__c = :planType
            WITH USER_MODE
            ORDER BY Data_GB__c ASC, Name ASC
        ];
    }

    public static List<Product2> findDevices() {
        return [
            SELECT Id, Name, Family, ATS_Product_Code__c, Plan_Type__c,
                Data_GB__c, Speed_Mbps__c, Unlimited_Calls__c, Unlimited_SMS__c,
                Recurring__c, Requires_Commitment__c, Device_Image_URL__c, Specs__c
            FROM Product2
            WHERE IsActive = true
                AND Is_Active__c = true
                AND Family = :FAMILY_DEVICE
            WITH USER_MODE
            ORDER BY Name ASC
        ];
    }

    public static Eligibility__c findEligibility(String postalCode) {
        List<Eligibility__c> rows = [
            SELECT Fiber_Available__c, Max_Downstream_Mbps__c,
                Earliest_Activation_Date__c
            FROM Eligibility__c
            WHERE Postal_Code__c = :postalCode
                AND Is_Active__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}
