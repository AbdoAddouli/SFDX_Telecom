/**
 * Single bulk write path for plan-change amendments. A scoped change keeps the
 * engagement and contract, supersedes the old line and activates one new line.
 */
public with sharing class PlanChangeAmender {
    public class Amendment {
        public Integer resultIndex;
        public Customer_Request__c request;
        public Subscription__c source;
        public Engagement__c engagement;
        public Product2 product;
        public Decimal monthlyAmount;
        public String summary;
        public PlanChangeService.PlanChangeResult result;
    }

    public static void apply(List<Amendment> amendments, Date today) {
        if (amendments == null || amendments.isEmpty()) {
            return;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            List<Subscription__c> sources = new List<Subscription__c>();
            List<Subscription__c> replacements = new List<Subscription__c>();
            for (Amendment amendment : amendments) {
                amendment.source.Status__c = SubscriptionStateMachine.SUPERSEDED;
                amendment.source.Termination_Date__c = today;
                sources.add(amendment.source);
                replacements.add(buildReplacement(amendment));
            }
            Database.update(sources, true);
            Database.insert(replacements, true);

            List<Subscription__c> toActivate = new List<Subscription__c>();
            List<Engagement__c> engagements = new List<Engagement__c>();
            List<Customer_Request__c> requests = new List<Customer_Request__c>();
            for (Integer i = 0; i < amendments.size(); i++) {
                Amendment amendment = amendments[i];
                Subscription__c replacement = replacements[i];
                replacement.Status__c = SubscriptionStateMachine.ACTIVE;
                replacement.Activation_Date__c = today;
                toActivate.add(replacement);

                amendment.result.completed(
                    replacement.Id,
                    amendment.monthlyAmount,
                    'Plan changed. New line ' + replacement.Id + ' is active.'
                );
                amendment.request.Status__c = PlanChangePolicy.STATUS_COMPLETED;
                amendment.request.Completed_On__c = Datetime.now();
                amendment.request.Resolution_Summary__c =
                    (amendment.summary + replacement.Id).left(1000);
                requests.add(amendment.request);

                if (amendment.engagement != null) {
                    amendment.engagement.Monthly_Amount__c =
                        amendment.monthlyAmount;
                    engagements.add(amendment.engagement);
                }
            }
            Database.update(toActivate, true);
            Database.update(engagements, true);
            Database.update(requests, true);
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            for (Amendment amendment : amendments) {
                amendment.result.failed(
                    'The plan change could not be applied. No line was superseded.'
                );
            }
        }
    }

    private static Subscription__c buildReplacement(Amendment amendment) {
        Subscription__c source = amendment.source;
        return new Subscription__c(
            Account__c = source.Account__c,
            Asset__c = source.Asset__c,
            Contact__c = source.Contact__c,
            Contract__c = source.Contract__c,
            Engagement__c = source.Engagement__c,
            Root_Engagement__c = source.Root_Engagement__c,
            Parent_Subscription__c = source.Id,
            Service_Line_Type__c = source.Service_Line_Type__c,
            Product__c = amendment.product.Id,
            Monthly_Amount__c = amendment.monthlyAmount,
            Billing_Start_Date__c = source.Billing_Start_Date__c,
            Billing_End_Date__c = source.Billing_End_Date__c,
            Status__c = SubscriptionStateMachine.PENDING_ACTIVATION
        );
    }
}
