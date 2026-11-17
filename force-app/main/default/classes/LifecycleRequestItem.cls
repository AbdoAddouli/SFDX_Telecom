/**
 * One lifecycle intake row after bulk data loading.
 */
public with sharing class LifecycleRequestItem {
    public Integer index;
    public LifecycleRequestService.RequestInput input;
    public LifecycleRequestService.RequestOutput output;
    public Subscription__c subscription;
    public Account account;
    public Engagement__c engagement;
    public Id resolvedAccountId;
    public Case caseRecord;
    public Customer_Request__c request;
    public Decimal fee;
}
