trigger CdcCustomerRequestTrigger on Customer_Request__ChangeEvent (after insert) {
    CdcReportingService.handle(Trigger.new, 'Customer_Request__c');
}
