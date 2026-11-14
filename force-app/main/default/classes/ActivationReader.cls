/**
 * Read side of activation: locks the Order, loads its lines and existing
 * service records, and builds the per-line context used by the provisioner.
 *
 * Queries stay in one place and keep USER_MODE so activation never bypasses
 * record sharing or field access. No DML is performed here.
 */
public with sharing class ActivationReader {
    public static Order lockOrder(Id orderId) {
        String query =
            'SELECT Id, OrderNumber, AccountId, Account.Name, ' +
            'Account.Segment__c, BillToContactId, ContractId, Pricebook2Id, ' +
            'Status, Activation_State__c, Failure_Reason__c, BSS_Order_Key__c ' +
            'FROM Order WHERE Id = :orderId WITH USER_MODE FOR UPDATE';
        List<Order> orders = Database.query(query);
        return orders.isEmpty() ? null : orders[0];
    }

    public static List<OrderItem> loadOrderItems(Id orderId) {
        return [
            SELECT
                Id,
                OrderId,
                Product2Id,
                Product2.Name,
                Product2.Family,
                Product2.Plan_Type__c,
                Product2.Recurring__c,
                Product2.ATS_Product_Code__c,
                PricebookEntryId,
                Quantity,
                UnitPrice,
                Description,
                Commitment_Option_Code__c,
                Subscription_Number__c
            FROM OrderItem
            WHERE OrderId = :orderId
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
    }

    public static Map<Id, Product2> productMap(List<OrderItem> items) {
        Map<Id, Product2> products = new Map<Id, Product2>();
        for (OrderItem item : items) {
            if (item.Product2Id == null || item.Product2 == null) {
                throw new ActivationException(
                    'Every order item must reference a product before activation.'
                );
            }
            products.put(item.Product2Id, item.Product2);
        }
        return products;
    }

    public static Map<Id, Subscription__c> loadSubscriptions(
        List<OrderItem> items
    ) {
        Set<Id> itemIds = new Set<Id>();
        for (OrderItem item : items) {
            itemIds.add(item.Id);
        }

        Map<Id, Subscription__c> byOrderItem = new Map<Id, Subscription__c>();
        for (Subscription__c subscription : [
            SELECT
                Id,
                Name,
                Status__c,
                Asset__c,
                Order_Product__c,
                Engagement__c,
                Root_Engagement__c,
                Parent_Subscription__c
            FROM Subscription__c
            WHERE Order_Product__c IN :itemIds
            WITH USER_MODE
        ]) {
            if (byOrderItem.containsKey(subscription.Order_Product__c)) {
                throw new ActivationException(
                    'More than one subscription already exists for an order item.'
                );
            }
            byOrderItem.put(subscription.Order_Product__c, subscription);
        }
        return byOrderItem;
    }

    public static Map<String, Engagement__c> loadEngagements(
        List<OrderItem> items
    ) {
        Set<String> keys = new Set<String>();
        for (OrderItem item : items) {
            String code = ActivationContext.normalizeCommitment(
                item.Commitment_Option_Code__c
            );
            if (code != 'NOCOMMIT') {
                keys.add(ActivationContext.engagementKey(item.Id));
            }
        }

        Map<String, Engagement__c> byKey = new Map<String, Engagement__c>();
        if (keys.isEmpty()) {
            return byKey;
        }

        for (Engagement__c engagement : [
            SELECT
                Id,
                Engagement_Key__c,
                Subscription__c,
                Root_Engagement__c
            FROM Engagement__c
            WHERE Engagement_Key__c IN :keys
            WITH USER_MODE
        ]) {
            byKey.put(engagement.Engagement_Key__c, engagement);
        }
        return byKey;
    }

    public static Map<Id, Asset> loadAssets(
        Map<Id, Subscription__c> subscriptions
    ) {
        Set<Id> assetIds = new Set<Id>();
        for (Subscription__c subscription : subscriptions.values()) {
            if (subscription.Asset__c != null) {
                assetIds.add(subscription.Asset__c);
            }
        }

        Map<Id, Asset> assets = new Map<Id, Asset>();
        if (assetIds.isEmpty()) {
            return assets;
        }

        for (Asset asset : [
            SELECT
                Id,
                Name,
                AccountId,
                Product2Id,
                Status,
                Provisioned_Status__c,
                Service_Line_Type__c,
                Is_Primary__c
            FROM Asset
            WHERE Id IN :assetIds
            WITH USER_MODE
        ]) {
            assets.put(asset.Id, asset);
        }
        return assets;
    }

    public static List<ActivationContext.ItemContext> buildContexts(
        List<OrderItem> items,
        Map<Id, Product2> products,
        Map<Id, Subscription__c> existingSubscriptions,
        Map<String, Engagement__c> existingEngagements,
        Map<Id, Asset> existingAssets
    ) {
        List<ActivationContext.ItemContext> contexts =
            new List<ActivationContext.ItemContext>();
        for (OrderItem item : items) {
            ActivationContext.ItemContext context = ActivationContext.build(
                item,
                products.get(item.Product2Id),
                existingSubscriptions.get(item.Id),
                existingEngagements.get(
                    ActivationContext.engagementKey(item.Id)
                ),
                null
            );
            if (context.subscription != null) {
                context.asset = existingAssets.get(
                    context.subscription.Asset__c
                );
            }
            contexts.add(context);
        }
        return contexts;
    }
}
