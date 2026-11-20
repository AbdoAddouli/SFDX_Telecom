/**
 * Flow entry point for applying a donor port confirmation. PortabilityService
 * owns the logic; this wrapper exists because Apex allows only one
 * @InvocableMethod per class.
 */
public with sharing class PortabilityConfirmationService {
    public class ConfirmationInput {
        @InvocableVariable(label='Request Id' required=true) public Id requestId;
        @InvocableVariable(label='Confirmation Reference') public String confirmationReference;
        @InvocableVariable(label='Outcome' required=true) public String outcome;
        @InvocableVariable(label='Rejection Reason') public String rejectionReason;
        @InvocableVariable(label='Customer Comment') public String customerComment;
    }

    @InvocableMethod(
        label='Apply Port Confirmation'
        description='Applies a confirmed inbound/outbound port to the subscription, or records a donor rejection. Only confirmed ports change the MSISDN.'
    )
    public static List<PortabilityService.PortabilityResult> apply(
        List<ConfirmationInput> inputs
    ) {
        List<PortabilityService.ConfirmationInput> delegates =
            new List<PortabilityService.ConfirmationInput>();
        if (inputs != null) {
            for (ConfirmationInput input : inputs) {
                PortabilityService.ConfirmationInput delegate =
                    new PortabilityService.ConfirmationInput();
                delegate.requestId = input == null ? null : input.requestId;
                delegate.confirmationReference =
                    input == null ? null : input.confirmationReference;
                delegate.outcome = input == null ? null : input.outcome;
                delegate.rejectionReason =
                    input == null ? null : input.rejectionReason;
                delegate.customerComment =
                    input == null ? null : input.customerComment;
                delegates.add(delegate);
            }
        }
        return PortabilityService.applyConfirmation(delegates);
    }
}
