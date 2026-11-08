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
        @AuraEnabled public Id productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String name;
        @AuraEnabled public String family;
        @AuraEnabled public String planType;
        @AuraEnabled public Decimal dataGb;
        @AuraEnabled public Decimal speedMbps;
        @AuraEnabled public Boolean unlimitedCalls;
        @AuraEnabled public Boolean unlimitedSms;
        @AuraEnabled public Boolean recurring;
        @AuraEnabled public Boolean requiresCommitment;
        @AuraEnabled public String deviceImageUrl;
        @AuraEnabled public String specs;
        @AuraEnabled public Date earliestActivationDate;
        @AuraEnabled public Boolean activationBlocked;

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
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductView> getPlans(String offerType, String commitmentCode) {
        String normalizedType = normalizeOfferType(offerType);
        String normalizedCommitment = PricingScope.normalizeCommitment(commitmentCode);
        return toViews(
            CatalogQueryRepository.findPlans(normalizedType),
            normalizedCommitment
        );
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
