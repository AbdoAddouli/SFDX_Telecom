/**
 * Resolves the penalty rate snapshot at activation time. Custom metadata rows
 * are read once per transaction; no SOQL or DML runs per engagement.
 */
public class ActivationPenaltyPolicy {
    public class Snapshot {
        public Decimal rate { get; set; }
        public String ruleName { get; set; }
    }

    public static Snapshot resolve(
        String segment,
        String productCategory,
        Integer durationMonths
    ) {
        Snapshot selected = new Snapshot();
        Integer bestScore = -1;

        for (Engagement_Penalty__mdt rule : Engagement_Penalty__mdt.getAll()
            .values()) {
            if (rule.Is_Active__c != true) {
                continue;
            }
            if (
                String.isNotBlank(rule.Customer_Segment__c) &&
                rule.Customer_Segment__c != segment
            ) {
                continue;
            }
            if (
                String.isNotBlank(rule.Product_Category__c) &&
                rule.Product_Category__c != 'Any' &&
                rule.Product_Category__c != productCategory
            ) {
                continue;
            }
            if (
                rule.Commitment_Months__c != null &&
                rule.Commitment_Months__c != durationMonths
            ) {
                continue;
            }

            Integer priority = rule.Priority__c == null
                ? 0
                : rule.Priority__c.intValue();
            Integer specificity = 0;
            if (
                String.isNotBlank(rule.Customer_Segment__c) &&
                rule.Customer_Segment__c == segment
            ) {
                specificity += 4;
            }
            if (
                String.isNotBlank(rule.Product_Category__c) &&
                rule.Product_Category__c == productCategory
            ) {
                specificity += 2;
            }
            if (
                rule.Commitment_Months__c != null &&
                rule.Commitment_Months__c == durationMonths
            ) {
                specificity += 1;
            }

            Integer score = (priority * 100) + specificity;
            if (score > bestScore) {
                bestScore = score;
                selected.rate = rule.Penalty_Rate__c;
                selected.ruleName = rule.DeveloperName;
            }
        }

        return selected;
    }
}
