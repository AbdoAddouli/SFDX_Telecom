/**
 * BSS boundary for activation. The gateway remains injectable so tests and E8
 * can swap the simulated implementation for the real callout without touching
 * the activation transaction.
 */
public with sharing class ActivationBssClient {
    private static final String BSS_ENDPOINT = 'simulated://bss/provision';

    @TestVisible
    private static BssProvisioningGateway gateway =
        new SimulatedBssProvisioningGateway();

    public class CallResult {
        public List<BssProvisioningResponse> responses;
        public Integer durationMs;
    }

    public static Boolean isEnabled() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return flags == null || flags.BSS_Provisioning_Enabled__c != false;
    }

    public static String endpoint() {
        External_Api__mdt config = External_Api__mdt.getInstance(
            'Bss_Provisioning'
        );
        if (config != null && String.isNotBlank(config.Base_Url__c)) {
            return config.Base_Url__c.left(255);
        }
        return BSS_ENDPOINT;
    }

    public static CallResult provision(
        Order order,
        List<ActivationContext.ItemContext> contexts,
        String correlationId
    ) {
        CallResult result = new CallResult();
        result.durationMs = 0;
        result.responses = new List<BssProvisioningResponse>();
        List<BssProvisioningRequest> requests =
            new List<BssProvisioningRequest>();

        for (ActivationContext.ItemContext context : contexts) {
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
            return result;
        }

        DateTime started = System.now();
        List<BssProvisioningResponse> responses = gateway.provision(requests);
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

    public static void apply(
        List<ActivationContext.ItemContext> contexts,
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
        for (ActivationContext.ItemContext context : contexts) {
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

        for (ActivationContext.ItemContext context : contexts) {
            if (context.subscription != null) {
                context.subscription.Status__c = 'Active';
            }
        }
    }

    @TestVisible
    public static void setGateway(BssProvisioningGateway replacement) {
        gateway = replacement;
    }

    private static Integer elapsedMs(DateTime start) {
        return (Integer) (System.now().getTime() - start.getTime());
    }
}
