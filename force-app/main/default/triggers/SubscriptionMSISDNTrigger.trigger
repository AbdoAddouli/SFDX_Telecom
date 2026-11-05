trigger SubscriptionMSISDNTrigger on Subscription__c (
    before insert, before update) {
    SubscriptionMSISDNDuplicateHandler.checkDuplicates(Trigger.new);
}
