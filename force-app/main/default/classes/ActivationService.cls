/**
 * UC-COM-03: atomically turns a Ready Order into live service.
 *
 * Contract binding is intentionally isolated in ActivationContractWriter so
 * the unresolved Q1 decision (amend vs new contract) is a contained change.
 * BSS access is behind BssProvisioningGateway; E8 replaces the simulated
 * gateway with the real callout.
 */
public with sharing class ActivationService {
    private static final String OPERATION = 'activateOrder';
    private static final String BSS_ENDPOINT = 'simulated://bss/provision';
    private static final String INTERNAL_ENDPOINT = 'internal://activation';
    private static final Integer MAX_ORDERS_PER_CALL = 80;
    private static final Set<String> COMMITMENT_CODES = new Set<String>{
        'NOCOMMIT',
        'COMMIT12',
        'COMMIT24'
    };
    private static final Map<String, Integer> COMMITMENT_MONTHS =
        new Map<String, Integer>{
            'COMMIT12' => 12,
            'COMMIT24' => 24
        };
    private static final Set<String> SERVICE_LINE_TYPES = new Set<String>{
        'Mobile',
        'Fiber',
        'Landline',
        'Device'
    };

    @TestVisible
    private static BssProvisioningGateway bssGateway =
        new SimulatedBssProvisioningGateway();

    public class ActivationException extends Exception {
    }

    public class ActivationResult {
        @InvocableVariable public Id orderId;
        @InvocableVariable public String status;
        @InvocableVariable public String message;
        @InvocableVariable public String correlationId;
        @InvocableVariable public Integer assetCount;
        @InvocableVariable public Integer subscriptionCount;
        @InvocableVariable public Integer engagementCount;
        @InvocableVariable public Id contractId;
    }

    private class BssCallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    private class ItemContext {
        public OrderItem item;
        public Product2 product;
        public String commitmentCode;
        public Integer durationMonths;
        public String serviceLineType;
        public Boolean isRecurring;
        public Boolean isDevice;
        public Asset asset;
        public Subscription__c subscription;
        public Engagement__c engagement;
        public Engagement__c rootEngagement;
        public Subscription__c parentSubscription;
    }

    @InvocableMethod(
        label='Activate Orders'
        description='Atomically activates Ready orders into Assets, Subscriptions and Engagements.'
    )
    public static List<ActivationResult> activate(List<Id> orderIds) {
        List<ActivationResult> results = new List<ActivationResult>();

        if (orderIds == null || orderIds.isEmpty()) {
            return results;
        }

        if (orderIds.size() > MAX_ORDERS_PER_CALL) {
            ActivationResult result = new ActivationResult();
            result.status = 'Failed';
            result.message =
                'Activate at most ' +
                MAX_ORDERS_PER_CALL +
                ' orders per call so savepoint limits are never reached.';
            results.add(result);
            return results;
        }

        for (Id orderId : orderIds) {
            results.add(activateOrder(orderId));
        }

        return results;
    }

    public static ActivationResult activateOrder(Id orderId) {
        ActivationResult result = new ActivationResult();
        result.orderId = orderId;
        result.correlationId = correlationId();
        result.assetCount = 0;
        result.subscriptionCount = 0;
        result.engagementCount = 0;

        if (orderId == null) {
            result.status = 'Failed';
            result.message = 'An Order Id is required.';
            return result;
        }

        Savepoint checkpoint = Database.setSavepoint();
        DateTime started = System.now();
        String failureSystem = 'Other';
        String failureEndpoint = INTERNAL_ENDPOINT;

        try {
            Order order = lockOrder(orderId);
            if (order == null) {
                throw new ActivationException(
                    'The order could not be found or is not visible to you.'
                );
            }

            if (
                order.Activation_State__c == 'Activated' ||
                order.Status == 'Activated'
            ) {
                result.status = 'NoOp';
                result.message = 'The order is already activated.';
                return result;
            }
            if (order.Activation_State__c != 'Ready') {
                throw new ActivationException(
                    'The order is not in Ready state and cannot be activated.'
                );
            }
            if (order.AccountId == null) {
                throw new ActivationException(
                    'The order must have an account before activation.'
                );
            }
            if (!bssProvisioningEnabled()) {
                throw new ActivationException(
                    'BSS provisioning is disabled. The order remains Ready for operations.'
                );
            }

            List<OrderItem> items = loadOrderItems(orderId);
            if (items.isEmpty()) {
                throw new ActivationException(
                    'The order has no order items and cannot be activated.'
                );
            }

            Map<Id, Product2> products = productMap(items);
            Map<Id, Subscription__c> existingSubscriptions =
                loadSubscriptions(items);
            Map<String, Engagement__c> existingEngagements =
                loadEngagements(items, products);
            Map<Id, Asset> existingAssets = loadAssets(existingSubscriptions);

            List<ItemContext> contexts = buildContexts(
                items,
                products,
                existingSubscriptions,
                existingEngagements,
                existingAssets
            );

            Integer maxTerm = maxTerm(contexts);
            String contractType = contractType(contexts);
            Contract contract = ActivationContractWriter.ensure(
                order,
                maxTerm,
                contractType
            );

            order.ContractId = contract.Id;
            order.Activation_State__c = 'Activating';
            order.Failure_Reason__c = null;
            Database.update(order, AccessLevel.USER_MODE);

            createAssets(contexts, order);
            createSubscriptions(contexts, order, contract);
            createEngagements(contexts, order, contract);
            updateSubscriptionLinks(contexts, order, contract);

            failureSystem = 'BSS';
            failureEndpoint = bssEndpoint();
            BssCallResult bss = callBss(
                order,
                contexts,
                result.correlationId
            );
            Integer bssDurationMs = bss.durationMs;
            List<BssProvisioningResponse> responses = bss.responses;
            applyBss(contexts, responses);
            updateOrderItemNumbers(contexts);

            ActivationContractWriter.activate(contract);

            order.ContractId = contract.Id;
            order.Status = 'Activated';
            order.Activation_State__c = 'Activated';
            order.Failure_Reason__c = null;
            order.Activated_By__c = UserInfo.getUserId();
            order.Activated_On__c = System.now();
            if (String.isBlank(order.BSS_Order_Key__c)) {
                order.BSS_Order_Key__c = result.correlationId;
            }
            Database.update(order, AccessLevel.USER_MODE);

            result.status = 'Activated';
            result.message = 'Order activated successfully.';
            result.contractId = contract.Id;
            result.assetCount = countAssets(contexts);
            result.subscriptionCount = countSubscriptions(contexts);
            result.engagementCount = countEngagements(contexts);

            logSuccess(
                order,
                contexts,
                result.correlationId,
                bssDurationMs,
                failureEndpoint
            );

            return result;
        } catch (Exception error) {
            Database.rollback(checkpoint);
            String message = friendlyMessage(error);
            markReady(orderId, message);
            logFailure(
                orderId,
                result.correlationId,
                message,
                failureSystem,
                failureEndpoint
            );
            result.status = 'Failed';
            result.message = message;
            return result;
        }
    }

    private static Order lockOrder(Id orderId) {
        String query =
            'SELECT Id, OrderNumber, AccountId, Account.Name, ' +
            'Account.Segment__c, BillToContactId, ContractId, Pricebook2Id, ' +
            'Status, Activation_State__c, Failure_Reason__c, BSS_Order_Key__c ' +
            'FROM Order WHERE Id = :orderId WITH USER_MODE FOR UPDATE';
        List<Order> orders = Database.query(query);
        return orders.isEmpty() ? null : orders[0];
    }

    private static List<OrderItem> loadOrderItems(Id orderId) {
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

    private static Map<Id, Product2> productMap(List<OrderItem> items) {
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

    private static Map<Id, Subscription__c> loadSubscriptions(
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

    private static Map<String, Engagement__c> loadEngagements(
        List<OrderItem> items,
        Map<Id, Product2> products
    ) {
        Set<String> keys = new Set<String>();
        for (OrderItem item : items) {
            String code = normalizeCommitment(
                item.Commitment_Option_Code__c
            );
            if (code != 'NOCOMMIT') {
                keys.add(engagementKey(item.Id));
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

    private static Map<Id, Asset> loadAssets(
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

    private static List<ItemContext> buildContexts(
        List<OrderItem> items,
        Map<Id, Product2> products,
        Map<Id, Subscription__c> existingSubscriptions,
        Map<String, Engagement__c> existingEngagements,
        Map<Id, Asset> existingAssets
    ) {
        List<ItemContext> contexts = new List<ItemContext>();
        for (OrderItem item : items) {
            ItemContext context = new ItemContext();
            context.item = item;
            context.product = products.get(item.Product2Id);
            context.commitmentCode = normalizeCommitment(
                item.Commitment_Option_Code__c
            );
            context.durationMonths = commitmentMonths(
                context.commitmentCode
            );
            context.serviceLineType = serviceLineType(context.product);
            context.isRecurring = context.product.Recurring__c == true;
            context.isDevice = context.serviceLineType == 'Device';
            context.subscription = existingSubscriptions.get(item.Id);
            if (context.subscription != null) {
                context.asset = existingAssets.get(
                    context.subscription.Asset__c
                );
            }
            context.engagement = existingEngagements.get(
                engagementKey(item.Id)
            );
            contexts.add(context);
        }
        return contexts;
    }

    private static void createAssets(
        List<ItemContext> contexts,
        Order order
    ) {
        ItemContext primary = primaryPlan(contexts);
        List<Asset> newAssets = new List<Asset>();
        List<ItemContext> owners = new List<ItemContext>();

        for (ItemContext context : contexts) {
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
        List<ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Subscription__c> newSubscriptions =
            new List<Subscription__c>();
        List<ItemContext> owners = new List<ItemContext>();

        for (ItemContext context : contexts) {
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
        List<ItemContext> contexts
    ) {
        Set<Id> subscriptionIds = new Set<Id>();
        for (ItemContext context : contexts) {
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

        for (ItemContext context : contexts) {
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
        List<ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Engagement__c> newEngagements = new List<Engagement__c>();
        List<ItemContext> owners = new List<ItemContext>();

        for (ItemContext context : contexts) {
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

        Map<ItemContext, ItemContext> deviceParents =
            new Map<ItemContext, ItemContext>();
        for (ItemContext context : contexts) {
            if (!context.isDevice) {
                continue;
            }
            ItemContext parent = parentPlan(contexts, context);
            deviceParents.put(context, parent);
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

        for (ItemContext context : contexts) {
            if (context.isDevice) {
                ItemContext parent = deviceParents.get(context);
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
        ItemContext context,
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
            Engagement_Key__c = engagementKey(context.item.Id),
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
        List<ItemContext> contexts,
        Order order,
        Contract contract
    ) {
        List<Subscription__c> updates = new List<Subscription__c>();
        for (ItemContext context : contexts) {
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

    private static BssCallResult callBss(
        Order order,
        List<ItemContext> contexts,
        String correlationId
    ) {
        BssCallResult result = new BssCallResult();
        result.durationMs = 0;
        result.responses = new List<BssProvisioningResponse>();
        List<BssProvisioningRequest> requests =
            new List<BssProvisioningRequest>();

        for (ItemContext context : contexts) {
            if (
                context.subscription == null ||
                context.subscription.Status__c == 'Active'
            ) {
                continue;
            }
            if (String.isBlank(context.subscription.Name)) {
                throw new BssProvisioningException(
                    'A subscription number is required for BSS idempotency.'
                );
            }
            BssProvisioningRequest request = new BssProvisioningRequest();
            request.orderId = order.Id;
            request.orderItemId = context.item.Id;
            request.subscriptionId = context.subscription.Id;
            request.subscriptionNumber = context.subscription.Name;
            request.idempotencyKey = context.subscription.Name;
            request.correlationId = correlationId;
            request.productCode = context.product.ATS_Product_Code__c;
            request.serviceLineType = context.serviceLineType;
            request.accountName = order.Account.Name;
            requests.add(request);
        }

        if (requests.isEmpty()) {
            result.durationMs = 0;
            return result;
        }

        DateTime started = System.now();
        List<BssProvisioningResponse> responses =
            bssGateway.provision(requests);
        result.durationMs = elapsedMs(started);

        if (responses == null || responses.size() != requests.size()) {
            throw new BssProvisioningException(
                'The BSS returned an incomplete provisioning response.'
            );
        }

        Map<Id, BssProvisioningResponse> bySubscription =
            new Map<Id, BssProvisioningResponse>();
        for (BssProvisioningResponse response : responses) {
            if (response.subscriptionId == null) {
                throw new BssProvisioningException(
                    'The BSS response did not identify a subscription.'
                );
            }
            if (response.success != true) {
                throw new BssProvisioningException(
                    String.isBlank(response.message)
                        ? 'The BSS rejected the provisioning request.'
                        : response.message
                );
            }
            bySubscription.put(response.subscriptionId, response);
        }

        for (BssProvisioningRequest request : requests) {
            if (!bySubscription.containsKey(request.subscriptionId)) {
                throw new BssProvisioningException(
                    'The BSS response did not cover every subscription.'
                );
            }
        }

        result.responses = responses;
        return result;
    }

    private static void applyBss(
        List<ItemContext> contexts,
        List<BssProvisioningResponse> responses
    ) {
        if (responses == null || responses.isEmpty()) {
            return;
        }

        Map<Id, BssProvisioningResponse> bySubscription =
            new Map<Id, BssProvisioningResponse>();
        for (BssProvisioningResponse response : responses) {
            bySubscription.put(response.subscriptionId, response);
        }

        List<Subscription__c> updates = new List<Subscription__c>();
        for (ItemContext context : contexts) {
            if (
                context.subscription == null ||
                context.subscription.Status__c == 'Active'
            ) {
                continue;
            }
            BssProvisioningResponse response = bySubscription.get(
                context.subscription.Id
            );
            if (response == null) {
                throw new BssProvisioningException(
                    'No BSS response was returned for a subscription.'
                );
            }

            Subscription__c subscription = new Subscription__c(
                Id = context.subscription.Id,
                Status__c = 'Active',
                Activation_Date__c = Date.today(),
                External_Status__c = 'Active',
                Last_Sync_DateTime__c = System.now()
            );
            if (String.isNotBlank(response.externalReference)) {
                subscription.External_Reference__c =
                    response.externalReference.left(64);
            }
            if (String.isNotBlank(response.msisdn)) {
                subscription.MSISDN__c = response.msisdn.left(20);
            }
            if (String.isNotBlank(response.lineNumber)) {
                subscription.Line_Number__c = response.lineNumber.left(20);
            }
            updates.add(subscription);
        }

        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }

        for (ItemContext context : contexts) {
            if (context.subscription != null) {
                context.subscription.Status__c = 'Active';
            }
        }
    }

    private static void updateOrderItemNumbers(
        List<ItemContext> contexts
    ) {
        List<OrderItem> updates = new List<OrderItem>();
        for (ItemContext context : contexts) {
            if (
                context.subscription == null ||
                String.isBlank(context.subscription.Name)
            ) {
                throw new ActivationException(
                    'A subscription number could not be resolved for an order item.'
                );
            }
            updates.add(
                new OrderItem(
                    Id = context.item.Id,
                    Subscription_Number__c = context.subscription.Name.left(30)
                )
            );
        }

        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }

    private static void markReady(Id orderId, String message) {
        if (orderId == null) {
            return;
        }
        try {
            List<Order> orders = [
                SELECT Id, Status, Activation_State__c
                FROM Order
                WHERE Id = :orderId
                WITH USER_MODE
            ];
            if (orders.isEmpty()) {
                return;
            }
            Order order = orders[0];
            if (
                order.Activation_State__c == 'Activated' ||
                order.Status == 'Activated'
            ) {
                return;
            }
            if (order.Activation_State__c != 'Not_Eligible') {
                order.Activation_State__c = 'Ready';
            }
            order.Failure_Reason__c = message.left(255);
            Database.update(order, AccessLevel.USER_MODE);
        } catch (Exception ignored) {
            // The original activation error is more useful than a cleanup error.
        }
    }

    private static void logSuccess(
        Order order,
        List<ItemContext> contexts,
        String correlationId,
        Integer durationMs,
        String endpoint
    ) {
        try {
            Integration_Log__c log = new Integration_Log__c(
                Correlation_Id__c = correlationId,
                Direction__c = 'Outbound',
                System__c = 'BSS',
                Operation__c = OPERATION,
                Status__c = 'Success',
                Status_Code__c = '200',
                Duration_Ms__c = durationMs,
                Endpoint__c = endpoint.left(255),
                Order__c = order.Id,
                Payload_Summary__c = (
                    'Activated order ' +
                    order.OrderNumber +
                    ' with ' +
                    contexts.size() +
                    ' line(s).'
                ).left(255),
                Retry_Count__c = 0
            );
            for (ItemContext context : contexts) {
                if (context.subscription != null) {
                    log.Subscription__c = context.subscription.Id;
                    log.Idempotency_Key__c = context.subscription.Name;
                    break;
                }
            }
            Database.insert(log, AccessLevel.USER_MODE);
        } catch (Exception ignored) {
            // Activation must not fail because the audit row could not be written.
        }
    }

    private static void logFailure(
        Id orderId,
        String correlationId,
        String message,
        String systemName,
        String endpoint
    ) {
        try {
            Integration_Log__c log = new Integration_Log__c(
                Correlation_Id__c = correlationId,
                Direction__c = 'Outbound',
                System__c = systemName,
                Operation__c = OPERATION,
                Status__c = 'Failure',
                Endpoint__c = endpoint.left(255),
                Error_Message__c = message.left(255),
                Payload_Summary__c = ('Activation failed: ' + message)
                    .left(255),
                Retry_Count__c = 0
            );
            if (orderId != null) {
                log.Order__c = orderId;
            }
            Database.insert(log, AccessLevel.USER_MODE);
        } catch (Exception ignored) {
            // Do not mask the activation failure with an audit failure.
        }
    }

    private static Boolean bssProvisioningEnabled() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return flags == null || flags.BSS_Provisioning_Enabled__c != false;
    }

    private static String normalizeCommitment(String rawCode) {
        String code = String.isBlank(rawCode)
            ? 'NOCOMMIT'
            : rawCode.trim().toUpperCase();
        if (!COMMITMENT_CODES.contains(code)) {
            throw new ActivationException(
                'Unsupported commitment option code: ' + rawCode
            );
        }
        return code;
    }

    private static Integer commitmentMonths(String code) {
        return COMMITMENT_MONTHS.get(code);
    }

    private static String serviceLineType(Product2 product) {
        if (product == null) {
            throw new ActivationException(
                'A product is required to determine the service line type.'
            );
        }
        String candidate = product.Plan_Type__c;
        if (String.isBlank(candidate) && product.Family != null) {
            if (product.Family.containsIgnoreCase('DEVICE')) {
                candidate = 'Device';
            } else if (product.Family.containsIgnoreCase('FIBER')) {
                candidate = 'Fiber';
            } else if (product.Family.containsIgnoreCase('MOBILE')) {
                candidate = 'Mobile';
            }
        }
        if (String.isBlank(candidate) || !SERVICE_LINE_TYPES.contains(candidate)) {
            throw new ActivationException(
                'The product does not map to a valid service line type.'
            );
        }
        return candidate;
    }

    private static String engagementKey(Id orderItemId) {
        return 'ENG-' + String.valueOf(orderItemId);
    }

    private static Integer maxTerm(List<ItemContext> contexts) {
        Integer maximum = 0;
        for (ItemContext context : contexts) {
            if (
                context.durationMonths != null &&
                context.durationMonths > maximum
            ) {
                maximum = context.durationMonths;
            }
        }
        return maximum;
    }

    private static String contractType(List<ItemContext> contexts) {
        Boolean mobile = false;
        Boolean fiber = false;
        for (ItemContext context : contexts) {
            if (context.serviceLineType == 'Mobile') {
                mobile = true;
            } else if (
                context.serviceLineType == 'Fiber' ||
                context.serviceLineType == 'Landline'
            ) {
                fiber = true;
            }
        }
        if (mobile && fiber) {
            return 'Bundle';
        }
        if (fiber) {
            return 'Fiber';
        }
        if (mobile) {
            return 'Mobile';
        }
        return null;
    }

    private static ItemContext primaryPlan(List<ItemContext> contexts) {
        for (ItemContext context : contexts) {
            if (context.isRecurring) {
                return context;
            }
        }
        return null;
    }

    private static ItemContext parentPlan(
        List<ItemContext> contexts,
        ItemContext device
    ) {
        Integer deviceIndex = contexts.indexOf(device);
        for (Integer index = deviceIndex - 1; index >= 0; index--) {
            if (contexts[index].isRecurring) {
                return contexts[index];
            }
        }
        for (ItemContext context : contexts) {
            if (context.isRecurring) {
                return context;
            }
        }
        return null;
    }

    private static Integer countAssets(List<ItemContext> contexts) {
        Integer count = 0;
        for (ItemContext context : contexts) {
            if (context.asset != null) {
                count++;
            }
        }
        return count;
    }

    private static Integer countSubscriptions(List<ItemContext> contexts) {
        Integer count = 0;
        for (ItemContext context : contexts) {
            if (context.subscription != null) {
                count++;
            }
        }
        return count;
    }

    private static Integer countEngagements(List<ItemContext> contexts) {
        Set<Id> engagementIds = new Set<Id>();
        for (ItemContext context : contexts) {
            if (context.engagement != null) {
                engagementIds.add(context.engagement.Id);
            }
        }
        return engagementIds.size();
    }

    private static Integer elapsedMs(DateTime start) {
        return (Integer) (System.now().getTime() - start.getTime());
    }

    private static String correlationId() {
        return String.valueOf(UUID.randomUUID());
    }

    private static String bssEndpoint() {
        External_Api__mdt config = External_Api__mdt.getInstance(
            'Bss_Provisioning'
        );
        if (config != null && String.isNotBlank(config.Base_Url__c)) {
            return config.Base_Url__c.left(255);
        }
        return BSS_ENDPOINT;
    }

    private static String friendlyMessage(Exception error) {
        if (error instanceof DmlException) {
            DmlException dml = (DmlException) error;
            if (dml.getNumDml() > 0) {
                return dml.getDmlMessage(0);
            }
        }
        return String.isBlank(error.getMessage())
            ? 'Activation failed.'
            : error.getMessage();
    }

    @TestVisible
    private static void setBssGateway(BssProvisioningGateway gateway) {
        bssGateway = gateway;
    }
}
