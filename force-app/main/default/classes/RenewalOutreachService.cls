/**
 * Creates stage-specific renewal outreach tasks once per engagement. DNC
 * contacts receive an email-only task and never a phone-outreach task.
 */
public with sharing class RenewalOutreachService {
    public static Integer apply(List<Engagement__c> engagements) {
        if (engagements == null || engagements.isEmpty()) {
            return 0;
        }
        Set<Id> engagementIds = new Set<Id>();
        for (Engagement__c engagement : engagements) {
            if (engagement != null && engagement.Id != null) {
                engagementIds.add(engagement.Id);
            }
        }
        Set<String> existing = RenewalOutreachRepository.existingStages(
            engagementIds
        );
        Date today = Date.today();
        Datetime now = Datetime.now();

        List<Task> tasks = new List<Task>();
        List<Engagement__c> updates = new List<Engagement__c>();
        for (Engagement__c engagement : engagements) {
            if (engagement == null || engagement.Id == null) {
                continue;
            }
            Subscription__c subscription = engagement.Subscription__r;
            if (subscription == null) {
                continue;
            }
            String stage = RenewalOutreachPolicy.stage(
                subscription.Next_Renewal_Date__c,
                today
            );
            if (stage == null || existing.contains(
                RenewalOutreachPolicy.key(engagement.Id, stage)
            )) {
                continue;
            }
            Boolean doNotCall = subscription.Contact__r != null &&
                subscription.Contact__r.Do_Not_Call__c == true;
            tasks.add(
                new Task(
                    OwnerId = engagement.OwnerId,
                    WhoId = subscription.Contact__c,
                    WhatId = engagement.Id,
                    Subject = RenewalOutreachPolicy.subject(stage, doNotCall),
                    Description = RenewalOutreachPolicy.description(
                        stage,
                        doNotCall
                    ),
                    ActivityDate = stage == RenewalOutreachPolicy.STAGE_T7
                        ? today.addDays(1)
                        : today.addDays(5),
                    Priority = stage == RenewalOutreachPolicy.STAGE_T7
                        ? 'High'
                        : 'Normal',
                    Status = 'Not Started'
                )
            );
            if (engagement.Renewal_Contacted__c != true) {
                updates.add(
                    new Engagement__c(
                        Id = engagement.Id,
                        Renewal_Contacted__c = true,
                        Renewal_Contacted_On__c = now
                    )
                );
            }
        }
        if (tasks.isEmpty()) {
            return 0;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            Database.insert(tasks, true);
            if (!updates.isEmpty()) {
                Database.update(updates, true);
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            return 0;
        }
        return tasks.size();
    }
}
