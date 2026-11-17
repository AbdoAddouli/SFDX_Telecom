/**
 * UC-LIF-03 step 1 façade.
 *
 * Flow/test entry points stay here; validation, intake and scheduling live in
 * focused helpers so each concern can be read and scaled independently.
 */
public with sharing class CancellationService {
    public class CancellationInput {
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Cancellation Reason' required=true) public String cancellationReason;
        @InvocableVariable(label='Cancellation Effective Date' required=true) public Date cancellationEffectiveDate;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Goodwill Waiver') public Boolean goodwillWaiver;
        @InvocableVariable(label='Goodwill Justification') public String goodwillJustification;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class CancellationResult {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Calculated Fee') public Decimal calculatedFee;
        @InvocableVariable(label='Cancellation Effective Date') public Date cancellationEffectiveDate;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Message') public String message;

        public CancellationResult() {
            success = false;
        }

        public void scheduled(Date effectiveDate) {
            success = true;
            status = 'In_Fulfilment';
            message = 'Cancellation scheduled; service continues until ' +
                effectiveDate.format() + '.';
        }
    }

    public class ApprovalInput {
        public Id requestId;
    }

    public class CancellationException extends Exception {}

    @InvocableMethod(label='Submit Cancellation' description='Validates the 30-day notice, creates the shared lifecycle request and schedules an approved cancellation.')
    public static List<CancellationResult> apply(List<CancellationInput> inputs) {
        return CancellationIntake.execute(inputs);
    }

    public static List<CancellationResult> applyApproved(List<ApprovalInput> inputs) {
        return CancellationApproval.execute(inputs);
    }
}
