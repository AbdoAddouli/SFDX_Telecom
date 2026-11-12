/**
 * @description Authoritative catalogue and pricing read path for the advisor
 * wizard and the portal.
 *
 * This facade validates inputs, maps Product2 rows to client-safe views, and
 * delegates configuration and pricing to PricingService. Data access lives in
 * CatalogQueryRepository and the fibre decision lives in
 * CatalogEligibilityFilter, so this class stays focused on orchestration.
 *
 * Every public method performs a bounded number of queries; no SOQL or DML runs
 * inside a product loop. Pricing and eligibility reads use user mode.
 */
public with sharing class CatalogQueryService {
    private static final List<String> OFFER_TYPES = new List<String>{
        'Mobile',
        'Fiber',
        'Landline'
    };

    public class CatalogException extends Exception {}

    public class ProductView {
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public String planType { get; set; }
        @AuraEnabled public Decimal dataGb { get; set; }
        @AuraEnabled public Decimal speedMbps { get; set; }
        @AuraEnabled public Boolean unlimitedCalls { get; set; }
        @AuraEnabled public Boolean unlimitedSms { get; set; }
        @AuraEnabled public Boolean recurring { get; set; }
        @AuraEnabled public Boolean requiresCommitment { get; set; }
        @AuraEnabled public String deviceImageUrl { get; set; }
        @AuraEnabled public String specs { get; set; }
        @AuraEnabled public Date earliestActivationDate { get; set; }
        @AuraEnabled public Boolean activationBlocked { get; set; }

        public ProductView() {
            this.unlimitedCalls = false;
            this.unlimitedSms = false;
            this.recurring = false;
            this.requiresCommitment = false;
            this.activationBlocked = false;
        }

        public ProductView copy() {
            ProductView copy = new ProductView();
            copy.productId = productId;
            copy.productCode = productCode;
            copy.name = name;
            copy.family = family;
            copy.planType = planType;
            copy.dataGb = dataGb;
            copy.speedMbps = speedMbps;
            copy.unlimitedCalls = unlimitedCalls;
            copy.unlimitedSms = unlimitedSms;
            copy.recurring = recurring;
            copy.requiresCommitment = requiresCommitment;
            copy.deviceImageUrl = deviceImageUrl;
            copy.specs = specs;
            copy.earliestActivationDate = earliestActivationDate;
            copy.activationBlocked = activationBlocked;
            return copy;
        }
    }

    /**
     * Returns active plans for the requested offer type. A blank commitment is
     * treated as NOCOMMIT, which excludes plans that require a commitment.
     * Configuration rules are evaluated once for the full plan list, so plans
     * with blocking option rules never reach the picker.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> getPlans(String offerType, String commitmentCode) {
        String normalizedType = normalizeOfferType(offerType);
        String normalizedCommitment = PricingScope.normalizeCommitment(commitmentCode);
        List<Product2> products = CatalogQueryRepository.findPlans(normalizedType);
        List<ProductView> views = toViews(products, normalizedCommitment);
        Map<Id, List<PricingService.ConfigResult>> configs =
            PricingService.evaluateConfigurations(products, normalizedCommitment);

        List<ProductView> compatible = new List<ProductView>();
        for (ProductView view : views) {
            if (!hasBlockingConfig(configs.get(view.productId))) {
                compatible.add(view);
            }
        }
        return compatible;
    }

    /**
     * Returns active devices. Commitment compatibility is evaluated by
     * getOptions(), not hidden in the catalogue query.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> getDevices() {
        return toViews(CatalogQueryRepository.findDevices(), null);
    }

    /**
     * Evaluates the configuration rules attached to one product.
     */
    @AuraEnabled(cacheable=true)
    public static List<PricingService.ConfigResult> getOptions(
        Id productId,
        String commitmentCode
    ) {
        requireProductId(productId);
        return PricingService.evaluateConfiguration(productId, commitmentCode);
    }

    /**
     * Returns the authoritative server-side price breakdown for one product.
     */
    @AuraEnabled(cacheable=true)
    public static PricingService.PriceBreakdown getPriceBreakdown(
        Id productId,
        String commitmentCode,
        String segment,
        Date effectiveDate,
        List<String> companionScopes
    ) {
        requireProductId(productId);

        Set<String> companions = companionScopes == null
            ? new Set<String>()
            : new Set<String>(companionScopes);
        return PricingService.price(
            productId,
            commitmentCode,
            segment,
            effectiveDate,
            companions
        );
    }

    /**
     * Fibre speed gate. Non-fibre-only lists bypass the eligibility query.
     * A future earliest activation date keeps the plan selectable but marks it
     * blocked so the caller can set expectations before checkout.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> filterByEligibility(
        List<ProductView> plans,
        String postalCode
    ) {
        if (plans == null
            || plans.isEmpty()
            || String.isBlank(postalCode)
            || !CatalogEligibilityFilter.requiresFiltering(plans)) {
            return plans;
        }

        Eligibility__c eligibility = CatalogQueryRepository.findEligibility(
            postalCode.trim()
        );
        return CatalogEligibilityFilter.filter(plans, eligibility);
    }

    private static Boolean hasBlockingConfig(
        List<PricingService.ConfigResult> configs
    ) {
        if (configs == null) {
            return false;
        }
        for (PricingService.ConfigResult config : configs) {
            if (config.blocking) {
                return true;
            }
        }
        return false;
    }

    private static void requireProductId(Id productId) {
        if (productId == null) {
            throw new CatalogException('Product id is required.');
        }
    }

    private static String normalizeOfferType(String offerType) {
        if (String.isBlank(offerType)) {
            throw new CatalogException('Offer type is required.');
        }
        String normalized = offerType.trim();
        for (String allowed : OFFER_TYPES) {
            if (allowed.equalsIgnoreCase(normalized)) {
                return allowed;
            }
        }
        throw new CatalogException('Unsupported offer type: ' + offerType);
    }

    private static List<ProductView> toViews(
        List<Product2> products,
        String commitmentCode
    ) {
        List<ProductView> views = new List<ProductView>();
        Boolean noCommitment = PricingScope.NO_COMMITMENT.equals(commitmentCode);
        for (Product2 product : products) {
            if (noCommitment && product.Requires_Commitment__c == true) {
                continue;
            }
            views.add(toView(product));
        }
        return views;
    }

    private static ProductView toView(Product2 product) {
        ProductView view = new ProductView();
        view.productId = product.Id;
        view.productCode = product.ATS_Product_Code__c;
        view.name = product.Name;
        view.family = product.Family;
        view.planType = product.Plan_Type__c;
        view.dataGb = product.Data_GB__c;
        view.speedMbps = product.Speed_Mbps__c;
        view.unlimitedCalls = product.Unlimited_Calls__c == true;
        view.unlimitedSms = product.Unlimited_SMS__c == true;
        view.recurring = product.Recurring__c == true;
        view.requiresCommitment = product.Requires_Commitment__c == true;
        view.deviceImageUrl = product.Device_Image_URL__c;
        view.specs = product.Specs__c;
        return view;
    }
}
