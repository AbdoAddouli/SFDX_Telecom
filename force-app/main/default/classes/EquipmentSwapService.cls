/**
 * UC-LIF-05 façade. Intake creates the shared request/Case pair, then an
 * approved swap is applied atomically through the BSS gateway boundary.
 */
public with sharing class EquipmentSwapService {
    public class EquipmentSwapInput {
        @InvocableVariable(label='Account Id' required=true) public Id accountId;
        @InvocableVariable(label='Contact Id' required=true) public Id contactId;
        @InvocableVariable(label='Subscription Id' required=true) public Id subscriptionId;
        @InvocableVariable(label='New Device Product Id' required=true) public Id newProductId;
        @InvocableVariable(label='Serial Number' required=true) public String serialNumber;
        @InvocableVariable(label='Colour') public String colour;
        @InvocableVariable(label='Image URL') public String imageUrl;
        @InvocableVariable(label='Channel' required=true) public String channel;
        @InvocableVariable(label='Customer Comment') public String customerComment;
        @InvocableVariable(label='Goodwill Waiver') public Boolean goodwillWaiver;
        @InvocableVariable(label='Goodwill Justification') public String goodwillJustification;
        @InvocableVariable(label='Priority') public String priority;
    }

    public class ApprovalInput {
        public Id requestId;
    }

    public class EquipmentSwapResult {
        @InvocableVariable(label='Success') public Boolean success = false;
        @InvocableVariable(label='Request Id') public Id requestId;
        @InvocableVariable(label='Case Id') public Id caseId;
        @InvocableVariable(label='Subscription Id') public Id subscriptionId;
        @InvocableVariable(label='Old Asset Id') public Id oldAssetId;
        @InvocableVariable(label='New Asset Id') public Id newAssetId;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Calculated Fee') public Decimal calculatedFee;
        @InvocableVariable(label='Message') public String message;

        public void submitted(Customer_Request__c request, String status, String message) {
            this.success = true;
            this.requestId = request != null ? request.Id : null;
            this.caseId = request != null ? request.Case__c : null;
            this.subscriptionId = request != null ? request.Subscription__c : null;
            this.status = status;
            this.message = message;
        }

        public void completed(EquipmentSwapContext context) {
            this.success = true;
            this.requestId = context.request.Id;
            this.caseId = context.request.Case__c;
            this.subscriptionId = context.subscription.Id;
            this.oldAssetId = context.oldAsset.Id;
            this.newAssetId = context.newAsset != null ? context.newAsset.Id : null;
            this.status = EquipmentSwapPolicy.STATUS_COMPLETED;
            this.calculatedFee = EquipmentSwapPolicy.FEE;
            this.message = 'Device swapped; service, contract and commitment are unchanged.';
        }

        public void failed(String message) {
            this.success = false;
            this.status = EquipmentSwapPolicy.STATUS_REJECTED;
            this.message = message;
        }

        public void alreadyApplied(EquipmentSwapContext context) {
            this.success = true;
            this.requestId = context.request.Id;
            this.caseId = context.request.Case__c;
            this.subscriptionId = context.subscription.Id;
            this.oldAssetId = context.oldAsset != null ? context.oldAsset.Id : context.request.Old_Asset__c;
            this.newAssetId = context.request.New_Asset__c;
            this.status = EquipmentSwapPolicy.STATUS_COMPLETED;
            this.calculatedFee = EquipmentSwapPolicy.FEE;
            this.message = 'Swap already completed.';
        }
    }

    @InvocableMethod(
        label='Request Equipment Swap'
        description='Validates and submits a device swap without changing the subscription service, contract or commitment.'
    )
    public static List<EquipmentSwapResult> requestSwaps(List<EquipmentSwapInput> inputs) {
        return EquipmentSwapIntake.execute(inputs);
    }

    public static List<EquipmentSwapResult> applyApproved(List<ApprovalInput> inputs) {
        return EquipmentSwapApproval.execute(inputs);
    }
}
