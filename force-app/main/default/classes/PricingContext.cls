/**
 * @description Per-request pricing state. The service resolves the product and
 * pricebook entry once, then passes this context to the evaluators.
 */
public class PricingContext {
    public Id productId;
    public String commitmentCode;
    public String segment;
    public Date effectiveDate;
    public Set<String> companionScopes;
    public Product2 product;
    public PricebookEntry pricebookEntry;
    public Decimal listPrice;

    public PricingContext(
        Id productId,
        String commitmentCode,
        String segment,
        Date effectiveDate,
        Set<String> companionScopes
    ) {
        this.productId = productId;
        this.commitmentCode = PricingScope.normalizeCommitment(commitmentCode);
        this.segment = PricingScope.normalize(segment);
        this.effectiveDate = effectiveDate == null ? Date.today() : effectiveDate;
        this.companionScopes = companionScopes == null
            ? new Set<String>()
            : new Set<String>(companionScopes);
        this.listPrice = 0;
    }
}
