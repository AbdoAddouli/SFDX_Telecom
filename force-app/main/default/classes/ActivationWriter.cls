/**
 * Lifecycle and audit writes for activation. Keeping these together makes it
 * obvious which Order fields change, when the BSS key is set, and how failures
 * remain visible to operations.
 */
public with sharing class ActivationWriter {
    private static final String OPERATION = 'activateOrder';

    public static void markActivating(Order order, Contract contract) {
        order.ContractId = contract.Id;
        order.Activation_State__c = 'Activating';
        order.Failure_Reason__c = null;
        Database.update(order, AccessLevel.USER_MODE);
    }

    public static void markActivated(
        Order order,
        Contract contract,
        String correlationId
    ) {
        order.ContractId = contract.Id;
        order.Status = 'Activated';
        order.Activation_State__c = 'Activated';
        order.Failure_Reason__c = null;
        order.Activated_By__c = UserInfo.getUserId();
        order.Activated_On__c = System.now();
        if (String.isBlank(order.BSS_Order_Key__c)) {
            // The batch correlation is shared for traceability, but the BSS
            // order key is unique per order.
            order.BSS_Order_Key__c = (
                correlationId + ':' + order.OrderNumber
            ).left(64);
        }
        Database.update(order, AccessLevel.USER_MODE);
    }

    public static void markReady(Id orderId, String message) {
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

    public static void updateOrderItemNumbers(
        List<ActivationContext.ItemContext> contexts
    ) {
        List<OrderItem> updates = new List<OrderItem>();
        for (ActivationContext.ItemContext context : contexts) {
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

    public static void logSuccess(
        Order order,
        List<ActivationContext.ItemContext> contexts,
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
            for (ActivationContext.ItemContext context : contexts) {
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

    public static void logFailure(
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
}
