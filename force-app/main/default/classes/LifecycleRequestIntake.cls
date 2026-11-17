/**
 * Shared lifecycle intake orchestration: load once, validate, prepare, write.
 */
public with sharing class LifecycleRequestIntake {
    public static List<LifecycleRequestService.RequestOutput> execute(
        List<LifecycleRequestService.RequestInput> inputs
    ) {
        List<LifecycleRequestService.RequestOutput> outputs =
            new List<LifecycleRequestService.RequestOutput>();
        if (inputs == null || inputs.isEmpty()) {
            return outputs;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            outputs.add(new LifecycleRequestService.RequestOutput());
        }

        LifecycleRequestRepository.Data data =
            LifecycleRequestRepository.load(inputs);
        List<LifecycleRequestItem> items = new List<LifecycleRequestItem>();
        List<String> errors = new List<String>();
        for (Integer i = 0; i < inputs.size(); i++) {
            String error = LifecycleRequestValidator.validate(
                inputs[i], data.subscriptions
            );
            if (error != null) {
                errors.add(error);
                continue;
            }
            LifecycleRequestItem item = new LifecycleRequestItem();
            item.index = i;
            item.input = inputs[i];
            item.output = outputs[i];
            item.subscription = inputs[i].subscriptionId == null
                ? null
                : data.subscriptions.get(inputs[i].subscriptionId);
            item.resolvedAccountId = item.subscription != null
                && item.subscription.Account__c != null
                ? item.subscription.Account__c
                : inputs[i].accountId;
            item.account = data.accounts.get(item.resolvedAccountId);
            if (item.account == null) {
                errors.add('Account could not be found.');
                continue;
            }
            if (item.subscription != null && item.subscription.Engagement__c != null) {
                item.engagement =
                    data.engagements.get(item.subscription.Engagement__c);
            }
            items.add(item);
        }
        if (!errors.isEmpty()) {
            String message = String.join(errors, ' ');
            for (LifecycleRequestService.RequestOutput output : outputs) {
                output.failed(message);
            }
            return outputs;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            Decimal threshold = LifecycleRequestPolicy.approvalThreshold();
            Date today = Date.today();
            for (LifecycleRequestItem item : items) {
                LifecycleRequestBuilder.prepare(item, threshold, today);
            }
            LifecycleRequestWriter.write(items);
            for (LifecycleRequestItem item : items) {
                item.output.requestId = item.request.Id;
                item.output.caseId =
                    item.caseRecord == null ? null : item.caseRecord.Id;
                item.output.fee = item.fee;
                item.output.submitted(item.request.Status__c);
            }
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            for (LifecycleRequestService.RequestOutput output : outputs) {
                output.failed(
                    'The request could not be created. Review the entries and retry.'
                );
            }
        }
        return outputs;
    }
}
