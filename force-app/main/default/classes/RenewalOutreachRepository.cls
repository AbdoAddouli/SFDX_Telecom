/**
 * Bulk query boundary for renewal outreach idempotency.
 */
public with sharing class RenewalOutreachRepository {
    public static Set<String> existingStages(Set<Id> engagementIds) {
        Set<String> keys = new Set<String>();
        if (engagementIds == null || engagementIds.isEmpty()) {
            return keys;
        }
        for (Task task : [
            SELECT Id, WhatId, Subject
            FROM Task
            WHERE WhatId IN :engagementIds AND Subject LIKE 'Renewal T-%'
        ]) {
            for (String stage : RenewalOutreachPolicy.STAGES) {
                if (
                    task.Subject != null &&
                    task.Subject.startsWith(
                        RenewalOutreachPolicy.subjectPrefix(stage)
                    )
                ) {
                    keys.add(RenewalOutreachPolicy.key(task.WhatId, stage));
                }
            }
        }
        return keys;
    }
}
