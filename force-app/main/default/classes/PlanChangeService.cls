/**
 * UC-LIF-02 façade.
 *
 * Flow/test entry points stay here; validation, quoting, repository access and
 * amendment writes live in focused helpers so each concern stays readable.
 */
public with sharing class PlanChangeService {
    public class PlanChangeInput {
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='Target Product Id' required=true) public Id targetProductId;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Commitment Code') public String commitmentCode;
        @InvocableVariable(label='Postal Code') public String postalCode;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class PlanChangeResult {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Monthly Amount') public Decimal monthlyAmount;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Message') public String message;

        public PlanChangeResult() {
            success = false;
        }

        public void rejected(String reason) {
            status = 'Rejected';
            message = reason;
        }

        public void awaitingApproval(Decimal amount) {
            status = 'Awaiting_Approval';
            monthlyAmount = amount;
            message = 'Plan change quoted and awaiting approval.';
        }

        public void completed(Id lineId, Decimal amount, String messageText) {
            success = true;
            status = 'Completed';
            subscriptionId = lineId;
            monthlyAmount = amount;
            message = messageText;
        }

        public void failed(String messageText) {
            success = false;
            status = 'Failed';
            message = messageText;
        }

        public void alreadyApplied() {
            success = true;
            status = 'Completed';
            message = 'Plan change was already applied.';
        }
    }

    public class ApprovalInput {
        public Id requestId;
    }

    public class PlanChangeException extends Exception {}

    @InvocableMethod(label='Apply Plan Change' description='Quotes and applies a scoped plan change through shared intake, preserving the existing engagement and term.')
    public static List<PlanChangeResult> apply(List<PlanChangeInput> inputs) {
        return PlanChangeIntake.execute(inputs);
    }

    public static List<PlanChangeResult> applyApproved(List<ApprovalInput> inputs) {
        return PlanChangeApproval.execute(inputs);
    }
}
