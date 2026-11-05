/**
 * @description Prevents duplicate MSISDN values on Subscription__c with a
 * friendly, field-level message. The field already carries the platform
 * unique constraint (`unique=true`); this handler adds a consistent message
 * for duplicate values both within one DML batch and against existing rows.
 *
 * The spec references `Database.getDuplicateRecords`, which is not an Apex
 * method. The supported API is `Datacloud.FindDuplicates`; this handler uses a
 * selective SOQL query on the unique, indexed `MSISDN__c` field instead.
 */
public class SubscriptionMSISDNDuplicateHandler {
    private static final String MSG = 'A Subscription with this MSISDN already exists.';

    public static void checkDuplicates(List<Subscription__c> scope) {
        Map<String, Subscription__c> firstByKey = new Map<String, Subscription__c>();
        Set<String> values = new Set<String>();

        for (Subscription__c r : scope) {
            if (String.isBlank(r.MSISDN__c)) {
                continue;
            }
            String key = r.MSISDN__c.trim();
            values.add(key);
            if (firstByKey.containsKey(key)) {
                r.addError(Subscription__c.MSISDN__c, MSG);
            } else {
                firstByKey.put(key, r);
            }
        }

        if (values.isEmpty()) {
            return;
        }

        Map<String, List<Subscription__c>> byValue = new Map<String, List<Subscription__c>>();
        for (Subscription__c existing : [
            SELECT Id, MSISDN__c
            FROM Subscription__c
            WHERE MSISDN__c IN :values
        ]) {
            if (String.isBlank(existing.MSISDN__c)) {
                continue;
            }
            String key = existing.MSISDN__c.trim();
            if (!byValue.containsKey(key)) {
                byValue.put(key, new List<Subscription__c>());
            }
            byValue.get(key).add(existing);
        }

        for (Subscription__c r : scope) {
            if (String.isBlank(r.MSISDN__c)) {
                continue;
            }
            String key = r.MSISDN__c.trim();
            List<Subscription__c> matches = byValue.get(key);
            if (matches == null) {
                continue;
            }
            for (Subscription__c existing : matches) {
                if (existing.Id != r.Id) {
                    r.addError(Subscription__c.MSISDN__c, MSG);
                    break;
                }
            }
        }
    }
}
