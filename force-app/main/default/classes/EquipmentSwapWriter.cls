/**
 * Bulk write path for UC-LIF-05. Subscription status, contract and engagement
 * are never written here; only the device lineage and request audit change.
 */
public with sharing class EquipmentSwapWriter {
    public static void prepare(List<EquipmentSwapContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (EquipmentSwapContext context : contexts) {
            if (context.request == null) {
                continue;
            }
            context.request.Requested_Product__c = context.device != null
                ? context.device.productId
                : context.request.Requested_Product__c;
            context.request.Old_Asset__c = context.oldAsset != null
                ? context.oldAsset.Id
                : null;
            context.request.New_Asset_Serial__c = context.serialNumber;
            context.request.New_Asset_Colour__c = context.colour;
            context.request.New_Asset_Image_URL__c = context.imageUrl;
            context.request.Calculated_Fee__c = EquipmentSwapPolicy.FEE;
            context.request.Fee_Breakdown__c = EquipmentSwapPolicy.FEE_BREAKDOWN;
            context.request.Resolution_Summary__c =
                'Equipment swap submitted; awaiting BSS confirmation.';
            requests.add(context.request);
        }
        if (!requests.isEmpty()) {
            Database.update(requests, true);
        }
    }

    public static void apply(List<EquipmentSwapContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }

        List<OrderItem> swapItems = new List<OrderItem>();
        for (EquipmentSwapContext context : contexts) {
            validateWriteInputs(context);
            swapItems.add(swapOrderItem(context));
        }
        Database.insert(swapItems, true);
        for (Integer i = 0; i < contexts.size(); i++) {
            contexts[i].swapOrderItem = swapItems[i];
        }

        List<Asset> newAssets = new List<Asset>();
        for (EquipmentSwapContext context : contexts) {
            newAssets.add(newAsset(context));
        }
        Database.insert(newAssets, true);
        for (Integer i = 0; i < contexts.size(); i++) {
            contexts[i].newAsset = newAssets[i];
        }

        List<Asset> retiredAssets = new List<Asset>();
        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        List<Case> cases = new List<Case>();
        for (EquipmentSwapContext context : contexts) {
            context.oldAsset.Status = EquipmentSwapPolicy.OLD_ASSET_STATUS;
            context.oldAsset.Provisioned_Status__c =
                EquipmentSwapPolicy.OLD_ASSET_PROVISIONED_STATUS;
            retiredAssets.add(context.oldAsset);

            context.subscription.Asset__c = context.newAsset.Id;
            subscriptions.add(context.subscription);

            context.request.Status__c = EquipmentSwapPolicy.STATUS_COMPLETED;
            context.request.Completed_On__c = System.now();
            context.request.Old_Asset__c = context.oldAsset.Id;
            context.request.New_Asset__c = context.newAsset.Id;
            context.request.BSS_Swap_Reference__c = context.response != null
                ? context.response.externalReference
                : null;
            context.request.Calculated_Fee__c = EquipmentSwapPolicy.FEE;
            context.request.Fee_Breakdown__c = EquipmentSwapPolicy.FEE_BREAKDOWN;
            context.request.Resolution_Summary__c =
                EquipmentSwapValidator.summary(context);
            requests.add(context.request);

            if (context.request.Case__c != null) {
                cases.add(
                    new Case(
                        Id = context.request.Case__c,
                        Status = 'Closed'
                    )
                );
            }
        }

        Database.update(retiredAssets, true);
        Database.update(subscriptions, true);
        Database.update(requests, true);
        if (!cases.isEmpty()) {
            Database.update(cases, true);
        }
    }

    private static void validateWriteInputs(EquipmentSwapContext context) {
        if (context.subscription == null || context.subscription.Id == null) {
            throw new EquipmentSwapException('Subscription is required for the swap write.');
        }
        if (context.oldAsset == null || context.oldAsset.Id == null) {
            throw new EquipmentSwapException('Old asset is required for the swap write.');
        }
        if (context.device == null || context.device.productId == null) {
            throw new EquipmentSwapException('New device is required for the swap write.');
        }
        if (context.sourceOrderItem == null || context.sourceOrderItem.OrderId == null) {
            throw new EquipmentSwapException(
                'Subscription has no source OrderItem to preserve lineage.'
            );
        }
        if (context.pricebookEntry == null || context.pricebookEntry.Id == null) {
            throw new EquipmentSwapException(
                'No active pricebook entry exists for the new device.'
            );
        }
    }

    private static OrderItem swapOrderItem(EquipmentSwapContext context) {
        return new OrderItem(
            OrderId = context.sourceOrderItem.OrderId,
            PricebookEntryId = context.pricebookEntry.Id,
            Product2Id = context.device.productId,
            Quantity = 1,
            UnitPrice = context.pricebookEntry.UnitPrice,
            ServiceDate = Date.today(),
            Description = 'Equipment swap for ' + context.subscription.Name,
            Creates_Asset__c = true,
            Subscription_Number__c = context.subscription.Name,
            Commitment_Option_Code__c =
                context.sourceOrderItem.Commitment_Option_Code__c
        );
    }

    private static Asset newAsset(EquipmentSwapContext context) {
        return new Asset(
            Name = context.device.name,
            AccountId = context.oldAsset.AccountId,
            ParentId = context.oldAsset.ParentId,
            Product2Id = context.device.productId,
            SerialNumber = context.serialNumber,
            Colour__c = context.colour,
            Image_URL__c = context.imageUrl,
            Order_Item__c = context.swapOrderItem.Id,
            Status = EquipmentSwapPolicy.NEW_ASSET_STATUS,
            Provisioned_Status__c = EquipmentSwapPolicy.NEW_ASSET_PROVISIONED_STATUS,
            Service_Line_Type__c = context.oldAsset.Service_Line_Type__c,
            Is_Primary__c = context.oldAsset.Is_Primary__c,
            InstallDate = Date.today(),
            PurchaseDate = Date.today(),
            Quantity = 1,
            Price = context.pricebookEntry.UnitPrice,
            Description = 'Equipment swap from ' + context.oldAsset.Name
        );
    }
}
