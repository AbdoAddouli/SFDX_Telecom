/**
 * UC-LIF-06 façade. Flow/test entry points stay here; validation, quoting,
 * repository access and renewal writes live in focused helpers.
 */
public with sharing class RenewalService {
    public class RenewalInput {
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='Renewal Decision' required=true) public String decision;
        @InvocableVariable(label='Target Product Id') public Id targetProductId;
        @InvocableVariable(label='Commitment Code') public String commitmentCode;
        @InvocableVariable(label='Postal Code') public String postalCode;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class RenewalResult {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Decision') public String decision;
        @InvocableVariable(label='Monthly Amount') public Decimal monthlyAmount;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Message') public String message;

        public RenewalResult() {
            success = false;
        }

        public void rejected(String reason) {
            status = RenewalPolicy.STATUS_REJECTED;
            message = reason;
        }

        public void awaiting(Decimal amount) {
            success = true;
            status = RenewalPolicy.STATUS_AWAITING;
            monthlyAmount = amount;
            message = 'Renewal quoted and awaiting manager approval.';
        }

        public void completed(Decimal amount, String text) {
            success = true;
            status = RenewalPolicy.STATUS_COMPLETED;
            monthlyAmount = amount;
            message = text;
        }

        public void failed(String text) {
            success = false;
            status = 'Failed';
            message = text;
        }
    }

    public class RenewalException extends Exception {}

    @InvocableMethod(label='Apply Renewal Decision' description='Applies a renewal decision using shared intake and server-authoritative pricing from the catalogue facade.')
    public static List<RenewalResult> apply(List<RenewalInput> inputs) {
        return RenewalIntake.execute(inputs);
    }
}
