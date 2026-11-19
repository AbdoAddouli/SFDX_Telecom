/**
 * UC-LIF-04 façade. Flow/test entry points stay here; validation, intake,
 * BSS state changes and writes live in focused helpers.
 */
public with sharing class SuspensionService {
    public class SuspensionInput {
        @InvocableVariable(label='Action' required=true) public String action;
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Goodwill Waiver') public Boolean goodwillWaiver;
        @InvocableVariable(label='Goodwill Justification') public String goodwillJustification;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class SuspensionResult {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Action') public String action;
        @InvocableVariable(label='Calculated Fee') public Decimal calculatedFee;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Message') public String message;

        public SuspensionResult() {
            success = false;
        }

        public void awaiting() {
            success = true;
            status = SuspensionPolicy.STATUS_AWAITING;
            message = action == SuspensionPolicy.ACTION_UNFREEZE
                ? 'Unfreeze submitted and awaiting manager approval.'
                : 'Suspension submitted and awaiting manager approval.';
        }

        public void completed(String targetStatus) {
            success = true;
            status = SuspensionPolicy.STATUS_COMPLETED;
            message = action == SuspensionPolicy.ACTION_UNFREEZE
                ? 'Line unfrozen; service is active again.'
                : 'Line suspended; service is paused. The contract term continues to run.';
        }

        public void failed(String reason) {
            success = false;
            status = SuspensionPolicy.STATUS_FAILED;
            message = reason;
        }
    }

    public class ApprovalInput {
        public Id requestId;
    }

    public class SuspensionException extends Exception {}

    @InvocableMethod(label='Apply Suspension' description='Creates a suspension or unfreeze request and applies the reversible line state change through BSS.')
    public static List<SuspensionResult> apply(List<SuspensionInput> inputs) {
        return SuspensionIntake.execute(inputs);
    }

    public static List<SuspensionResult> applyApproved(List<ApprovalInput> inputs) {
        return SuspensionApproval.execute(inputs);
    }
}
