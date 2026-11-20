/** Device-swap payload sent to the BSS boundary. No Salesforce DML here. */
public with sharing class BssEquipmentSwapRequest {
    public String correlationId;
    public String idempotencyKey;
    public Id subscriptionId;
    public String subscriptionNumber;
    public Id oldAssetId;
    public String oldSerialNumber;
    public String newProductCode;
    public String newSerialNumber;
    public String newColour;
    public String newImageUrl;
}
