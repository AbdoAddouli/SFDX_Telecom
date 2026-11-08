/**
 * @description Shared scope, commitment, companion, and effective-date rules
 * used by pricing and configuration evaluation.
 */
public class PricingScope {
    public static final String SCOPE_RECURRING = 'TELCO_RECURRING';
    public static final String SCOPE_MOBILE = 'TELCO_MOBILE';
    public static final String SCOPE_FIBER = 'TELCO_FIBER';
    public static final String NO_COMMITMENT = 'NOCOMMIT';

    public static String normalize(String value) {
        return value == null ? '' : value.trim().toUpperCase();
    }

    public static String normalizeCommitment(String value) {
        String normalized = normalize(value);
        return String.isBlank(normalized) ? NO_COMMITMENT : normalized;
    }

    public static Boolean scopeMatches(String scope, Product2 product) {
        if (String.isBlank(scope)) {
            return true;
        }
        if (product == null || String.isBlank(product.Family)) {
            return false;
        }
        if (scope.equalsIgnoreCase(product.Family)) {
            return true;
        }
        if (SCOPE_RECURRING.equalsIgnoreCase(scope)
            && (SCOPE_MOBILE.equalsIgnoreCase(product.Family)
                || SCOPE_FIBER.equalsIgnoreCase(product.Family))) {
            return true;
        }
        if (String.isNotBlank(product.ATS_Product_Code__c)
            && scope.equalsIgnoreCase(product.ATS_Product_Code__c)) {
            return true;
        }
        return false;
    }

    public static Boolean companionRequirementMet(
        String requiredScope,
        Set<String> companionScopes
    ) {
        if (String.isBlank(requiredScope)) {
            return true;
        }
        return companionPresent(requiredScope, companionScopes);
    }

    public static Boolean companionPresent(
        String requiredScope,
        Set<String> companionScopes
    ) {
        if (String.isBlank(requiredScope)
            || companionScopes == null
            || companionScopes.isEmpty()) {
            return false;
        }
        for (String suppliedScope : companionScopes) {
            if (scopeCodeMatches(requiredScope, suppliedScope)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean scopeCodeMatches(String requiredScope, String suppliedScope) {
        if (String.isBlank(suppliedScope)) {
            return false;
        }
        if (requiredScope.equalsIgnoreCase(suppliedScope)) {
            return true;
        }
        if (SCOPE_RECURRING.equalsIgnoreCase(requiredScope)
            && (SCOPE_MOBILE.equalsIgnoreCase(suppliedScope)
                || SCOPE_FIBER.equalsIgnoreCase(suppliedScope))) {
            return true;
        }
        return false;
    }

    public static Boolean codeMatches(String ruleValue, String suppliedValue) {
        return String.isBlank(ruleValue)
            || ruleValue.trim().equalsIgnoreCase(suppliedValue);
    }

    public static Boolean isEffective(Pricing_Rule__mdt rule, Date pricingDate) {
        if (rule.Effective_From__c != null && pricingDate < rule.Effective_From__c) {
            return false;
        }
        if (rule.Effective_To__c != null && pricingDate > rule.Effective_To__c) {
            return false;
        }
        return true;
    }
}
