/**
 * UC-LIF-07 façade. Flow/test entry points stay here; validation, intake,
 * BSS calls and writes live in focused helpers.
 *
 * Portability is two-phase: requestPorts submits the port to BSS and creates
 * the shared request/Case pair without changing the MSISDN; applyConfirmation
 * is a separate invocation that updates the number only after confirmation.
 */
public with sharing class PortabilityService {
    public class PortabilityInput {
        @InvocableVariable(label='Direction' required=true) public String direction;
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='Requested MSISDN' required=true) public String requestedMsisdn;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Goodwill Waiver') public Boolean goodwillWaiver;
        @InvocableVariable(label='Goodwill Justification') public String goodwillJustification;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class ConfirmationInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
        @InvocableVariable(label='Confirmation Reference') public String confirmationReference;
        @InvocableVariable(label='Outcome' required=true) public String outcome;
        @InvocableVariable(label='Rejection Reason') public String rejectionReason;
        @InvocableVariable(label='Customer Comment') public String customerComment;
    }

    public class PortabilityResult {
        @InvocableVariable(label='Success') public Boolean success = false;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Direction') public String direction;
        @InvocableVariable(label='Requested MSISDN') public String requestedMsisdn;
        @InvocableVariable(label='Previous MSISDN') public String previousMsisdn;
        @InvocableVariable(label='Applied MSISDN') public String appliedMsisdn;
        @InvocableVariable(label='Port Request Reference') public String portRequestReference;
        @InvocableVariable(label='Port Confirmation Reference') public String portConfirmationReference;
        @InvocableVariable(label='Calculated Fee') public Decimal calculatedFee;
        @InvocableVariable(label='Message') public String message;

        public void submitted(String requestStatus, String requestReference) {
            this.success = true;
            this.status = requestStatus;
            this.portRequestReference = requestReference;
            if (requestStatus == PortabilityPolicy.STATUS_AWAITING) {
                this.message =
                    'Port request submitted to BSS and awaiting approval. ' +
                    'MSISDN is unchanged until donor confirmation.';
            } else {
                this.message =
                    'Port request submitted to BSS and approved. ' +
                    'MSISDN is unchanged until donor confirmation.';
            }
        }

        public void applied(String msisdn) {
            this.success = true;
            this.status = PortabilityPolicy.STATUS_COMPLETED;
            this.appliedMsisdn = msisdn;
            this.message = String.isBlank(msisdn)
                ? 'Port confirmed. The number has been released from the line.'
                : 'Port confirmed. MSISDN updated to ' + msisdn + '.';
        }

        public void alreadyApplied(String msisdn) {
            this.success = true;
            this.status = PortabilityPolicy.STATUS_COMPLETED;
            this.appliedMsisdn = msisdn;
            this.message =
                'Port was already applied to this request. No changes were made.';
        }

        public void rejected(String reason) {
            this.success = true;
            this.status = PortabilityPolicy.STATUS_REJECTED;
            this.message = String.isBlank(reason)
                ? 'Donor rejected the port request. MSISDN is unchanged.'
                : 'Donor rejected the port request: ' + reason +
                    ' MSISDN is unchanged.';
        }

        public void alreadyRejected() {
            this.success = true;
            this.status = PortabilityPolicy.STATUS_REJECTED;
            this.message =
                'This port request was already rejected. No changes were made.';
        }

        public void failed(String reason) {
            this.success = false;
            this.status = PortabilityPolicy.STATUS_FAILED;
            this.message = reason;
        }
    }

    @InvocableMethod(
        label='Request Number Portability'
        description='Submits an inbound or outbound port request to BSS and creates the shared lifecycle request. The MSISDN is not changed yet.'
    )
    public static List<PortabilityResult> requestPorts(
        List<PortabilityInput> inputs
    ) {
        return PortabilityIntake.execute(inputs);
    }

    public static List<PortabilityResult> applyConfirmation(
        List<ConfirmationInput> inputs
    ) {
        return PortabilityConfirmation.execute(inputs);
    }
}
