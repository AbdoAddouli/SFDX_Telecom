/**
 * Applies approved renewal decisions atomically. Expiring engagements become
 * terminal; renewals create a new engagement instead of resurrecting the old.
 */
public with sharing class RenewalFulfilment {
    public static void apply(List<RenewalContext> contexts, Date today) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            RenewalWriter.apply(contexts, today);
            for (RenewalContext context : contexts) {
                String message = context.input.decision ==
                    RenewalPolicy.DECISION_LAPSE
                    ? 'Commitment lapsed. BQ4 monthly rollover now applies.'
                    : 'Renewal applied with a new active engagement.';
                context.result.completed(context.quotedAmount, message);
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            for (RenewalContext context : contexts) {
                context.result.failed(
                    'The renewal could not be applied. No term or engagement was changed.'
                );
            }
        }
    }
}
