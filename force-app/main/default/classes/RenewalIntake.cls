/**
 * UC-LIF-06 intake orchestration: validate a batch, create shared requests,
 * re-quote through the catalogue, then apply approved renewal decisions.
 */
public with sharing class RenewalIntake {
    public static List<RenewalService.RenewalResult> execute(
        List<RenewalService.RenewalInput> inputs
    ) {
        List<RenewalService.RenewalResult> results =
            new List<RenewalService.RenewalResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new RenewalService.RenewalResult());
        }

        Set<Id> subscriptionIds = new Set<Id>();
        for (RenewalService.RenewalInput input : inputs) {
            if (input != null && input.subscriptionId != null) {
                subscriptionIds.add(input.subscriptionId);
            }
        }
        Map<Id, Subscription__c> subscriptions =
            RenewalRepository.subscriptions(subscriptionIds);
        Map<Id, Customer_Request__c> inFlight =
            RenewalRepository.inFlightBySubscription(subscriptionIds);

        Map<Integer, RenewalService.RenewalInput> validInputs =
            new Map<Integer, RenewalService.RenewalInput>();
        Map<Integer, Integer> originalIndexByIntakeIndex =
            new Map<Integer, Integer>();
        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        Set<Id> seenSubscriptionIds = new Set<Id>();

        for (Integer i = 0; i < inputs.size(); i++) {
            RenewalService.RenewalInput input = inputs[i];
            results[i].decision = input == null ? null : input.decision;
            String error = RenewalValidator.inputError(input);
            if (
                error == null &&
                input.subscriptionId != null &&
                subscriptions.containsKey(input.subscriptionId) == false
            ) {
                error = 'Subscription could not be found.';
            }
            if (
                error == null &&
                (inFlight.containsKey(input.subscriptionId) ||
                seenSubscriptionIds.contains(input.subscriptionId))
            ) {
                error = 'A renewal request is already in flight for this line.';
            }
            if (error != null) {
                results[i].rejected(error);
                continue;
            }
            seenSubscriptionIds.add(input.subscriptionId);
            validInputs.put(intakeInputs.size(), input);
            originalIndexByIntakeIndex.put(intakeInputs.size(), i);
            intakeInputs.add(RenewalValidator.toIntakeInput(input));
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
            RenewalRepository.requests(requestIds);
        Set<Id> engagementIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        Set<Id> contractIds = new Set<Id>();
        for (RenewalService.RenewalInput input : validInputs.values()) {
            accountIds.add(input.accountId);
            if (input.targetProductId != null) {
                productIds.add(input.targetProductId);
            }
        }
        for (Subscription__c subscription : subscriptions.values()) {
            if (subscription.Account__c != null) {
                accountIds.add(subscription.Account__c);
            }
            if (subscription.Engagement__c != null) {
                engagementIds.add(subscription.Engagement__c);
            }
            if (subscription.Product__c != null) {
                productIds.add(subscription.Product__c);
            }
            if (subscription.Contract__c != null) {
                contractIds.add(subscription.Contract__c);
            }
        }
        Map<Id, Engagement__c> engagements =
            RenewalRepository.engagements(engagementIds);
        Map<Id, Account> accounts = RenewalRepository.accounts(accountIds);
        Map<Id, Product2> products = RenewalRepository.products(productIds);
        Map<Id, Contract> contracts = RenewalRepository.contracts(contractIds);

        List<RenewalContext> contexts = buildContexts(
            outputs,
            validInputs,
            originalIndexByIntakeIndex,
            results,
            requests,
            subscriptions,
            engagements,
            accounts,
            products,
            contracts,
            today
        );

        List<Customer_Request__c> requestUpdates =
            new List<Customer_Request__c>();
        List<Case> casesToClose = new List<Case>();
        List<RenewalContext> approved = new List<RenewalContext>();
        for (RenewalContext context : contexts) {
            applyDecision(context, requestUpdates, results);
            if (context.request.Case__c != null) {
                casesToClose.add(
                    new Case(Id = context.request.Case__c, Status = 'Closed')
                );
            }
            if (
                context.rejectionReason == null &&
                context.request.Status__c == RenewalPolicy.STATUS_APPROVED
            ) {
                approved.add(context);
            }
        }
        if (!requestUpdates.isEmpty()) {
            Database.update(requestUpdates, true);
        }
        if (!casesToClose.isEmpty()) {
            Database.update(casesToClose, true);
        }
        RenewalFulfilment.apply(approved, today);
        return results;
    }

    private static void mapIntakeErrors(
        List<LifecycleRequestService.RequestOutput> outputs,
        Map<Integer, Integer> originalIndexByIntakeIndex,
        List<RenewalService.RenewalResult> results
    ) {
        for (Integer j = 0; j < outputs.size(); j++) {
            Integer index = originalIndexByIntakeIndex.get(j);
            if (index != null) {
                results[index].failed(outputs[j].message);
            }
        }
    }

    private static List<RenewalContext> buildContexts(
        List<LifecycleRequestService.RequestOutput> outputs,
        Map<Integer, RenewalService.RenewalInput> validInputs,
        Map<Integer, Integer> originalIndexByIntakeIndex,
        List<RenewalService.RenewalResult> results,
        Map<Id, Customer_Request__c> requests,
        Map<Id, Subscription__c> subscriptions,
        Map<Id, Engagement__c> engagements,
        Map<Id, Account> accounts,
        Map<Id, Product2> products,
        Map<Id, Contract> contracts,
        Date today
    ) {
        List<RenewalContext> contexts = new List<RenewalContext>();
        for (Integer j = 0; j < outputs.size(); j++) {
            Integer index = originalIndexByIntakeIndex.get(j);
            if (index == null) {
                continue;
            }
            RenewalService.RenewalInput input = validInputs.get(j);
            LifecycleRequestService.RequestOutput intake = outputs[j];
            RenewalService.RenewalResult result = results[index];
            result.requestId = intake.requestId;
            result.caseId = intake.caseId;
            result.subscriptionId = input.subscriptionId;
            result.decision = input.decision;
            if (!intake.success || intake.requestId == null) {
                result.failed(intake.message);
                continue;
            }
            if (intake.status == RenewalPolicy.STATUS_AWAITING) {
                result.awaiting(0);
                continue;
            }
            if (intake.status != RenewalPolicy.STATUS_APPROVED) {
                result.failed('The renewal request is not ready for fulfilment.');
                continue;
            }

            RenewalContext context = new RenewalContext();
            context.resultIndex = index;
            context.result = result;
            context.input = input;
            context.request = requests.get(intake.requestId);
            context.subscription = subscriptions.get(input.subscriptionId);
            context.engagement = context.subscription == null
                ? null
                : engagements.get(context.subscription.Engagement__c);
            context.account = accounts.get(input.accountId);
            context.product = context.input.decision ==
                RenewalPolicy.DECISION_NEW_PLAN
                ? products.get(input.targetProductId)
                : products.get(context.subscription.Product__c);
            context.contract = context.subscription == null
                ? null
                : contracts.get(context.subscription.Contract__c);
            context.commitmentCode = RenewalValidator.resolveCommitment(
                input.commitmentCode,
                context.engagement
            );
            RenewalValidator.validateAndQuote(context, today);
            contexts.add(context);
        }
        return contexts;
    }

    private static void applyDecision(
        RenewalContext context,
        List<Customer_Request__c> requestUpdates,
        List<RenewalService.RenewalResult> results
    ) {
        RenewalService.RenewalResult result = results[context.resultIndex];
        Customer_Request__c request = context.request;
        if (context.input.decision != RenewalPolicy.DECISION_NEW_PLAN &&
            context.subscription != null) {
            request.Requested_Product__c = context.subscription.Product__c;
        }
        request.Calculated_Fee__c = 0;
        request.Fee_Breakdown__c =
            RenewalValidator.buildBreakdown(context).left(1000);

        if (context.rejectionReason != null) {
            request.Status__c = RenewalPolicy.STATUS_REJECTED;
            request.Rejection_Reason__c =
                context.rejectionReason.left(256);
            request.Resolution_Summary__c = 'Renewal rejected at eligibility.';
            request.Completed_On__c = Datetime.now();
            result.rejected(context.rejectionReason);
        } else if (request.Status__c == RenewalPolicy.STATUS_AWAITING) {
            request.Resolution_Summary__c =
                'Renewal quoted and awaiting manager approval.';
            result.awaiting(context.quotedAmount);
        } else {
            result.monthlyAmount = context.quotedAmount;
        }
        requestUpdates.add(request);
    }
}
