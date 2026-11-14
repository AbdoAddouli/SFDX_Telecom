/**
 * UC-COM-03/UC-COM-06: atomic, idempotent, bulk-safe order activation.
 *
 * The service owns only the transaction: validate, load, write local records,
 * call BSS, commit the Order, and roll back to Ready on any failure. The
 * detailed work is split into small collaborators:
 *
 *   ActivationReader      - SOQL and per-line context
 *   ActivationContext     - pure commitment/product rules and context
 *   ActivationProvisioner - Asset/Subscription/Engagement DML
 *   ActivationBssClient   - BSS request, response validation, BSS DML
 *   ActivationWriter      - Order lifecycle, item numbers, audit logs
 *   ActivationContractWriter (existing) - contract binding
 *   ActivationException   - user-safe failure message
 *
 * A synchronous call is capped at 10 orders. Larger batches are split by
 * ActivationBatchJob into independent queueable chunks of this size.
 */
public with sharing class ActivationService {
    private static final String INTERNAL_ENDPOINT = 'internal://activation';
    public static final Integer MAX_ORDERS_PER_CALL = 10;

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

    @InvocableMethod(
        label='Activate Orders'
        description='Atomically activates Ready orders into Assets, Subscriptions and Engagements.'
    )
    public static List<ActivationResult> activate(List<Id> orderIds) {
        return activate(orderIds, null);
    }

    @TestVisible
    public static List<ActivationResult> activate(
        List<Id> orderIds,
        String sharedCorrelationId
    ) {
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
                ' orders per call so transaction limits are never reached.';
            results.add(result);
            return results;
        }

        String callCorrelationId = String.isBlank(sharedCorrelationId)
            ? correlationId()
            : sharedCorrelationId;
        for (Id orderId : orderIds) {
            results.add(activateOrder(orderId, callCorrelationId));
        }

        return results;
    }

    public static ActivationResult activateOrder(Id orderId) {
        return activateOrder(orderId, correlationId());
    }

    private static ActivationResult activateOrder(
        Id orderId,
        String sharedCorrelationId
    ) {
        ActivationResult result = new ActivationResult();
        result.orderId = orderId;
        result.correlationId = sharedCorrelationId;
        result.assetCount = 0;
        result.subscriptionCount = 0;
        result.engagementCount = 0;

        if (orderId == null) {
            result.status = 'Failed';
            result.message = 'An Order Id is required.';
            return result;
        }

        Savepoint checkpoint = Database.setSavepoint();
        String failureSystem = 'Other';
        String failureEndpoint = INTERNAL_ENDPOINT;

        try {
            Order order = ActivationReader.lockOrder(orderId);
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
            if (!ActivationBssClient.isEnabled()) {
                throw new ActivationException(
                    'BSS provisioning is disabled. The order remains Ready for operations.'
                );
            }

            List<OrderItem> items = ActivationReader.loadOrderItems(orderId);
            if (items.isEmpty()) {
                throw new ActivationException(
                    'The order has no order items and cannot be activated.'
                );
            }

            Map<Id, Product2> products = ActivationReader.productMap(items);
            Map<Id, Subscription__c> existingSubscriptions =
                ActivationReader.loadSubscriptions(items);
            Map<String, Engagement__c> existingEngagements =
                ActivationReader.loadEngagements(items);
            Map<Id, Asset> existingAssets = ActivationReader.loadAssets(
                existingSubscriptions
            );

            List<ActivationContext.ItemContext> contexts =
                ActivationReader.buildContexts(
                    items,
                    products,
                    existingSubscriptions,
                    existingEngagements,
                    existingAssets
                );

            Contract contract = ActivationContractWriter.ensure(
                order,
                ActivationContext.maxTerm(contexts),
                ActivationContext.contractType(contexts)
            );

            ActivationWriter.markActivating(order, contract);
            ActivationProvisioner.create(contexts, order, contract);

            failureSystem = 'BSS';
            failureEndpoint = ActivationBssClient.endpoint();
            ActivationBssClient.CallResult bss =
                ActivationBssClient.provision(
                    order,
                    contexts,
                    result.correlationId
                );
            ActivationBssClient.apply(contexts, bss.responses);
            ActivationWriter.updateOrderItemNumbers(contexts);

            ActivationContractWriter.activate(contract);
            ActivationWriter.markActivated(
                order,
                contract,
                result.correlationId
            );

            result.status = 'Activated';
            result.message = 'Order activated successfully.';
            result.contractId = contract.Id;
            result.assetCount = ActivationContext.countAssets(contexts);
            result.subscriptionCount = ActivationContext.countSubscriptions(
                contexts
            );
            result.engagementCount = ActivationContext.countEngagements(
                contexts
            );

            ActivationWriter.logSuccess(
                order,
                contexts,
                result.correlationId,
                bss.durationMs,
                failureEndpoint
            );
            return result;
        } catch (Exception error) {
            Database.rollback(checkpoint);
            String message = friendlyMessage(error);
            ActivationWriter.markReady(orderId, message);
            ActivationWriter.logFailure(
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

    private static String correlationId() {
        return String.valueOf(UUID.randomUUID());
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
        ActivationBssClient.setGateway(gateway);
    }
}
