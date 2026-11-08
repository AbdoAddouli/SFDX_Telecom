/**
 * @description Evaluates Config_Rule__mdt records for one pricing context.
 * Pure calculation: no SOQL and no DML.
 */
public class ConfigurationRuleEvaluator {
    public static List<PricingService.ConfigResult> evaluate(
        PricingContext context,
        List<Config_Rule__mdt> rules
    ) {
        List<PricingService.ConfigResult> results =
            new List<PricingService.ConfigResult>();
        if (rules == null) {
            return results;
        }

        for (Config_Rule__mdt rule : rules) {
            if (!PricingScope.scopeMatches(rule.Product__c, context.product)) {
                continue;
            }
            if (!configRuleFires(
                rule,
                context.commitmentCode,
                context.companionScopes
            )) {
                continue;
            }
            results.add(buildConfigResult(rule));
        }

        return results;
    }

    private static Boolean configRuleFires(
        Config_Rule__mdt rule,
        String commitmentCode,
        Set<String> companionScopes
    ) {
        String ruleKind = rule.Rule_Kind__c;
        if (String.isBlank(ruleKind)) {
            return false;
        }

        if (ruleKind.equalsIgnoreCase('Requires Commitment')) {
            return String.isBlank(rule.Applies_When_Commitment__c)
                || PricingScope.codeMatches(
                    rule.Applies_When_Commitment__c,
                    commitmentCode
                );
        }

        if (ruleKind.equalsIgnoreCase('Excludes Commitment')) {
            return String.isBlank(rule.Applies_When_Commitment__c)
                || PricingScope.codeMatches(
                    rule.Applies_When_Commitment__c,
                    commitmentCode
                );
        }

        if (String.isNotBlank(rule.Applies_When_Commitment__c)
            && !PricingScope.codeMatches(
                rule.Applies_When_Commitment__c,
                commitmentCode
            )) {
            return false;
        }

        if (ruleKind.equalsIgnoreCase('Requires Companion')) {
            return String.isBlank(rule.Companion_Product__c)
                || !PricingScope.companionPresent(
                    rule.Companion_Product__c,
                    companionScopes
                );
        }

        if (ruleKind.equalsIgnoreCase('Excludes Companion')) {
            return String.isNotBlank(rule.Companion_Product__c)
                && PricingScope.companionPresent(
                    rule.Companion_Product__c,
                    companionScopes
                );
        }

        return false;
    }

    private static PricingService.ConfigResult buildConfigResult(
        Config_Rule__mdt rule
    ) {
        PricingService.ConfigResult result = new PricingService.ConfigResult();
        result.developerName = rule.DeveloperName;
        result.label = rule.MasterLabel;
        result.ruleKind = rule.Rule_Kind__c;
        result.productScope = rule.Product__c;
        result.companionProduct = rule.Companion_Product__c;
        result.appliesWhenCommitment = rule.Applies_When_Commitment__c;
        result.severity = String.isBlank(rule.Severity__c)
            ? 'Block'
            : rule.Severity__c;
        result.message = String.isBlank(rule.Message__c)
            ? ('Configuration rule failed: ' + rule.DeveloperName)
            : rule.Message__c;
        result.warning = result.severity.equalsIgnoreCase('Warn');
        result.blocking = !result.warning;
        return result;
    }
}
