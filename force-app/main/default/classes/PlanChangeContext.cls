/**
 * One plan-change intake row after bulk data loading and eligibility checks.
 */
public with sharing class PlanChangeContext {
    public Integer resultIndex;
    public PlanChangeService.PlanChangeInput input;
    public Customer_Request__c request;
    public Subscription__c source;
    public Engagement__c engagement;
    public Account account;
    public Product2 product;
    public String commitmentCode;
    public String rejectionReason;
    public Decimal quotedAmount;
    public PricingService.PriceBreakdown price;
}
