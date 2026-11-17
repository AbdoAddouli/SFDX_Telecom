/**
 * Flow entry point for applying an already approved plan-change request.
 *
 * PlanChangeService owns the amendment logic; this thin wrapper exists because
 * Apex allows only one @InvocableMethod per class.
 */
public with sharing class PlanChangeApprovalService {
    public class ApprovalInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
    }

    @InvocableMethod(label='Apply Approved Plan Change' description='Applies a previously approved plan-change request, superseding the old subscription line.')
    public static List<PlanChangeService.PlanChangeResult> apply(List<ApprovalInput> inputs) {
        List<PlanChangeService.ApprovalInput> delegates =
            new List<PlanChangeService.ApprovalInput>();
        if (inputs == null) {
            return PlanChangeService.applyApproved(delegates);
        }
        for (ApprovalInput input : inputs) {
            PlanChangeService.ApprovalInput delegate =
                new PlanChangeService.ApprovalInput();
            delegate.requestId = input == null ? null : input.requestId;
            delegates.add(delegate);
        }
        return PlanChangeService.applyApproved(delegates);
    }
}
