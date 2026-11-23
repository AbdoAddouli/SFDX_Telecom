/**
 * Publishes the post-commit activation event. The payload contains only
 * record IDs, a correlation ID and a timestamp - never MSISDNs or customer
 * names. PublishAfterCommit guarantees consumers never see phantom state.
 */
public with sharing class ServiceActivatedEventPublisher {
    private static final Integer MAX_IDS_LENGTH = 255;

    public static void publish(
        Order order,
        List<ActivationContext.ItemContext> contexts,
        String correlationId
    ) {
        if (order == null) {
            return;
        }

        List<String> subscriptionIds = new List<String>();
        if (contexts != null) {
            for (ActivationContext.ItemContext context : contexts) {
                if (context.subscription != null && context.subscription.Id != null) {
                    subscriptionIds.add(String.valueOf(context.subscription.Id));
                }
            }
        }

        String joinedIds = String.join(subscriptionIds, ',');
        if (joinedIds.length() > MAX_IDS_LENGTH) {
            joinedIds = joinedIds.left(MAX_IDS_LENGTH);
        }

        Service_Activated__e event = new Service_Activated__e(
            Correlation_Id__c = String.isBlank(correlationId)
                ? IntegrationCorrelation.next()
                : correlationId.left(36),
            Order_Id__c = String.valueOf(order.Id),
            Account_Id__c = String.valueOf(order.AccountId),
            Subscription_Ids__c = joinedIds,
            Subscription_Count__c = subscriptionIds.size(),
            Activated_At__c = System.now(),
            Source__c = 'ActivationService'
        );
        EventBus.publish(event);
    }
}
