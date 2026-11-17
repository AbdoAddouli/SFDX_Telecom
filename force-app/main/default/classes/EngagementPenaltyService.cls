/**
 * Computes early-termination fees from inception snapshots and the
 * Engagement_Penalty__mdt matrix. No SOQL or DML is performed; custom metadata
 * is read once through getAll(), so the calculation is bulk-safe.
 */
public with sharing class EngagementPenaltyService {
    public class Result {
        public Decimal fee { get; set; }
        public Decimal rate { get; set; }
        public Integer monthsRemaining { get; set; }
        public String ruleName { get; set; }
        public String breakdown { get; set; }
        public Boolean expired { get; set; }
        public Boolean withinPenaltyFreeWindow { get; set; }
    }

    private static final String DEFAULT_RULE = 'Default_No_Penalty';

    /**
     * Calculates the fee and stamps the engagement with a reproducible audit
     * trail. Callers persist the engagement and write Result.fee to the
     * Customer_Request__c.Calculated_Fee__c field.
     */
    public static Result calculate(
        Engagement__c engagement,
        String segment,
        String productCategory,
        Date activityDate
    ) {
        if (activityDate == null) {
            activityDate = Date.today();
        }

        Result result = new Result();
        result.fee = 0;
        result.rate = 0;
        result.monthsRemaining = 0;
        result.ruleName = DEFAULT_RULE;
        result.expired = false;
        result.withinPenaltyFreeWindow = false;

        Date startDate = engagement.Start_Date__c;
        Date endDate = engagement.End_Date__c;
        Integer durationMonths = engagement.Duration_Months__c == null
            ? 0
            : engagement.Duration_Months__c.intValue();
        Decimal monthlyAmount = engagement.Monthly_Amount__c == null
            ? 0
            : engagement.Monthly_Amount__c;

        if (endDate != null && activityDate >= endDate) {
            result.expired = true;
            result.breakdown =
                'Commitment expired on ' +
                endDate.format() +
                '. No early-termination fee applies.';
            stampEngagement(engagement, result, activityDate);
            return result;
        }

        ActivationPenaltyPolicy.Snapshot snapshot = ActivationPenaltyPolicy.resolve(
            segment,
            productCategory,
            durationMonths
        );
        Engagement_Penalty__mdt rule = String.isBlank(snapshot.ruleName)
            ? null
            : Engagement_Penalty__mdt.getAll().get(snapshot.ruleName);

        if (rule == null) {
            result.breakdown =
                'No matching penalty matrix row for ' +
                blankToNone(segment) +
                '/' +
                blankToNone(productCategory) +
                '/' +
                durationMonths +
                ' months. Default no-penalty rule applied.';
            stampEngagement(engagement, result, activityDate);
            return result;
        }

        result.ruleName = snapshot.ruleName;
        result.rate = snapshot.rate == null ? 0 : snapshot.rate;

        Integer elapsedDays = startDate == null
            ? 0
            : startDate.daysBetween(activityDate);
        Integer elapsedMonths = startDate == null
            ? 0
            : startDate.monthsBetween(activityDate);
        result.monthsRemaining = endDate == null
            ? (durationMonths > elapsedMonths ? durationMonths - elapsedMonths : 0)
            : activityDate.monthsBetween(endDate);

        Decimal dayWindow = rule.Penalty_Applicable_After_Days__c;
        Decimal monthWindow = rule.Penalty_Applicable_After_Months__c == null
            ? 0
            : rule.Penalty_Applicable_After_Months__c;
        result.withinPenaltyFreeWindow = dayWindow != null && dayWindow > 0
            ? elapsedDays <= dayWindow.intValue()
            : elapsedMonths <= monthWindow.intValue();

        if (result.withinPenaltyFreeWindow || result.monthsRemaining <= 0) {
            result.breakdown =
                'Penalty rule ' +
                result.ruleName +
                ' applied. Within the penalty-free window or no months remain; fee is 0.';
            stampEngagement(engagement, result, activityDate);
            return result;
        }

        Decimal rawFee = result.monthsRemaining * monthlyAmount * result.rate / 100;
        result.fee = rawFee;

        Decimal cap = rule.Max_Penalty_Cap__c;
        if (cap != null && result.fee > cap) {
            result.fee = cap;
        }
        Decimal minimum = rule.Min_Penalty__c;
        if (minimum != null && result.fee > 0 && result.fee < minimum) {
            result.fee = minimum;
        }
        result.fee = result.fee.setScale(2, System.RoundingMode.HALF_UP);

        result.breakdown =
            'Penalty rule ' +
            result.ruleName +
            ' applied: ' +
            result.monthsRemaining +
            ' month(s) remaining x ' +
            monthlyAmount +
            ' monthly amount x ' +
            result.rate +
            '% rate = ' +
            rawFee.setScale(2, System.RoundingMode.HALF_UP) +
            (cap != null && rawFee > cap ? ' capped at ' + cap : '') +
            '. Final fee ' +
            result.fee +
            '. Snapshots retained on the engagement.';

        stampEngagement(engagement, result, activityDate);
        return result;
    }

    private static void stampEngagement(
        Engagement__c engagement,
        Result result,
        Date activityDate
    ) {
        engagement.Penalty_Rule__c = result.ruleName;
        engagement.Penalty_Calculated_On__c = Datetime.newInstance(
            activityDate,
            Time.newInstance(0, 0, 0, 0)
        );
        engagement.Penalty_Breakdown__c = result.breakdown.left(1000);
        engagement.Early_Termination_Fee__c = result.fee;
    }

    private static String blankToNone(String value) {
        return String.isBlank(value) ? 'none' : value;
    }
}
