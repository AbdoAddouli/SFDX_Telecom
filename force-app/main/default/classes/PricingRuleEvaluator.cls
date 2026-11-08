/**
 * @description Applies Pricing_Rule__mdt records to one pricing context.
 * Pure calculation: no SOQL and no DML.
 */
public class PricingRuleEvaluator {
    public class Result {
        public Decimal finalPrice;
        public Decimal adjustmentTotal;
        public List<PricingService.AppliedRule> appliedRules;

        public Result() {
            this.finalPrice = 0;
            this.adjustmentTotal = 0;
            this.appliedRules = new List<PricingService.AppliedRule>();
        }
    }

    public static Result apply(
        PricingContext context,
        List<Pricing_Rule__mdt> rules
    ) {
        Result result = new Result();
        Decimal listPrice = context.listPrice == null ? 0 : context.listPrice;
        Decimal runningPrice = listPrice;

        if (rules != null) {
            for (Pricing_Rule__mdt rule : rules) {
                if (!PricingScope.isEffective(rule, context.effectiveDate)) {
                    continue;
                }
                if (!PricingScope.scopeMatches(rule.Product__c, context.product)) {
                    continue;
                }
                if (!PricingScope.codeMatches(
                    rule.Commitment_Code__c,
                    context.commitmentCode
                )) {
                    continue;
                }
                if (!PricingScope.codeMatches(rule.Segment__c, context.segment)) {
                    continue;
                }
                if (!PricingScope.companionRequirementMet(
                    rule.Requires_Product__c,
                    context.companionScopes
                )) {
                    continue;
                }

                Decimal adjustmentAmount = calculateAdjustment(
                    runningPrice,
                    rule.Adjustment_Type__c,
                    rule.Adjustment_Value__c,
                    rule.DeveloperName
                );

                runningPrice = (runningPrice - adjustmentAmount)
                    .setScale(2, RoundingMode.HALF_UP);
                if (runningPrice < 0) {
                    runningPrice = 0;
                }

                result.appliedRules.add(buildAppliedRule(rule, adjustmentAmount));
            }
        }

        result.finalPrice = runningPrice;
        result.adjustmentTotal = (listPrice - runningPrice)
            .setScale(2, RoundingMode.HALF_UP);
        return result;
    }

    private static PricingService.AppliedRule buildAppliedRule(
        Pricing_Rule__mdt rule,
        Decimal adjustmentAmount
    ) {
        PricingService.AppliedRule applied = new PricingService.AppliedRule();
        applied.developerName = rule.DeveloperName;
        applied.label = rule.MasterLabel;
        applied.ruleType = rule.Rule_Type__c;
        applied.adjustmentType = rule.Adjustment_Type__c;
        applied.adjustmentValue = rule.Adjustment_Value__c;
        applied.amount = adjustmentAmount.setScale(2, RoundingMode.HALF_UP);
        applied.priority = rule.Priority__c;
        applied.targetScope = rule.Product__c;
        applied.requiresProduct = rule.Requires_Product__c;
        return applied;
    }

    private static Decimal calculateAdjustment(
        Decimal runningPrice,
        String adjustmentType,
        Decimal adjustmentValue,
        String ruleName
    ) {
        if (String.isBlank(adjustmentType)) {
            throw new PricingService.PricingException(
                'Adjustment type is missing on rule: ' + ruleName
            );
        }
        if (adjustmentValue == null) {
            throw new PricingService.PricingException(
                'Adjustment value is missing on rule: ' + ruleName
            );
        }

        if (adjustmentType.equalsIgnoreCase('Percent')) {
            return runningPrice * adjustmentValue / 100;
        }
        if (adjustmentType.equalsIgnoreCase('Amount')) {
            return adjustmentValue;
        }
        if (adjustmentType.equalsIgnoreCase('Fixed')) {
            return runningPrice - adjustmentValue;
        }
        throw new PricingService.PricingException(
            'Unsupported adjustment type "' + adjustmentType + '" on rule: ' + ruleName
        );
    }
}
