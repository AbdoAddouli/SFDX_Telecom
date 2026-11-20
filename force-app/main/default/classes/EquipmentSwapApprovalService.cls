/**
 * Flow entry point for applying an approved equipment-swap request. Apex allows
 * only one @InvocableMethod per class, so this wrapper delegates to the service.
 */
public with sharing class EquipmentSwapApprovalService {
    public class ApprovalInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
    }

    @InvocableMethod(
        label='Apply Approved Equipment Swap'
        description='Applies a manager-approved equipment swap and retires the old asset.'
    )
    public static List<EquipmentSwapService.EquipmentSwapResult> apply(
        List<ApprovalInput> inputs
    ) {
        List<EquipmentSwapService.ApprovalInput> delegates =
            new List<EquipmentSwapService.ApprovalInput>();
        if (inputs != null) {
            for (ApprovalInput input : inputs) {
                EquipmentSwapService.ApprovalInput delegate =
                    new EquipmentSwapService.ApprovalInput();
                delegate.requestId = input != null ? input.requestId : null;
                delegates.add(delegate);
            }
        }
        return EquipmentSwapService.applyApproved(delegates);
    }
}
