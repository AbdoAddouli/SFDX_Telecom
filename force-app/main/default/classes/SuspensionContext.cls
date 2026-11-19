/**
 * One suspension request loaded for BSS state change and Salesforce writes.
 */
public with sharing class SuspensionContext {
    public Integer resultIndex;
    public SuspensionService.SuspensionResult result;
    public Customer_Request__c request;
    public Subscription__c subscription;
    public String action;
    public String targetStatus;
    public BssProvisioningResponse response;
}
