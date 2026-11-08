/**
 * @description Pure fibre eligibility decisions. The repository performs the
 * single eligibility lookup; this class never queries and never mutates the
 * caller's plan views.
 */
public class CatalogEligibilityFilter {
    private static final String PLAN_TYPE_FIBER = 'Fiber';

    /**
     * Returns true when the list contains a fibre plan or a null element that
     * the filter must remove. Non-fibre-only lists can bypass the eligibility
     * lookup entirely.
     */
    public static Boolean requiresFiltering(
        List<CatalogQueryService.ProductView> plans
    ) {
        if (plans == null) {
            return false;
        }
        for (CatalogQueryService.ProductView plan : plans) {
            if (plan == null || PLAN_TYPE_FIBER.equalsIgnoreCase(plan.planType)) {
                return true;
            }
        }
        return false;
    }

    public static List<CatalogQueryService.ProductView> filter(
        List<CatalogQueryService.ProductView> plans,
        Eligibility__c eligibility
    ) {
        List<CatalogQueryService.ProductView> filtered =
            new List<CatalogQueryService.ProductView>();

        for (CatalogQueryService.ProductView plan : plans) {
            if (plan == null) {
                continue;
            }
            if (!PLAN_TYPE_FIBER.equalsIgnoreCase(plan.planType)) {
                filtered.add(plan);
                continue;
            }
            if (eligibility == null || eligibility.Fiber_Available__c != true) {
                continue;
            }
            if (plan.speedMbps != null
                && (eligibility.Max_Downstream_Mbps__c == null
                    || plan.speedMbps > eligibility.Max_Downstream_Mbps__c)) {
                continue;
            }

            CatalogQueryService.ProductView eligiblePlan = plan.copy();
            eligiblePlan.earliestActivationDate = null;
            eligiblePlan.activationBlocked = false;
            if (eligibility.Earliest_Activation_Date__c != null
                && eligibility.Earliest_Activation_Date__c > Date.today()) {
                eligiblePlan.earliestActivationDate =
                    eligibility.Earliest_Activation_Date__c;
                eligiblePlan.activationBlocked = true;
            }
            filtered.add(eligiblePlan);
        }
        return filtered;
    }
}
