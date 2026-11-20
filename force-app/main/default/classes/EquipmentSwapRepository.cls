/** Bulk-only query boundary for UC-LIF-05. Fixed SOQL count per batch. */
public with sharing class EquipmentSwapRepository {
    public static Map<Id, Subscription__c> subscriptions(
        Set<Id> subscriptionIds
    ) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return new Map<Id, Subscription__c>();
        }
        return new Map<Id, Subscription__c>(
            [
                SELECT
                    Id,
                    Name,
                    Account__c,
                    Contact__c,
                    Status__c,
                    Asset__c,
                    Engagement__c,
                    Order_Product__c,
                    Product__c,
                    Product__r.Family,
                    Product__r.Requires_Commitment__c
                FROM Subscription__c
                WHERE Id IN :subscriptionIds
            ]
        );
    }

    public static Map<Id, Asset> assets(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new Map<Id, Asset>();
        }
        return new Map<Id, Asset>(
            [
                SELECT
                    Id,
                    Name,
                    AccountId,
                    ParentId,
                    Product2Id,
                    SerialNumber,
                    Status,
                    Provisioned_Status__c,
                    Service_Line_Type__c,
                    Is_Primary__c
                FROM Asset
                WHERE Id IN :assetIds
            ]
        );
    }

    public static Map<Id, Customer_Request__c> inFlightBySubscription(
        Set<Id> subscriptionIds
    ) {
        if (subscriptionIds == null || subscriptionIds.isEmpty()) {
            return new Map<Id, Customer_Request__c>();
        }
        Map<Id, Customer_Request__c> bySubscription =
            new Map<Id, Customer_Request__c>();
        for (
            Customer_Request__c request : [
                SELECT Id, Subscription__c, Status__c
                FROM Customer_Request__c
                WHERE
                    Subscription__c IN :subscriptionIds
                    AND Request_Type__c = :EquipmentSwapPolicy.REQUEST_TYPE
                    AND Status__c IN :EquipmentSwapPolicy.IN_FLIGHT_STATUSES
            ]
        ) {
            bySubscription.put(request.Subscription__c, request);
        }
        return bySubscription;
    }

    public static Map<Id, Customer_Request__c> requests(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Customer_Request__c>();
        }
        return new Map<Id, Customer_Request__c>(
            [
                SELECT
                    Id,
                    Account__c,
                    Case__c,
                    Status__c,
                    Subscription__c,
                    Request_Type__c,
                    Requested_Product__c,
                    Old_Asset__c,
                    New_Asset__c,
                    New_Asset_Serial__c,
                    New_Asset_Colour__c,
                    New_Asset_Image_URL__c,
                    BSS_Swap_Reference__c,
                    Calculated_Fee__c,
                    Fee_Breakdown__c,
                    Resolution_Summary__c,
                    Customer_Comment__c
                FROM Customer_Request__c
                WHERE Id IN :requestIds
            ]
        );
    }

    public static Map<Id, OrderItem> sourceOrderItems(Set<Id> orderItemIds) {
        if (orderItemIds == null || orderItemIds.isEmpty()) {
            return new Map<Id, OrderItem>();
        }
        return new Map<Id, OrderItem>(
            [
                SELECT
                    Id,
                    OrderId,
                    Product2Id,
                    UnitPrice,
                    Commitment_Option_Code__c
                FROM OrderItem
                WHERE Id IN :orderItemIds
            ]
        );
    }

    public static Map<Id, PricebookEntry> pricebookEntries(
        Set<Id> productIds
    ) {
        if (productIds == null || productIds.isEmpty()) {
            return new Map<Id, PricebookEntry>();
        }
        Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>();
        for (
            PricebookEntry entry : [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE
                    Product2Id IN :productIds
                    AND IsActive = true
                    AND Pricebook2.IsActive = true
                ORDER BY UnitPrice ASC
            ]
        ) {
            if (!entries.containsKey(entry.Product2Id)) {
                entries.put(entry.Product2Id, entry);
            }
        }
        return entries;
    }

    public static Map<Id, CatalogQueryService.ProductView> devices() {
        Map<Id, CatalogQueryService.ProductView> devices =
            new Map<Id, CatalogQueryService.ProductView>();
        for (CatalogQueryService.ProductView device : CatalogQueryService.getDevices()) {
            if (device != null && device.productId != null) {
                devices.put(device.productId, device);
            }
        }
        return devices;
    }

    public static void populateFromRequest(
        EquipmentSwapContext context,
        Map<Id, Subscription__c> subscriptions,
        Map<Id, Asset> assets,
        Map<Id, CatalogQueryService.ProductView> devices,
        Map<Id, OrderItem> orderItems,
        Map<Id, PricebookEntry> entries
    ) {
        if (context == null || context.request == null) {
            return;
        }
        context.subscription = subscriptions.get(context.request.Subscription__c);
        context.oldAsset = assets.get(context.request.Old_Asset__c);
        context.device = devices.get(context.request.Requested_Product__c);
        context.serialNumber = context.request.New_Asset_Serial__c;
        context.colour = context.request.New_Asset_Colour__c;
        context.imageUrl = String.isBlank(context.request.New_Asset_Image_URL__c)
            ? (context.device != null ? context.device.deviceImageUrl : null)
            : context.request.New_Asset_Image_URL__c;
        context.correlationId = EquipmentSwapPolicy.correlationId(
            context.request.Id
        );
        context.sourceOrderItem = context.subscription == null
            ? null
            : orderItems.get(context.subscription.Order_Product__c);
        context.pricebookEntry = context.device == null
            ? null
            : entries.get(context.device.productId);
    }
}
