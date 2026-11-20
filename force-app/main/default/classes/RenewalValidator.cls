/**
 * Pure UC-LIF-06 rules. No SOQL or DML; pricing is delegated to the catalogue
 * facade so renewal offers use exactly the new-sale pricing path.
 */
public with sharing class RenewalValidator {
    public static String inputError(RenewalService.RenewalInput input) {
        if (input == null) {
            return 'Renewal details are required.';
        }
        if (
            input.accountId == null ||
            input.contactId == null ||
            input.subscriptionId == null ||
            String.isBlank(input.decision) ||
            String.isBlank(input.channel)
        ) {
            return 'Account, Contact, Subscription, Decision and Channel are required.';
        }
        if (!RenewalPolicy.DECISIONS.contains(input.decision)) {
            return 'A valid renewal Decision is required.';
        }
        if (input.decision == RenewalPolicy.DECISION_CANCEL) {
            return 'Use the cancellation flow for early termination.';
        }
        if (!LifecycleRequestPolicy.VALID_CHANNELS.contains(input.channel)) {
            return 'A valid Channel is required.';
        }
        if (
            input.decision == RenewalPolicy.DECISION_NEW_PLAN &&
            input.targetProductId == null
        ) {
            return 'A target plan is required for a new-plan renewal.';
        }
        if (
            input.decision != RenewalPolicy.DECISION_NEW_PLAN &&
            input.targetProductId != null
        ) {
            return 'A target plan is only valid for a new-plan renewal.';
        }
        return null;
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        RenewalService.RenewalInput input
    ) {
        LifecycleRequestService.RequestInput request =
            new LifecycleRequestService.RequestInput();
        request.requestType = RenewalPolicy.REQUEST_TYPE;
        request.accountId = input.accountId;
        request.contactId = input.contactId;
        request.subscriptionId = input.subscriptionId;
        request.requestedProduct = input.targetProductId;
        request.channel = input.channel;
        request.customerComment = input.customerComment;
        request.priority = input.priority;
        return request;
    }

    public static String resolveCommitment(
        String requested,
        Engagement__c engagement
    ) {
        if (String.isNotBlank(requested)) {
            return requested.trim().toUpperCase();
        }
        if (engagement != null && engagement.Duration_Months__c == 24) {
            return RenewalPolicy.COMMIT_24;
        }
        if (engagement != null && engagement.Duration_Months__c == 12) {
            return RenewalPolicy.COMMIT_12;
        }
        return RenewalPolicy.NO_COMMIT;
    }

    public static void validateAndQuote(RenewalContext context, Date today) {
        if (context.subscription == null || context.account == null) {
            context.rejectionReason = 'The subscription or account could not be resolved.';
            return;
        }
        if (context.subscription.Status__c != RenewalPolicy.SUBSCRIPTION_ACTIVE) {
            context.rejectionReason = 'Only an active line can be renewed.';
            return;
        }
        if (
            context.engagement == null ||
            context.engagement.Status__c != RenewalPolicy.ENGAGEMENT_ACTIVE ||
            context.engagement.End_Date__c == null
        ) {
            context.rejectionReason = 'The expiring engagement is not active.';
            return;
        }
        if (context.input.decision == RenewalPolicy.DECISION_CANCEL) {
            context.rejectionReason =
                'Use the cancellation flow for early termination.';
            return;
        }
        if (context.input.decision == RenewalPolicy.DECISION_LAPSE) {
            context.quotedAmount = context.subscription.Monthly_Amount__c;
            return;
        }
        if (context.product == null || context.product.IsActive == false) {
            context.rejectionReason = 'The renewal plan is not active.';
            return;
        }
        context.commitmentCode = resolveCommitment(
            context.input.commitmentCode,
            context.engagement
        );
        if (
            context.product.Family == RenewalPolicy.FIBER &&
            !isFiberEligible(context)
        ) {
            context.rejectionReason = 'The renewal plan is not eligible at this address.';
            return;
        }
        try {
            context.price = CatalogQueryService.getPriceBreakdown(
                context.product.Id,
                context.commitmentCode,
                context.account.Segment__c,
                today,
                new List<String>()
            );
            if (
                context.price.blockingReasons != null &&
                !context.price.blockingReasons.isEmpty()
            ) {
                context.rejectionReason =
                    'The renewal plan could not be priced: ' +
                    String.join(context.price.blockingReasons, ' ');
                return;
            }
            context.quotedAmount = context.price.finalPrice;
        } catch (Exception exceptionRecord) {
            context.rejectionReason = 'The renewal plan could not be priced.';
        }
    }

    public static String buildBreakdown(RenewalContext context) {
        if (context.price != null) {
            return 'Renewal plan: ' + context.price.productName +
                ' | Commitment: ' + context.price.commitmentCode +
                ' | List price: ' + context.price.listPrice +
                ' | Adjustments: ' + context.price.adjustmentTotal +
                ' | ' + RenewalPolicy.QUOTE_MARKER + context.quotedAmount;
        }
        if (context.input.decision == RenewalPolicy.DECISION_LAPSE) {
            return 'No new commitment. BQ4 monthly rollover applies. ' +
                RenewalPolicy.QUOTE_MARKER + context.quotedAmount;
        }
        return 'Renewal decision rejected. ' +
            RenewalPolicy.QUOTE_MARKER + context.quotedAmount;
    }

    public static Decimal parseQuotedAmount(String breakdown) {
        if (String.isBlank(breakdown)) {
            return null;
        }
        Integer start = breakdown.indexOf(RenewalPolicy.QUOTE_MARKER);
        if (start == null || start < 0) {
            return null;
        }
        String tail = breakdown.substring(
            start + RenewalPolicy.QUOTE_MARKER.length()
        ).trim();
        Integer endIndex = tail.indexOf('|');
        if (endIndex != null && endIndex >= 0) {
            tail = tail.substring(0, endIndex).trim();
        }
        try {
            return Decimal.valueOf(tail);
        } catch (Exception exceptionRecord) {
            return null;
        }
    }

    private static Boolean isFiberEligible(RenewalContext context) {
        String postalCode = String.isBlank(context.input.postalCode)
            ? context.account.BillingPostalCode
            : context.input.postalCode;
        List<CatalogQueryService.ProductView> plans =
            CatalogQueryService.getPlans(
                RenewalPolicy.FIBER,
                context.commitmentCode
            );
        List<CatalogQueryService.ProductView> eligible =
            CatalogQueryService.filterByEligibility(plans, postalCode);
        for (CatalogQueryService.ProductView plan : eligible) {
            if (plan.productId == context.product.Id) {
                return true;
            }
        }
        return false;
    }
}
