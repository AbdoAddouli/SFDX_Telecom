/**
 * One cancellation request loaded for fulfilment.
 */
public with sharing class CancellationFulfilmentItem {
    public Integer resultIndex;
    public Customer_Request__c request;
    public Subscription__c subscription;
    public BssProvisioningResponse response;
}
