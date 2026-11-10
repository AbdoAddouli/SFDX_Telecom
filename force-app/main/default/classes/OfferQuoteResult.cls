/**
 * Maps persisted quote records and pricing breakdowns to the public result DTO.
 */
public class OfferQuoteResult {
    public static OfferBuilderService.OfferResult build(
        Quote quote,
        Opportunity opportunity,
        Id pricebookId,
        List<QuoteLineItem> lines,
        List<PricingService.PriceBreakdown> breakdowns,
        String breakdownJson
    ) {
        OfferBuilderService.OfferResult result =
            new OfferBuilderService.OfferResult();
        result.quoteId = quote.Id;
        result.quoteNumber = String.isBlank(quote.QuoteNumber)
            ? String.valueOf(quote.Id)
            : quote.QuoteNumber;
        result.quoteName = quote.Name;
        result.opportunityId = opportunity.Id;
        result.pricebookId = pricebookId;
        result.lineCount = lines.size();
        result.priceBreakdownJson = breakdownJson;

        for (QuoteLineItem line : lines) {
            result.quoteLineItemIds.add(line.Id);
        }
        for (PricingService.PriceBreakdown breakdown : breakdowns) {
            result.totalListPrice += breakdown.listPrice == null
                ? 0
                : breakdown.listPrice;
            result.totalAdjustment += breakdown.adjustmentTotal == null
                ? 0
                : breakdown.adjustmentTotal;
            result.totalPrice += breakdown.finalPrice == null
                ? 0
                : breakdown.finalPrice;
            if (breakdown.warningReasons != null) {
                result.warningReasons.addAll(breakdown.warningReasons);
            }
        }
        return result;
    }
}
