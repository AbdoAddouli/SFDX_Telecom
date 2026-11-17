/**
 * UC-LIF-02 intake orchestration: create shared requests, re-quote through the
 * catalogue, write the server price to the request, then amend approved lines.
 */
public with sharing class PlanChangeIntake {
    public static List<PlanChangeService.PlanChangeResult> execute(
        List<PlanChangeService.PlanChangeInput> inputs
    ) {
        List<PlanChangeService.PlanChangeResult> results =
            new List<PlanChangeService.PlanChangeResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Map<Integer, PlanChangeService.PlanChangeInput> validInputs =
            new Map<Integer, PlanChangeService.PlanChangeInput>();
        Map<Integer, Integer> originalIndexByIntakeIndex =
            new Map<Integer, Integer>();
        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new PlanChangeService.PlanChangeResult());
            String error = PlanChangeValidator.inputError(inputs[i]);
            if (error != null) {
                results[i].message = error;
                continue;
            }
            validInputs.put(intakeInputs.size(), inputs[i]);
            originalIndexByIntakeIndex.put(intakeInputs.size(), i);
            intakeInputs.add(PlanChangeValidator.toIntakeInput(inputs[i]));
        }
        if (intakeInputs.isEmpty()) {
            return results;
        }

        List<LifecycleRequestService.RequestOutput> outputs =
            LifecycleRequestService.createRequests(intakeInputs);
        Set<Id> requestIds = new Set<Id>();
        for (LifecycleRequestService.RequestOutput output : outputs) {
            if (output.success && output.requestId != null) {
                requestIds.add(output.requestId);
            }
        }
        if (requestIds.isEmpty()) {
            mapIntakeErrors(outputs, originalIndexByIntakeIndex, results);
            return results;
        }

        Date today = Date.today();
        Map<Id, Customer_Request__c> requests =
            PlanChangeRepository.requests(requestIds);
        Set<Id> subscriptionIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (PlanChangeService.PlanChangeInput input : validInputs.values()) {
            subscriptionIds.add(input.subscriptionId);
            accountIds.add(input.accountId);
            productIds.add(input.targetProductId);
        }

        Map<Id, Subscription__c> subscriptions =
            PlanChangeRepository.subscriptions(subscriptionIds);
        Set<Id> engagementIds = new Set<Id>();
        for (Subscription__c subscription : subscriptions.values()) {
            if (subscription.Account__c != null) {
                accountIds.add(subscription.Account__c);
            }
            if (subscription.Engagement__c != null) {
                engagementIds.add(subscription.Engagement__c);
            }
        }
        Map<Id, Engagement__c> engagements =
            PlanChangeRepository.engagements(engagementIds);
        Map<Id, Account> accounts = PlanChangeRepository.accounts(accountIds);
        Map<Id, Product2> products = PlanChangeRepository.products(productIds);

        List<PlanChangeContext> contexts = buildContexts(
            outputs,
            validInputs,
            originalIndexByIntakeIndex,
            results,
            requests,
            subscriptions,
            engagements,
            accounts,
            products,
            today
        );

        List<Customer_Request__c> requestUpdates =
            new List<Customer_Request__c>();
        for (PlanChangeContext context : contexts) {
            applyDecision(context, requestUpdates, results);
        }
        if (!requestUpdates.isEmpty()) {
            Database.update(requestUpdates, true);
        }

        List<PlanChangeAmender.Amendment> amendments = new List<PlanChangeAmender.Amendment>();
        for (PlanChangeContext context : contexts) {
            if (context.rejectionReason != null
                || context.request.Status__c == PlanChangePolicy.STATUS_AWAITING) {
                continue;
            }
            PlanChangeAmender.Amendment amendment = new PlanChangeAmender.Amendment();
            amendment.resultIndex = context.resultIndex;
            amendment.request = context.request;
            amendment.source = context.source;
            amendment.engagement = context.engagement;
            amendment.product = context.product;
            amendment.monthlyAmount = context.quotedAmount;
            amendment.result = results[context.resultIndex];
            amendment.summary =
                'Plan changed to ' + context.product.Name + '. New line ';
            amendments.add(amendment);
        }
        PlanChangeAmender.apply(amendments, today);
        closeCases(contexts, results);
        return results;
    }

    private static void mapIntakeErrors(
        List<LifecycleRequestService.RequestOutput> outputs,
        Map<Integer, Integer> originalIndexByIntakeIndex,
        List<PlanChangeService.PlanChangeResult> results
    ) {
        for (Integer j = 0; j < outputs.size(); j++) {
            Integer index = originalIndexByIntakeIndex.get(j);
            if (index != null) {
                results[index].message = outputs[j].message;
            }
        }
    }

    private static List<PlanChangeContext> buildContexts(
        List<LifecycleRequestService.RequestOutput> outputs,
        Map<Integer, PlanChangeService.PlanChangeInput> validInputs,
        Map<Integer, Integer> originalIndexByIntakeIndex,
        List<PlanChangeService.PlanChangeResult> results,
        Map<Id, Customer_Request__c> requests,
        Map<Id, Subscription__c> subscriptions,
        Map<Id, Engagement__c> engagements,
        Map<Id, Account> accounts,
        Map<Id, Product2> products,
        Date today
    ) {
        List<PlanChangeContext> contexts = new List<PlanChangeContext>();
        for (Integer j = 0; j < outputs.size(); j++) {
            Integer index = originalIndexByIntakeIndex.get(j);
            if (index == null) {
                continue;
            }
            PlanChangeService.PlanChangeInput input = validInputs.get(j);
            LifecycleRequestService.RequestOutput intake = outputs[j];
            results[index].requestId = intake.requestId;
            results[index].caseId = intake.caseId;
            if (!intake.success) {
                results[index].message = intake.message;
                continue;
            }

            PlanChangeContext context = new PlanChangeContext();
            context.resultIndex = index;
            context.input = input;
            context.request = requests.get(intake.requestId);
            context.source = subscriptions.get(input.subscriptionId);
            context.account = accounts.get(input.accountId);
            context.product = products.get(input.targetProductId);
            context.engagement = context.source == null
                ? null
                : engagements.get(context.source.Engagement__c);
            context.commitmentCode = PlanChangeValidator.resolveCommitment(
                input.commitmentCode, context.source, context.engagement
            );
            PlanChangeValidator.validateAndQuote(context, today);
            contexts.add(context);
        }
        return contexts;
    }

    private static void applyDecision(
        PlanChangeContext context,
        List<Customer_Request__c> requestUpdates,
        List<PlanChangeService.PlanChangeResult> results
    ) {
        PlanChangeService.PlanChangeResult result =
            results[context.resultIndex];
        Customer_Request__c request = context.request;
        request.Requested_Product__c = context.input.targetProductId;
        request.Calculated_Fee__c = 0;
        context.quotedAmount = context.price == null
            ? null
            : context.price.finalPrice;
        if (context.price != null) {
            request.Fee_Breakdown__c =
                PlanChangeValidator.buildBreakdown(context.price).left(1000);
        }

        if (context.rejectionReason != null) {
            request.Status__c = PlanChangePolicy.STATUS_REJECTED;
            request.Rejection_Reason__c =
                context.rejectionReason.left(256);
            request.Resolution_Summary__c =
                'Plan change rejected at eligibility.';
            request.Completed_On__c = Datetime.now();
            result.rejected(context.rejectionReason);
        } else if (request.Status__c == PlanChangePolicy.STATUS_AWAITING) {
            request.Resolution_Summary__c =
                'Plan change quoted and awaiting manager approval; ' +
                'no line superseded yet.';
            result.awaitingApproval(context.quotedAmount);
        } else {
            result.monthlyAmount = context.quotedAmount;
        }
        requestUpdates.add(request);
    }

    private static void closeCases(
        List<PlanChangeContext> contexts,
        List<PlanChangeService.PlanChangeResult> results
    ) {
        List<Case> casesToClose = new List<Case>();
        for (PlanChangeContext context : contexts) {
            PlanChangeService.PlanChangeResult result =
                results[context.resultIndex];
            result.subscriptionId = result.subscriptionId == null
                ? (context.source == null ? null : context.source.Id)
                : result.subscriptionId;
            if (result.status != 'Failed') {
                result.success = true;
            }
            if (context.request.Case__c != null) {
                casesToClose.add(
                    new Case(Id = context.request.Case__c, Status = 'Closed')
                );
            }
        }
        if (!casesToClose.isEmpty()) {
            Database.update(casesToClose, true);
        }
    }
}
