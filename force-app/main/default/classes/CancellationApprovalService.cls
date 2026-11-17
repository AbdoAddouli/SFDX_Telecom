/**
 * Flow entry point for scheduling an already approved cancellation request.
 *
 * CancellationService owns the validation and transition logic; this thin
 * wrapper exists because Apex allows only one @InvocableMethod per class.
 */
public with sharing class CancellationApprovalService {
    public class ApprovalInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
    }

    @InvocableMethod(label='Schedule Approved Cancellation' description='Moves an approved cancellation line to PendingCancellation and marks the request In_Fulfilment.')
    public static List<CancellationService.CancellationResult> apply(
        List<ApprovalInput> inputs
    ) {
        List<CancellationService.ApprovalInput> delegates =
            new List<CancellationService.ApprovalInput>();
        if (inputs == null) {
            return CancellationService.applyApproved(delegates);
        }
        for (ApprovalInput input : inputs) {
            CancellationService.ApprovalInput delegate =
                new CancellationService.ApprovalInput();
            delegate.requestId = input == null ? null : input.requestId;
            delegates.add(delegate);
        }
        return CancellationService.applyApproved(delegates);
    }
}
