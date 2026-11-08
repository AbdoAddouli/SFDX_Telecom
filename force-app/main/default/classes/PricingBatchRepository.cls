/**
 * @description Batch data access for pricing. Every query is performed once for
 * the full product set; the service never queries inside a request loop.
 */
public with sharing class PricingBatchRepository {
    public Map<Id, Product2> productsById;
    public Map<Id, PricebookEntry> pricebookEntriesByProductId;
    public List<Pricing_Rule__mdt> pricingRules;
    public List<Config_Rule__mdt> configRules;

    public PricingBatchRepository() {
        this.productsById = new Map<Id, Product2>();
        this.pricebookEntriesByProductId = new Map<Id, PricebookEntry>();
        this.pricingRules = new List<Pricing_Rule__mdt>();
        this.configRules = new List<Config_Rule__mdt>();
    }

    public static PricingBatchRepository load(Set<Id> productIds) {
        PricingBatchRepository batch = new PricingBatchRepository();
        if (productIds == null || productIds.isEmpty()) {
            return batch;
        }

        batch.productsById = new Map<Id, Product2>([
            SELECT Id, Name, Family, IsActive, ATS_Product_Code__c
            FROM Product2
            WHERE Id IN :productIds
        ]);

        List<PricebookEntry> entries = [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
                AND IsActive = true
                AND Pricebook2.IsActive = true
            ORDER BY Product2Id ASC, Pricebook2.IsStandard ASC,
                Pricebook2.Name ASC, Pricebook2Id ASC
        ];
        for (PricebookEntry entry : entries) {
            if (!batch.pricebookEntriesByProductId.containsKey(entry.Product2Id)) {
                batch.pricebookEntriesByProductId.put(entry.Product2Id, entry);
            }
        }

        batch.pricingRules = loadPricingRules();
        batch.configRules = loadConfigRules();
        return batch;
    }

    public static Product2 loadProduct(Id productId) {
        List<Product2> products = [
            SELECT Id, Name, Family, IsActive, ATS_Product_Code__c
            FROM Product2
            WHERE Id = :productId
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    public static List<Pricing_Rule__mdt> loadPricingRules() {
        return [
            SELECT DeveloperName, MasterLabel, Rule_Type__c, Product__c,
                Requires_Product__c, Commitment_Code__c, Segment__c,
                Adjustment_Type__c, Adjustment_Value__c, Priority__c,
                Effective_From__c, Effective_To__c
            FROM Pricing_Rule__mdt
            WHERE Active__c = true
            ORDER BY Priority__c ASC, DeveloperName ASC
        ];
    }

    public static List<Config_Rule__mdt> loadConfigRules() {
        return [
            SELECT DeveloperName, MasterLabel, Rule_Kind__c, Product__c,
                Companion_Product__c, Applies_When_Commitment__c,
                Message__c, Severity__c
            FROM Config_Rule__mdt
            WHERE Active__c = true
            ORDER BY DeveloperName ASC
        ];
    }
}
