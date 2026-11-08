/**
 * @description Unit tests for ConfigurationRuleEvaluator. These tests use
 * in-memory Config_Rule__mdt records and a single in-memory product, so they
 * exercise every rule kind without SOQL, DML, or seed-data changes.
 */
@IsTest
private class ConfigurationRuleEvaluatorTest {
    private static Product2 product() {
        return new Product2(
            Name = 'Unit Test Device',
            Family = 'TELCO_DEVICE',
            IsActive = true,
            ATS_Product_Code__c = 'UNIT_DEVICE'
        );
    }

    private static PricingContext context(String commitmentCode, Set<String> companions) {
        PricingContext context = new PricingContext(
            null,
            commitmentCode,
            null,
            Date.today(),
            companions
        );
        context.product = product();
        return context;
    }

    private static Config_Rule__mdt rule(
        String developerName,
        String ruleKind,
        String productScope,
        String companionProduct,
        String appliesWhenCommitment,
        String severity,
        String message
    ) {
        Config_Rule__mdt rule = new Config_Rule__mdt();
        rule.DeveloperName = developerName;
        rule.Rule_Kind__c = ruleKind;
        rule.Product__c = productScope;
        rule.Companion_Product__c = companionProduct;
        rule.Applies_When_Commitment__c = appliesWhenCommitment;
        rule.Severity__c = severity;
        rule.Message__c = message;
        return rule;
    }

    @IsTest
    static void returnsEmptyForNullRules() {
        Test.startTest();
        List<PricingService.ConfigResult> results =
            ConfigurationRuleEvaluator.evaluate(context('COMMIT12', null), null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void evaluatesCommitmentAndCompanionRulesWhenPresent() {
        List<Config_Rule__mdt> rules = new List<Config_Rule__mdt>{
            rule('Blank_Kind', null, 'TELCO_DEVICE', null, null, 'Block', 'blank kind'),
            rule('Global_Rule', 'Requires Commitment', null, null, null, 'Block', 'global'),
            rule('Requires_Commitment_Blank', 'Requires Commitment', 'TELCO_DEVICE', null, null, 'Warn', null),
            rule('Requires_Commitment_Match', 'Requires Commitment', 'TELCO_DEVICE', null, 'COMMIT12', 'Block', 'match'),
            rule('Requires_Commitment_Other', 'Requires Commitment', 'TELCO_DEVICE', null, 'COMMIT24', 'Block', 'other'),
            rule('Excludes_Commitment_Blank', 'Excludes Commitment', 'TELCO_DEVICE', null, null, 'Block', 'exclude blank'),
            rule('Excludes_Commitment_Match', 'Excludes Commitment', 'TELCO_DEVICE', null, 'COMMIT12', 'Block', 'exclude match'),
            rule('Excludes_Commitment_Other', 'Excludes Commitment', 'TELCO_DEVICE', null, 'COMMIT24', 'Block', 'exclude other'),
            rule('Requires_Companion_Blank', 'Requires Companion', 'TELCO_DEVICE', null, null, 'Block', 'companion blank'),
            rule('Requires_Companion_Present', 'Requires Companion', 'TELCO_DEVICE', 'TELCO_MOBILE', null, 'Block', 'companion present'),
            rule('Excludes_Companion_Blank', 'Excludes Companion', 'TELCO_DEVICE', null, null, 'Block', 'exclude companion blank'),
            rule('Excludes_Companion_Present', 'Excludes Companion', 'TELCO_DEVICE', 'TELCO_MOBILE', null, 'Block', 'exclude companion present'),
            rule('Unknown_Kind', 'Something Else', 'TELCO_DEVICE', null, null, 'Block', 'unknown'),
            rule('Wrong_Scope', 'Requires Commitment', 'TELCO_FIBER', null, null, 'Block', 'wrong scope'),
            rule('Gated_Out', 'Requires Companion', 'TELCO_DEVICE', 'TELCO_MOBILE', 'COMMIT24', 'Block', 'gate'),
            rule('Blank_Severity', 'Requires Commitment', 'TELCO_DEVICE', null, null, null, 'blank severity')
        };

        Test.startTest();
        List<PricingService.ConfigResult> results =
            ConfigurationRuleEvaluator.evaluate(
                context('COMMIT12', new Set<String>{ 'TELCO_MOBILE' }),
                rules
            );
        Test.stopTest();

        System.assertEquals(8, results.size());

        PricingService.ConfigResult warning = findResult(results, 'Requires_Commitment_Blank');
        System.assert(warning.warning);
        System.assert(!warning.blocking);
        System.assert(warning.message.contains('Requires_Commitment_Blank'));

        PricingService.ConfigResult blankSeverity = findResult(results, 'Blank_Severity');
        System.assert(blankSeverity.blocking);
        System.assert(!blankSeverity.warning);
        System.assertEquals('Block', blankSeverity.severity);

        System.assertNotEquals(null, findResult(results, 'Global_Rule'));
        System.assertNotEquals(null, findResult(results, 'Requires_Commitment_Match'));
        System.assertNotEquals(null, findResult(results, 'Excludes_Commitment_Blank'));
        System.assertNotEquals(null, findResult(results, 'Excludes_Commitment_Match'));
        System.assertNotEquals(null, findResult(results, 'Requires_Companion_Blank'));
        System.assertNotEquals(null, findResult(results, 'Excludes_Companion_Present'));
    }

    @IsTest
    static void evaluatesMissingCompanionBranches() {
        List<Config_Rule__mdt> rules = new List<Config_Rule__mdt>{
            rule('Requires_Companion_Missing', 'Requires Companion', 'TELCO_DEVICE', 'TELCO_MOBILE', null, 'Block', 'missing'),
            rule('Excludes_Companion_Missing', 'Excludes Companion', 'TELCO_DEVICE', 'TELCO_MOBILE', null, 'Block', 'missing')
        };

        Test.startTest();
        List<PricingService.ConfigResult> results =
            ConfigurationRuleEvaluator.evaluate(context('COMMIT12', new Set<String>()), rules);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Requires_Companion_Missing', results[0].developerName);
        System.assertEquals('Requires Companion', results[0].ruleKind);
        System.assertEquals('TELCO_DEVICE', results[0].productScope);
        System.assertEquals('TELCO_MOBILE', results[0].companionProduct);
    }

    private static PricingService.ConfigResult findResult(
        List<PricingService.ConfigResult> results,
        String developerName
    ) {
        for (PricingService.ConfigResult result : results) {
            if (developerName.equals(result.developerName)) {
                return result;
            }
        }
        return null;
    }
}
