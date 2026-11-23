/**
 * Subscriber stub for Service_Activated__e. It materialises a non-PII audit
 * row so delivery is observable and testable; real downstream consumers can
 * be added without changing the publisher or ActivationService.
 */
public without sharing class ServiceActivatedEventHandler {
    public static void handle(List<Service_Activated__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<Integration_Log__c> records = new List<Integration_Log__c>();
        for (Service_Activated__e event : events) {
            IntegrationLogService.LogInput input =
                new IntegrationLogService.LogInput();
            input.correlationId = event.Correlation_Id__c;
            input.systemName = 'BSS';
            input.operation = 'ServiceActivatedEvent';
            input.status = 'Success';
            input.statusCode = '200';
            input.orderId = toId(event.Order_Id__c);
            input.subscriptionId = firstSubscriptionId(event.Subscription_Ids__c);
            input.payloadSummary = 'Activation event subscriptions='
                + (event.Subscription_Count__c == null
                    ? 0
                    : event.Subscription_Count__c.intValue());
            records.add(IntegrationLogService.build(input));
        }
        Database.insert(records, false);
    }

    private static Id firstSubscriptionId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> ids = value.split(',');
        return ids.isEmpty() ? null : toId(ids[0]);
    }

    private static Id toId(String value) {
        return String.isBlank(value) ? null : (Id) value;
    }
}
