/**
 * Shared lifecycle intake façade.
 *
 * Flow/test entry stays here; validation, loading, preparation and writes live
 * in focused helpers so each concern can be read and scaled independently.
 */
public with sharing class LifecycleRequestService {
    public class RequestInput {
        @InvocableVariable(label='Request Type' required=true) public String requestType;
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Requested Product') public String requestedProduct;
        @InvocableVariable(label='Cancellation Reason') public String cancellationReason;
        @InvocableVariable(label='Cancellation Effective Date') public Date cancellationEffectiveDate;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Goodwill Waiver') public Boolean goodwillWaiver;
        @InvocableVariable(label='Goodwill Justification') public String goodwillJustification;
        @InvocableVariable(label='Priority') public String priority;
        @InvocableVariable(label='Related Quote Id') public Id relatedQuoteId;
        @InvocableVariable(label='Related Order Id') public Id relatedOrderId;
    }

    public class RequestOutput {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Calculated Fee') public Decimal fee;
        @InvocableVariable(label='Message') public String message;

        public RequestOutput() {
            success = false;
        }

        public void submitted(String requestStatus) {
            success = true;
            status = requestStatus;
            message = requestStatus == LifecycleRequestPolicy.STATUS_AWAITING
                ? 'Request submitted and awaiting approval.'
                : 'Request submitted and approved.';
        }

        public void failed(String messageText) {
            success = false;
            message = messageText;
        }
    }

    @InvocableMethod(label='Create Lifecycle Request' description='Creates a customer request with Case traceability, server-computed fees and approval routing.')
    public static List<RequestOutput> createRequests(List<RequestInput> inputs) {
        return LifecycleRequestIntake.execute(inputs);
    }
}
