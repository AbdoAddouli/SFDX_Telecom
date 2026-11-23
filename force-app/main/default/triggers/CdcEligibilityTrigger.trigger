trigger CdcEligibilityTrigger on Eligibility__ChangeEvent (after insert) {
    CdcReportingService.handle(Trigger.new, 'Eligibility__c');
}
