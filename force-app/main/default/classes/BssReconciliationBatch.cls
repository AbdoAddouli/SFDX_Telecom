/**
 * UC-INT-04: nightly Salesforce-to-BSS status reconciliation.
 *
 * The batch only writes External_Status__c, Last_Sync_DateTime__c and
 * Integration_Log__c findings. It never changes the Salesforce lifecycle
 * status, so drift is surfaced to ops instead of silently mutating history.
 */
public with sharing class BssReconciliationBatch
    implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static BssStatusReconciliationGateway gateway =
        BssStatusReconciliationGatewayFactory.create();

    @TestVisible
    private Integer checkedCount = 0;

    @TestVisible
    private Integer driftCount = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT
                Id,
                Name,
                Status__c,
                External_Status__c,
                External_Reference__c
            FROM Subscription__c
            WHERE External_Reference__c != NULL
            ORDER BY Name
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<Subscription__c> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        String correlationId = IntegrationCorrelation.next();
        List<BssStatusRequest> requests = new List<BssStatusRequest>();
        for (Subscription__c subscription : scope) {
            BssStatusRequest request = new BssStatusRequest();
            request.subscriptionId = subscription.Id;
            request.subscriptionNumber = subscription.Name;
            request.externalReference = subscription.External_Reference__c;
            request.localStatus = subscription.Status__c;
            request.correlationId = correlationId;
            requests.add(request);
        }

        List<BssStatusResponse> responses = gateway.status(requests);
        if (responses == null || responses.size() != requests.size()) {
            throw new BssReconciliationException(
                'The BSS returned an incomplete status reconciliation result.'
            );
        }

        Map<Id, BssStatusResponse> bySubscription =
            new Map<Id, BssStatusResponse>();
        for (BssStatusResponse response : responses) {
            if (response != null && response.subscriptionId != null) {
                bySubscription.put(response.subscriptionId, response);
            }
        }

        List<Subscription__c> updates = new List<Subscription__c>();
        List<IntegrationLogService.LogInput> findings =
            new List<IntegrationLogService.LogInput>();

        for (BssStatusRequest request : requests) {
            BssStatusResponse response =
                bySubscription.get(request.subscriptionId);
            if (response == null || response.success != true) {
                findings.add(finding(request, response, correlationId,
                    'BSS status lookup failed for this subscription.'));
                continue;
            }

            String externalStatus = response.externalStatus == null
                ? ''
                : response.externalStatus.trim().left(40);
            if (String.isBlank(externalStatus)) {
                findings.add(finding(request, response, correlationId,
                    'BSS returned an empty status.'));
                continue;
            }

            checkedCount++;
            updates.add(new Subscription__c(
                Id = request.subscriptionId,
                External_Status__c = externalStatus,
                Last_Sync_DateTime__c = System.now()
            ));

            if (!externalStatus.equalsIgnoreCase(request.localStatus)) {
                driftCount++;
                findings.add(finding(request, response, correlationId,
                    'Drift: Salesforce=' + request.localStatus
                        + '; BSS=' + externalStatus));
            }
        }

        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
        for (IntegrationLogService.LogInput finding : findings) {
            IntegrationLogService.publish(finding);
        }
    }

    public void finish(Database.BatchableContext context) {
        IntegrationLogService.LogInput summary =
            new IntegrationLogService.LogInput();
        summary.correlationId = IntegrationCorrelation.next();
        summary.systemName = 'BSS';
        summary.operation = 'BssReconciliationSummary';
        summary.status = driftCount == 0 ? 'Success' : 'Failure';
        summary.payloadSummary = 'checked=' + checkedCount
            + '; drift=' + driftCount;
        IntegrationLogService.publish(summary);
    }

    @TestVisible
    static void setGateway(BssStatusReconciliationGateway replacement) {
        gateway = replacement;
    }

    private static IntegrationLogService.LogInput finding(
        BssStatusRequest request,
        BssStatusResponse response,
        String correlationId,
        String message
    ) {
        IntegrationLogService.LogInput input =
            new IntegrationLogService.LogInput();
        input.correlationId = correlationId;
        input.systemName = 'BSS';
        input.operation = 'BssReconciliation';
        input.status = 'Failure';
        input.statusCode = response == null ? null : response.statusCode;
        input.subscriptionId = request.subscriptionId;
        input.errorMessage = message;
        input.durationMs = response == null || response.durationMs == null
            ? 0
            : response.durationMs;
        return input;
    }
}
