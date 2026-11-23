trigger CdcSubscriptionTrigger on Subscription__ChangeEvent (after insert) {
    CdcReportingService.handle(Trigger.new, 'Subscription__c');
}
