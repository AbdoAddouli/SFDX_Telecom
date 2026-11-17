/**
 * Builds the Customer_Request__c/Case pair from a validated item. Fee
 * calculation is delegated to EngagementPenaltyService; no DML happens here.
 */
public with sharing class LifecycleRequestBuilder {
    public static void prepare(
        LifecycleRequestItem item,
        Decimal threshold,
        Date today
    ) {
        LifecycleRequestService.RequestInput input = item.input;
        Decimal fee = 0;
        String breakdown = 'No early-termination fee applies to this request type.';
        if (item.engagement != null && isPenaltyApplicable(input.requestType)) {
            EngagementPenaltyService.Result result =
                EngagementPenaltyService.calculate(
                    item.engagement,
                    item.account.Segment__c,
                    item.subscription.Service_Line_Type__c,
                    today
                );
            fee = result.fee;
            breakdown = result.breakdown;
        }
        item.fee = fee;
        if (input.goodwillWaiver == true) {
            breakdown += ' Goodwill waiver requested: ' +
                input.goodwillJustification;
        }

        String status = resolveStatus(input, fee, threshold);
        Id approvedBy;
        Datetime approvedOn;
        if (status == LifecycleRequestPolicy.STATUS_APPROVED) {
            approvedBy = UserInfo.getUserId();
            approvedOn = Datetime.now();
        }

        item.request = new Customer_Request__c(
            Account__c = item.resolvedAccountId,
            Contact__c = input.contactId,
            Subscription__c = input.subscriptionId,
            Impacted_Engagement__c = item.engagement == null ? null : item.engagement.Id,
            Request_Type__c = input.requestType,
            Channel__c = input.channel,
            Requested_Product__c = input.requestedProduct,
            Cancellation_Reason__c = input.cancellationReason,
            Cancellation_Effective_Date__c = input.cancellationEffectiveDate,
            Customer_Comment__c = input.customerComment,
            Calculated_Fee__c = fee,
            Fee_Breakdown__c = breakdown.left(1000),
            Priority__c = normalizePriority(input.priority),
            Related_Quote__c = input.relatedQuoteId,
            Related_Order__c = input.relatedOrderId,
            Submitted_By__c = UserInfo.getUserId(),
            Status__c = status,
            Approved_By__c = approvedBy,
            Approved_On__c = approvedOn
        );

        if (input.requestType != LifecycleRequestPolicy.TYPE_INFO) {
            item.caseRecord = new Case(
                AccountId = item.resolvedAccountId,
                ContactId = input.contactId,
                Subject = input.requestType + ' request',
                Description = buildDescription(input),
                Origin = originFor(input.channel),
                Priority = casePriority(input.priority),
                Status = 'New'
            );
        }
    }

    private static Boolean isPenaltyApplicable(String requestType) {
        return LifecycleRequestPolicy.PENALTY_TYPES.contains(requestType);
    }

    private static String resolveStatus(
        LifecycleRequestService.RequestInput input,
        Decimal fee,
        Decimal threshold
    ) {
        if (input.requestType == LifecycleRequestPolicy.TYPE_INFO) {
            return LifecycleRequestPolicy.STATUS_COMPLETED;
        }
        if (input.goodwillWaiver == true || fee > threshold) {
            return LifecycleRequestPolicy.STATUS_AWAITING;
        }
        return LifecycleRequestPolicy.STATUS_APPROVED;
    }

    private static String buildDescription(
        LifecycleRequestService.RequestInput input
    ) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(input.cancellationReason)) {
            parts.add('Reason: ' + input.cancellationReason);
        }
        if (input.cancellationEffectiveDate != null) {
            parts.add('Effective: ' + input.cancellationEffectiveDate.format());
        }
        if (String.isNotBlank(input.customerComment)) {
            parts.add(input.customerComment);
        }
        return String.join(parts, ' | ').left(4000);
    }

    private static String originFor(String channel) {
        return channel == 'Advisor' ? 'Phone' : 'Web';
    }

    private static String normalizePriority(String priority) {
        return LifecycleRequestPolicy.VALID_PRIORITIES.contains(priority)
            ? priority
            : 'Normal';
    }

    private static String casePriority(String priority) {
        if (priority == 'High' || priority == 'Critical') {
            return 'High';
        }
        return priority == 'Low' ? 'Low' : 'Medium';
    }
}
