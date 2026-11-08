/**
 * @description Revenue Core pricing facade.
 *
 * The service validates and normalizes requests, loads a batch through
 * PricingBatchRepository exactly once, delegates pure calculations to
 * PricingRuleEvaluator and ConfigurationRuleEvaluator, and returns one
 * PriceBreakdown per request in input order.
 *
 * No SOQL and no DML run inside request loops.
 */
public with sharing class PricingService {
    /** Maximum requests per call. Callers must chunk larger workloads. */
    public static final Integer MAX_BATCH_SIZE = 200;

    public class PricingException extends Exception {}

    public class AppliedRule {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String ruleType;
        @AuraEnabled public String adjustmentType;
        @AuraEnabled public Decimal adjustmentValue;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public String targetScope;
        @AuraEnabled public String requiresProduct;

        public AppliedRule() {
            this.amount = 0;
        }
    }

    public class PriceBreakdown {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String commitmentCode;
        @AuraEnabled public String segment;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public Id pricebookId;
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public Decimal listPrice;
        @AuraEnabled public Decimal adjustmentTotal;
        @AuraEnabled public Decimal finalPrice;
        @AuraEnabled public List<AppliedRule> appliedRules;
        @AuraEnabled public List<String> blockingReasons;
        @AuraEnabled public List<String> warningReasons;

        public PriceBreakdown() {
            this.listPrice = 0;
            this.adjustmentTotal = 0;
            this.finalPrice = 0;
            this.appliedRules = new List<AppliedRule>();
            this.blockingReasons = new List<String>();
            this.warningReasons = new List<String>();
        }
    }

    public class PriceRequest {
        public Id productId;
        public String commitmentCode;
        public String segment;
        public Date effectiveDate;
        public Set<String> companionScopes;

        public PriceRequest() {
            this.companionScopes = new Set<String>();
        }

        public PriceRequest(
            Id productId,
            String commitmentCode,
            String segment,
            Date effectiveDate
        ) {
            this(productId, commitmentCode, segment, effectiveDate, new Set<String>());
        }

        public PriceRequest(
            Id productId,
            String commitmentCode,
            String segment,
            Date effectiveDate,
            Set<String> companionScopes
        ) {
            this.productId = productId;
            this.commitmentCode = commitmentCode;
            this.segment = segment;
            this.effectiveDate = effectiveDate;
            this.companionScopes = companionScopes == null
                ? new Set<String>()
                : new Set<String>(companionScopes);
        }
    }

    public class ConfigResult {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String ruleKind;
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
        @AuraEnabled public String productScope;
        @AuraEnabled public String companionProduct;
        @AuraEnabled public String appliesWhenCommitment;
        @AuraEnabled public Boolean blocking;
        @AuraEnabled public Boolean warning;

        public ConfigResult() {
            this.blocking = false;
            this.warning = false;
        }
    }

    /**
     * Prices one product without companion context. Bundle rules that require
     * a companion product do not fire through this overload.
     */
    public static PriceBreakdown price(
        Id productId,
        String commitmentCode,
        String segment,
        Date effectiveDate
    ) {
        return price(productId, commitmentCode, segment, effectiveDate, new Set<String>());
    }

    /**
     * Prices one product with a set of companion product scopes (for example,
     * TELCO_MOBILE or TELCO_RECURRING) already present in the quote.
     */
    public static PriceBreakdown price(
        Id productId,
        String commitmentCode,
        String segment,
        Date effectiveDate,
        Set<String> companionScopes
    ) {
        List<PriceRequest> requests = new List<PriceRequest>();
        requests.add(new PriceRequest(
            productId,
            commitmentCode,
            segment,
            effectiveDate,
            companionScopes
        ));
        return priceBulk(requests)[0];
    }

    /**
     * Bulk pricing entry point. One batch load covers every request in the list.
     */
    public static List<PriceBreakdown> priceBulk(List<PriceRequest> requests) {
        if (requests == null) {
            throw new PricingException('Pricing requests are required.');
        }
        if (requests.size() > MAX_BATCH_SIZE) {
            throw new PricingException(
                'priceBulk accepts at most ' + MAX_BATCH_SIZE +
                ' requests per call; split larger workloads into chunks.'
            );
        }

        List<PriceBreakdown> results = new List<PriceBreakdown>();
        if (requests.isEmpty()) {
            return results;
        }

        List<PricingContext> contexts = new List<PricingContext>();
        Set<Id> productIds = new Set<Id>();

        for (Integer i = 0; i < requests.size(); i++) {
            PriceRequest request = requests[i];
            if (request == null) {
                throw new PricingException('Pricing request is null at index ' + i + '.');
            }
            if (request.productId == null) {
                throw new PricingException('Product id is required for request ' + i + '.');
            }

            PricingContext context = new PricingContext(
                request.productId,
                request.commitmentCode,
                request.segment,
                request.effectiveDate,
                request.companionScopes
            );
            contexts.add(context);
            productIds.add(context.productId);
        }

        PricingBatchRepository batch = PricingBatchRepository.load(productIds);

        for (PricingContext context : contexts) {
            Product2 product = batch.productsById.get(context.productId);
            if (product == null) {
                throw new PricingException('Product not found: ' + context.productId);
            }
            if (product.IsActive == false) {
                throw new PricingException('Product is inactive: ' + product.Name);
            }
            context.product = product;
        }

        for (PricingContext context : contexts) {
            PricebookEntry entry =
                batch.pricebookEntriesByProductId.get(context.productId);
            if (entry == null) {
                throw new PricingException(
                    'No active pricebook entry for product: ' + context.product.Name
                );
            }
            context.pricebookEntry = entry;
            context.listPrice = entry.UnitPrice == null
                ? 0
                : entry.UnitPrice.setScale(2, RoundingMode.HALF_UP);
        }

        for (PricingContext context : contexts) {
            results.add(buildBreakdown(context, batch));
        }

        return results;
    }

    /**
     * Evaluates commitment-only configuration rules for one product.
     */
    public static List<ConfigResult> evaluateConfiguration(
        Id productId,
        String commitmentCode
    ) {
        return evaluateConfiguration(productId, commitmentCode, new Set<String>());
    }

    /**
     * Evaluates configuration rules for one product, including companion
     * constraints when companion scopes are supplied.
     */
    public static List<ConfigResult> evaluateConfiguration(
        Id productId,
        String commitmentCode,
        Set<String> companionScopes
    ) {
        if (productId == null) {
            throw new PricingException('Product id is required.');
        }

        Product2 product = PricingBatchRepository.loadProduct(productId);
        if (product == null) {
            throw new PricingException('Product not found: ' + productId);
        }
        if (product.IsActive == false) {
            throw new PricingException('Product is inactive: ' + product.Name);
        }

        PricingContext context = new PricingContext(
            productId,
            commitmentCode,
            null,
            null,
            companionScopes
        );
        context.product = product;

        return ConfigurationRuleEvaluator.evaluate(
            context,
            PricingBatchRepository.loadConfigRules()
        );
    }

    private static PriceBreakdown buildBreakdown(
        PricingContext context,
        PricingBatchRepository batch
    ) {
        PriceBreakdown result = new PriceBreakdown();
        result.productId = context.product.Id;
        result.productName = context.product.Name;
        result.productFamily = context.product.Family;
        result.commitmentCode = context.commitmentCode;
        result.segment = context.segment;
        result.effectiveDate = context.effectiveDate;
        result.pricebookId = context.pricebookEntry.Pricebook2Id;
        result.pricebookEntryId = context.pricebookEntry.Id;
        result.listPrice = context.listPrice;

        PricingRuleEvaluator.Result pricing =
            PricingRuleEvaluator.apply(context, batch.pricingRules);
        result.finalPrice = pricing.finalPrice;
        result.adjustmentTotal = pricing.adjustmentTotal;
        result.appliedRules = pricing.appliedRules;

        for (ConfigResult config : ConfigurationRuleEvaluator.evaluate(
            context,
            batch.configRules
        )) {
            if (config.blocking) {
                result.blockingReasons.add(config.message);
            } else if (config.warning) {
                result.warningReasons.add(config.message);
            }
        }

        return result;
    }
}
