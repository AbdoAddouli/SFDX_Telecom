/**
 * One portability request loaded for BSS calls, validation and bulk writes.
 */
public with sharing class PortabilityContext {
    public Integer resultIndex;
    public PortabilityService.PortabilityResult result;
    public PortabilityService.PortabilityInput input;
    public PortabilityService.ConfirmationInput confirmation;
    public Customer_Request__c request;
    public Subscription__c subscription;
    public String direction;
    public String requestedMsisdn;
    public String previousMsisdn;
    public String targetMsisdn;
    public String requestReference;
    public String confirmationReference;
    public String correlationId;
    public BssProvisioningResponse response;
    public Boolean attempted = false;

    public Boolean requestIdCreated() {
        return result != null && result.requestId != null;
    }
}
