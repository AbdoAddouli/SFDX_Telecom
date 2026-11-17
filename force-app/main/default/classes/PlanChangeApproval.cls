/**
 * Manager-approval orchestration for UC-LIF-02. Reuses the intake repository,
 * validator and amender so the approved path cannot drift from the quoted path.
 */
public with sharing class PlanChangeApproval {
    public static List<PlanChangeService.PlanChangeResult> execute(
        List<PlanChangeService.ApprovalInput> inputs
    ) {
        List<PlanChangeService.PlanChangeResult> results =
            new List<PlanChangeService.PlanChangeResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Set<Id> requestIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new PlanChangeService.PlanChangeResult());
            if (inputs[i] != null && inputs[i].requestId != null) {
                requestIds.add(inputs[i].requestId);
            } else {
                results[i].message = 'Request Id is required.';
            }
        }
        if (requestIds.isEmpty()) {
            return results;
        }

        Map<Id, Customer_Request__c> requests =
            PlanChangeRepository.requests(requestIds);
        Set<Id> subscriptionIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (Customer_Request__c request : requests.values()) {
            if (request.Subscription__c != null) {
                subscriptionIds.add(request.Subscription__c);
            }
            if (request.Requested_Product__c != null) {
                productIds.add(request.Requested_Product__c);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            PlanChangeRepository.subscriptions(subscriptionIds);
        Set<Id> engagementIds = new Set<Id>();
        for (Subscription__c source : subscriptions.values()) {
            if (source.Engagement__c != null) {
                engagementIds.add(source.Engagement__c);
            }
        }
        Map<Id, Engagement__c> engagements =
            PlanChangeRepository.engagements(engagementIds);
        Map<Id, Product2> products = PlanChangeRepository.products(productIds);

        List<PlanChangeAmender.Amendment> amendments =
            new List<PlanChangeAmender.Amendment>();
        Date today = Date.today();
        for (Integer i = 0; i < inputs.size(); i++) {
            PlanChangeService.ApprovalInput input = inputs[i];
            if (input == null || input.requestId == null) {
                continue;
            }
            Customer_Request__c request = requests.get(input.requestId);
            results[i].requestId = input.requestId;
            if (request == null) {
                results[i].message = 'Plan-change request could not be found.';
                continue;
            }
            if (request.Status__c == PlanChangePolicy.STATUS_COMPLETED) {
                results[i].alreadyApplied();
                continue;
            }

            Decimal quotedAmount = PlanChangeValidator.parseQuotedAmount(
                request.Fee_Breakdown__c
            );
            if (request.Status__c != PlanChangePolicy.STATUS_APPROVED
                || quotedAmount == null
                || request.Requested_Product__c == null) {
                results[i].message =
                    'Request must be approved with a quoted plan and price.';
                continue;
            }
            Subscription__c source = subscriptions.get(request.Subscription__c);
            Product2 product = products.get(request.Requested_Product__c);
            if (source == null || product == null) {
                results[i].message =
                    'Source line or target plan could not be found.';
                continue;
            }

            PlanChangeAmender.Amendment amendment =
                new PlanChangeAmender.Amendment();
            amendment.resultIndex = i;
            amendment.request = request;
            amendment.source = source;
            amendment.engagement = engagements.get(source.Engagement__c);
            amendment.product = product;
            amendment.monthlyAmount = quotedAmount;
            amendment.result = results[i];
            amendment.summary =
                'Approved plan change to ' + product.Name + '. New line ';
            amendments.add(amendment);
        }

        PlanChangeAmender.apply(amendments, today);
        return results;
    }
}
