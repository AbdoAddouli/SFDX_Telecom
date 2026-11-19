/**
 * Flow entry point for applying an already approved suspension/unfreeze.
 * SuspensionService owns the logic; this wrapper exists because Apex allows
 * only one @InvocableMethod per class.
 */
public with sharing class SuspensionApprovalService {
    public class ApprovalInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
    }

    @InvocableMethod(label='Apply Approved Suspension' description='Applies a previously approved suspension or unfreeze request.')
    public static List<SuspensionService.SuspensionResult> apply(
        List<ApprovalInput> inputs
    ) {
        List<SuspensionService.ApprovalInput> delegates =
            new List<SuspensionService.ApprovalInput>();
        if (inputs == null) {
            return SuspensionService.applyApproved(delegates);
        }
        for (ApprovalInput input : inputs) {
            SuspensionService.ApprovalInput delegate =
                new SuspensionService.ApprovalInput();
            delegate.requestId = input == null ? null : input.requestId;
            delegates.add(delegate);
        }
        return SuspensionService.applyApproved(delegates);
    }
}
