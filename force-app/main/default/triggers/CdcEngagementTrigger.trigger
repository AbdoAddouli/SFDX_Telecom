trigger CdcEngagementTrigger on Engagement__ChangeEvent (after insert) {
    CdcReportingService.handle(Trigger.new, 'Engagement__c');
}
