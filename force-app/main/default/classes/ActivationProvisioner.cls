/**
 * Write side of local activation records: Assets, Subscriptions, Engagements,
 * and the subscription links back to those records.
 *
 * This class performs the same bulk DML as before the split. It does not call
 * BSS or update the Order lifecycle; those stay in ActivationBssClient and
 * ActivationWriter so each transaction step is easy to audit.
 */
public with sharing class ActivationProvisioner {
    public static void create(
        List<ActivationContext.ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        createAssets(contexts, order);
        createSubscriptions(contexts, order, contract);
        createEngagements(contexts, order, contract);
        updateSubscriptionLinks(contexts, order, contract);
    }

    private static void createAssets(
        List<ActivationContext.ItemContext> contexts,
        Order order
    ) {
        ActivationContext.ItemContext primary = ActivationContext.primaryPlan(
            contexts
        );
        List<Asset> newAssets = new List<Asset>();
        List<ActivationContext.ItemContext> owners =
            new List<ActivationContext.ItemContext>();

        for (ActivationContext.ItemContext context : contexts) {
            if (context.asset != null) {
                continue;
            }
            Asset asset = new Asset(
                Name = context.product.Name,
                AccountId = order.AccountId,
                Product2Id = context.product.Id,
                Status = 'Installed',
                InstallDate = Date.today(),
                PurchaseDate = Date.today(),
                Quantity = context.item.Quantity,
                Price = context.item.UnitPrice,
                Description = context.item.Description,
                Service_Line_Type__c = context.serviceLineType,
                Provisioned_Status__c = 'Active',
                Is_Primary__c = context == primary
            );
            if (context.durationMonths != null) {
                asset.UsageEndDate = Date.today()
                    .addMonths(context.durationMonths);
            }
            newAssets.add(asset);
            owners.add(context);
        }

        if (newAssets.isEmpty()) {
            return;
        }

        Database.insert(newAssets, AccessLevel.USER_MODE);
        for (Integer index = 0; index < owners.size(); index++) {
            owners[index].asset = newAssets[index];
        }
    }

    private static void createSubscriptions(
        List<ActivationContext.ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Subscription__c> newSubscriptions =
            new List<Subscription__c>();
        List<ActivationContext.ItemContext> owners =
            new List<ActivationContext.ItemContext>();

        for (ActivationContext.ItemContext context : contexts) {
            if (context.subscription != null) {
                continue;
            }
            if (context.asset == null) {
                throw new ActivationException(
                    'An asset is required before a subscription can be created.'
                );
            }
            Subscription__c subscription = new Subscription__c(
                Account__c = order.AccountId,
                Asset__c = context.asset.Id,
                Product__c = context.item.Product2Id,
                Order_Product__c = context.item.Id,
                Contract__c = contract.Id,
                Service_Line_Type__c = context.serviceLineType,
                Status__c = 'PendingActivation',
                External_Status__c = 'PendingActivation',
                Billing_Start_Date__c = Date.today(),
                Monthly_Amount__c = context.item.UnitPrice,
                Contact__c = order.BillToContactId
            );
            if (context.durationMonths != null) {
                subscription.Billing_End_Date__c = Date.today()
                    .addMonths(context.durationMonths);
            }
            newSubscriptions.add(subscription);
            owners.add(context);
        }

        if (!newSubscriptions.isEmpty()) {
            Database.insert(newSubscriptions, AccessLevel.USER_MODE);
            for (Integer index = 0; index < owners.size(); index++) {
                owners[index].subscription = newSubscriptions[index];
            }
        }

        refreshSubscriptionNames(contexts);
    }

    private static void refreshSubscriptionNames(
        List<ActivationContext.ItemContext> contexts
    ) {
        Set<Id> subscriptionIds = new Set<Id>();
        for (ActivationContext.ItemContext context : contexts) {
            if (context.subscription != null) {
                subscriptionIds.add(context.subscription.Id);
            }
        }
        if (subscriptionIds.isEmpty()) {
            return;
        }

        Map<Id, Subscription__c> refreshed = new Map<Id, Subscription__c>([
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
            WHERE Id IN :subscriptionIds
            WITH USER_MODE
        ]);

        for (ActivationContext.ItemContext context : contexts) {
            if (context.subscription == null) {
                continue;
            }
            Subscription__c current = refreshed.get(
                context.subscription.Id
            );
            if (current == null) {
                throw new ActivationException(
                    'A subscription disappeared during activation.'
                );
            }
            context.subscription = current;
        }
    }

    private static void createEngagements(
        List<ActivationContext.ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Engagement__c> newEngagements = new List<Engagement__c>();
        List<ActivationContext.ItemContext> owners =
            new List<ActivationContext.ItemContext>();

        for (ActivationContext.ItemContext context : contexts) {
            if (context.durationMonths == null) {
                continue;
            }
            if (context.isDevice) {
                continue;
            }
            if (context.engagement == null) {
                newEngagements.add(
                    buildEngagement(context, order, contract)
                );
                owners.add(context);
            }
        }

        Map<Id, ActivationContext.ItemContext> deviceParents =
            new Map<Id, ActivationContext.ItemContext>();
        for (ActivationContext.ItemContext context : contexts) {
            if (!context.isDevice) {
                continue;
            }
            ActivationContext.ItemContext parent = ActivationContext.parentPlan(
                contexts,
                context
            );
            deviceParents.put(context.item.Id, parent);
            if (parent != null && parent.durationMonths != null) {
                continue;
            }
            if (context.durationMonths == null) {
                continue;
            }
            if (context.engagement == null) {
                newEngagements.add(
                    buildEngagement(context, order, contract)
                );
                owners.add(context);
            }
        }

        if (!newEngagements.isEmpty()) {
            Database.insert(newEngagements, AccessLevel.USER_MODE);
            for (Integer index = 0; index < owners.size(); index++) {
                owners[index].engagement = newEngagements[index];
                owners[index].rootEngagement = newEngagements[index];
            }
        }

        for (ActivationContext.ItemContext context : contexts) {
            if (context.isDevice) {
                ActivationContext.ItemContext parent = deviceParents.get(
                    context.item.Id
                );
                if (parent != null) {
                    context.parentSubscription = parent.subscription;
                    if (
                        parent.engagement != null &&
                        parent.durationMonths != null
                    ) {
                        context.engagement = parent.engagement;
                        context.rootEngagement = parent.engagement;
                    }
                }
            }
            if (
                context.engagement != null &&
                context.rootEngagement == null
            ) {
                context.rootEngagement = context.engagement;
            }
        }
    }

    private static Engagement__c buildEngagement(
        ActivationContext.ItemContext context,
        Order order,
        Contract contract
    ) {
        ActivationPenaltyPolicy.Snapshot penalty =
            ActivationPenaltyPolicy.resolve(
                order.Account.Segment__c,
                context.serviceLineType,
                context.durationMonths
            );
        if (penalty.rate == null) {
            throw new ActivationException(
                'No active penalty rule matches ' +
                context.serviceLineType +
                ' for a ' +
                context.durationMonths +
                '-month commitment.'
            );
        }

        return new Engagement__c(
            Account__c = order.AccountId,
            Subscription__c = context.subscription.Id,
            Asset__c = context.asset.Id,
            Contract__c = contract.Id,
            Engagement_Key__c = ActivationContext.engagementKey(
                context.item.Id
            ),
            Status__c = 'Active',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today()
                .addMonths(context.durationMonths),
            Duration_Months__c = context.durationMonths,
            Monthly_Amount__c = context.item.UnitPrice,
            Penalty_Rate__c = penalty.rate,
            Penalty_Rule__c = penalty.ruleName
        );
    }

    private static void updateSubscriptionLinks(
        List<ActivationContext.ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Subscription__c> updates = new List<Subscription__c>();
        for (ActivationContext.ItemContext context : contexts) {
            if (context.subscription == null) {
                continue;
            }
            Subscription__c subscription = new Subscription__c(
                Id = context.subscription.Id,
                Asset__c = context.asset.Id,
                Contract__c = contract.Id,
                Service_Line_Type__c = context.serviceLineType,
                Monthly_Amount__c = context.item.UnitPrice,
                Billing_Start_Date__c = Date.today(),
                Contact__c = order.BillToContactId
            );
            if (context.durationMonths != null) {
                subscription.Billing_End_Date__c = Date.today()
                    .addMonths(context.durationMonths);
            }
            if (context.engagement != null) {
                subscription.Engagement__c = context.engagement.Id;
                subscription.Root_Engagement__c =
                    context.rootEngagement != null
                    ? context.rootEngagement.Id
                    : context.engagement.Id;
            }
            if (context.parentSubscription != null) {
                subscription.Parent_Subscription__c =
                    context.parentSubscription.Id;
            }
            updates.add(subscription);
        }

        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }
}
