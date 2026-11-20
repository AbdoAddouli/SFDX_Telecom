/**
 * One renewal decision after bulk data loading, validation and quoting.
 */
public with sharing class RenewalContext {
    public Integer resultIndex;
    public RenewalService.RenewalResult result;
    public RenewalService.RenewalInput input;
    public Customer_Request__c request;
    public Subscription__c subscription;
    public Engagement__c engagement;
    public Account account;
    public Product2 product;
    public Contract contract;
    public String commitmentCode;
    public String rejectionReason;
    public Decimal quotedAmount;
    public PricingService.PriceBreakdown price;
}
