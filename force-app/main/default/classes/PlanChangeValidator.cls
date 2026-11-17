/**
 * Pure plan-change rules. No SOQL or DML; every check is safe to run for each
 * row of a bulk request. Only pricing calls are delegated to the catalogue.
 */
public with sharing class PlanChangeValidator {
    public static String inputError(PlanChangeService.PlanChangeInput input) {
        if (input == null
            || input.accountId == null
            || input.contactId == null
            || input.subscriptionId == null
            || input.targetProductId == null
            || String.isBlank(input.channel)) {
            return 'Account, Contact, Subscription, target plan and Channel are required.';
        }
        return null;
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        PlanChangeService.PlanChangeInput input
    ) {
        LifecycleRequestService.RequestInput request =
            new LifecycleRequestService.RequestInput();
        request.requestType = PlanChangePolicy.REQUEST_TYPE;
        request.accountId = input.accountId;
        request.contactId = input.contactId;
        request.subscriptionId = input.subscriptionId;
        request.channel = input.channel;
        request.requestedProduct = input.targetProductId;
        request.customerComment = input.customerComment;
        request.priority = input.priority;
        return request;
    }

    public static String resolveCommitment(
        String requested,
        Subscription__c source,
        Engagement__c engagement
    ) {
        if (String.isNotBlank(requested)) {
            return requested.trim().toUpperCase();
        }
        if (source != null && source.Is_Committed__c == true && engagement != null) {
            if (engagement.Duration_Months__c == 24) {
                return PlanChangePolicy.COMMIT_24;
            }
            if (engagement.Duration_Months__c == 12) {
                return PlanChangePolicy.COMMIT_12;
            }
        }
        return PlanChangePolicy.NO_COMMIT;
    }

    public static void validateAndQuote(PlanChangeContext context, Date today) {
        if (context.source == null || context.account == null || context.request == null) {
            context.rejectionReason = 'The source line or account could not be resolved.';
            return;
        }
        if (context.source.Status__c != SubscriptionStateMachine.ACTIVE) {
            context.rejectionReason = 'Only an active line can be changed.';
            return;
        }
        if (context.engagement == null
            || context.engagement.Status__c != PlanChangePolicy.ACTIVE_ENGAGEMENT
            || context.engagement.End_Date__c == null
            || context.engagement.End_Date__c < today) {
            context.rejectionReason = 'The impacted engagement is not active.';
            return;
        }
        if (context.product == null || context.product.IsActive == false) {
            context.rejectionReason = 'The target plan is not active.';
            return;
        }
        if (context.source.Product__c == context.input.targetProductId) {
            context.rejectionReason = 'The target plan is already active on this line.';
            return;
        }
        if (context.product.Family == PlanChangePolicy.FIBER && !isFiberEligible(context)) {
            context.rejectionReason = 'The target plan is not eligible at this address.';
            return;
        }

        try {
            context.price = CatalogQueryService.getPriceBreakdown(
                context.input.targetProductId,
                context.commitmentCode,
                context.account.Segment__c,
                today,
                new List<String>()
            );
            if (context.price.blockingReasons != null
                && !context.price.blockingReasons.isEmpty()) {
                context.rejectionReason =
                    'The target plan could not be priced: ' +
                    String.join(context.price.blockingReasons, ' ');
            }
        } catch (Exception exceptionRecord) {
            context.rejectionReason = 'The target plan could not be priced.';
        }
    }

    public static Decimal parseQuotedAmount(String breakdown) {
        if (String.isBlank(breakdown)) {
            return null;
        }
        Integer start = breakdown.indexOf(PlanChangePolicy.QUOTE_MARKER);
        if (start == null || start < 0) {
            return null;
        }
        String tail = breakdown.substring(
            start + PlanChangePolicy.QUOTE_MARKER.length()
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

    public static String buildBreakdown(PricingService.PriceBreakdown price) {
        return 'Target plan: ' + price.productName +
            ' | Commitment: ' + price.commitmentCode +
            ' | List price: ' + price.listPrice +
            ' | Adjustments: ' + price.adjustmentTotal +
            ' | New monthly amount: ' + price.finalPrice;
    }

    private static Boolean isFiberEligible(PlanChangeContext context) {
        String postalCode = String.isBlank(context.input.postalCode)
            ? context.account.BillingPostalCode
            : context.input.postalCode;
        List<CatalogQueryService.ProductView> plans =
            CatalogQueryService.getPlans(
                PlanChangePolicy.FIBER, context.commitmentCode
            );
        List<CatalogQueryService.ProductView> eligible =
            CatalogQueryService.filterByEligibility(plans, postalCode);
        for (CatalogQueryService.ProductView plan : eligible) {
            if (plan.productId == context.input.targetProductId) {
                return true;
            }
        }
        return false;
    }
}
