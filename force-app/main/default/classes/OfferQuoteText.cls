/**
 * Pure formatting helpers for quote text and generated subscription keys.
 */
public class OfferQuoteText {
    public static String opportunityName(Account account, String offerType) {
        return (account.Name + ' - ' + offerType).left(120);
    }

    public static String quoteName(
        Account account,
        String planName,
        String commitmentCode
    ) {
        return (account.Name + ' - ' + planName + ' - ' + commitmentCode)
            .left(255);
    }

    public static String quoteDescription(
        CatalogQueryService.ProductView plan,
        CatalogQueryService.ProductView device,
        String commitmentCode
    ) {
        String description = 'ATS quote for ' + plan.name;
        if (device != null) {
            description += ' with ' + device.name;
        }
        return (description + ' (' + commitmentCode + ')').left(32000);
    }

    public static String lineDescription(
        PricingService.PriceBreakdown breakdown
    ) {
        String name = String.isBlank(breakdown.productName)
            ? 'ATS line'
            : breakdown.productName;
        return name.left(55);
    }

    public static String subscriptionKey(Quote quote, Integer index) {
        String quoteNumber = String.isBlank(quote.QuoteNumber)
            ? String.valueOf(quote.Id)
            : quote.QuoteNumber;
        String suffix = '-' + String.valueOf(index + 1);
        Integer maxPrefixLength = 30 - suffix.length();
        String prefix = quoteNumber.length() > maxPrefixLength
            ? quoteNumber.left(maxPrefixLength)
            : quoteNumber;
        return prefix + suffix;
    }
}
