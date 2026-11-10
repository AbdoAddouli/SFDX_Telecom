/**
 * Prices a plan and optional device in one batch and validates the returned
 * breakdowns. No DML is performed here.
 */
public class OfferQuotePricing {
    private static final Integer MAX_BREAKDOWN_LENGTH = 10068;

    public class PricedOffer {
        public Id pricebookId;
        public String breakdownJson;
        public List<PricingService.PriceBreakdown> breakdowns;
    }

    public static PricedOffer price(
        OfferContext context,
        OfferCatalog catalog
    ) {
        List<PricingService.PriceRequest> requests =
            buildRequests(context, catalog);
        List<PricingService.PriceBreakdown> breakdowns =
            PricingService.priceBulk(requests);
        validateBreakdowns(breakdowns, requests.size());

        PricedOffer priced = new PricedOffer();
        priced.breakdowns = breakdowns;
        priced.pricebookId = resolvePricebookId(breakdowns);
        priced.breakdownJson = serializeBreakdowns(breakdowns);
        return priced;
    }

    private static List<PricingService.PriceRequest> buildRequests(
        OfferContext context,
        OfferCatalog catalog
    ) {
        Set<String> planCompanions = new Set<String>();
        Set<String> deviceCompanions = new Set<String>();
        if (catalog.device != null) {
            planCompanions.add(catalog.device.family);
            deviceCompanions.add(catalog.plan.family);
        }

        List<PricingService.PriceRequest> requests =
            new List<PricingService.PriceRequest>();
        requests.add(new PricingService.PriceRequest(
            catalog.plan.productId,
            context.commitmentCode,
            context.segment,
            context.effectiveDate,
            planCompanions
        ));
        if (catalog.device != null) {
            requests.add(new PricingService.PriceRequest(
                catalog.device.productId,
                context.commitmentCode,
                context.segment,
                context.effectiveDate,
                deviceCompanions
            ));
        }
        return requests;
    }

    private static void validateBreakdowns(
        List<PricingService.PriceBreakdown> breakdowns,
        Integer requestCount
    ) {
        if (breakdowns == null || breakdowns.size() != requestCount) {
            throw new OfferBuilderService.OfferException(
                'Pricing did not return a complete breakdown.'
            );
        }
        for (PricingService.PriceBreakdown breakdown : breakdowns) {
            if (breakdown == null
                || breakdown.pricebookId == null
                || breakdown.pricebookEntryId == null
                || breakdown.finalPrice == null) {
                throw new OfferBuilderService.OfferException(
                    'Pricing returned an incomplete quote line.'
                );
            }
            if (breakdown.blockingReasons != null
                && !breakdown.blockingReasons.isEmpty()) {
                throw new OfferBuilderService.OfferException(
                    joinMessages(breakdown.blockingReasons)
                );
            }
        }
    }

    private static Id resolvePricebookId(
        List<PricingService.PriceBreakdown> breakdowns
    ) {
        Id pricebookId = breakdowns[0].pricebookId;
        for (PricingService.PriceBreakdown breakdown : breakdowns) {
            if (breakdown.pricebookId != pricebookId) {
                throw new OfferBuilderService.OfferException(
                    'All quote lines must use the same pricebook.'
                );
            }
        }
        return pricebookId;
    }

    private static String serializeBreakdowns(
        List<PricingService.PriceBreakdown> breakdowns
    ) {
        String json = JSON.serialize(breakdowns);
        if (json.length() > MAX_BREAKDOWN_LENGTH) {
            throw new OfferBuilderService.OfferException(
                'The price breakdown is too large to persist on the wizard session.'
            );
        }
        return json;
    }

    private static String joinMessages(List<String> messages) {
        String joined = '';
        for (String message : messages) {
            if (String.isNotBlank(message)) {
                joined += (String.isBlank(joined) ? '' : ' ') + message;
            }
        }
        return String.isBlank(joined)
            ? 'The selected configuration is not valid.'
            : joined;
    }
}
