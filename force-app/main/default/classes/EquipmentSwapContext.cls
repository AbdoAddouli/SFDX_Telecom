/** One equipment swap loaded for validation, BSS calls and bulk writes. */
public with sharing class EquipmentSwapContext {
    public Integer resultIndex;
    public EquipmentSwapService.EquipmentSwapResult result;
    public EquipmentSwapService.EquipmentSwapInput input;
    public Customer_Request__c request;
    public Subscription__c subscription;
    public Asset oldAsset;
    public Asset newAsset;
    public CatalogQueryService.ProductView device;
    public OrderItem sourceOrderItem;
    public OrderItem swapOrderItem;
    public PricebookEntry pricebookEntry;
    public String serialNumber;
    public String colour;
    public String imageUrl;
    public String bssReference;
    public String correlationId;
    public BssProvisioningResponse response;
    public Boolean attempted = false;

    public Boolean requestIdCreated() {
        return result != null && result.requestId != null;
    }
}
