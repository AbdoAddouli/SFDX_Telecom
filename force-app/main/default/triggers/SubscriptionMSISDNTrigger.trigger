/**
 * Single Subscription__c trigger. The legacy MSISDN name is retained so the
 * existing trigger does not need a destructive rename; lifecycle validation,
 * MSISDN uniqueness and the no-hard-delete guard all run from here.
 */
trigger SubscriptionMSISDNTrigger on Subscription__c (
    before insert, before update, before delete) {
    SubscriptionTriggerHandler.handle(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );

    if (Trigger.isInsert || Trigger.isUpdate) {
        SubscriptionMSISDNDuplicateHandler.checkDuplicates(Trigger.new);
    }
}
