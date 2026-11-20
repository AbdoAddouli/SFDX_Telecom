/**
 * UC-LIF-05 intake: validate the swap, create the shared request/Case pair,
 * stamp the device details, then fulfil approved swaps through the BSS gateway.
 */
public with sharing class EquipmentSwapIntake {
    public static List<EquipmentSwapService.EquipmentSwapResult> execute(
        List<EquipmentSwapService.EquipmentSwapInput> inputs
    ) {
        List<EquipmentSwapService.EquipmentSwapResult> results =
            new List<EquipmentSwapService.EquipmentSwapResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new EquipmentSwapService.EquipmentSwapResult());
        }

        Set<Id> subscriptionIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (EquipmentSwapService.EquipmentSwapInput input : inputs) {
            if (input != null) {
                if (input.subscriptionId != null) {
                    subscriptionIds.add(input.subscriptionId);
                }
                if (input.newProductId != null) {
                    productIds.add(input.newProductId);
                }
            }
        }

        Map<Id, Subscription__c> subscriptions =
            EquipmentSwapRepository.subscriptions(subscriptionIds);
        Set<Id> assetIds = new Set<Id>();
        Set<Id> orderItemIds = new Set<Id>();
        for (Subscription__c subscription : subscriptions.values()) {
            if (subscription.Asset__c != null) {
                assetIds.add(subscription.Asset__c);
            }
            if (subscription.Order_Product__c != null) {
                orderItemIds.add(subscription.Order_Product__c);
            }
        }

        Map<Id, Asset> assets = EquipmentSwapRepository.assets(assetIds);
        Map<Id, Customer_Request__c> inFlight =
            EquipmentSwapRepository.inFlightBySubscription(subscriptionIds);
        Map<Id, CatalogQueryService.ProductView> devices =
            EquipmentSwapRepository.devices();
        Map<Id, PricebookEntry> entries =
            EquipmentSwapRepository.pricebookEntries(productIds);
        Map<Id, OrderItem> orderItems =
            EquipmentSwapRepository.sourceOrderItems(orderItemIds);

        List<EquipmentSwapContext> contexts = new List<EquipmentSwapContext>();
        List<LifecycleRequestService.RequestInput> intakeInputs =
            new List<LifecycleRequestService.RequestInput>();
        Map<Integer, Integer> contextIndexByIntake = new Map<Integer, Integer>();

        for (Integer i = 0; i < inputs.size(); i++) {
            EquipmentSwapService.EquipmentSwapInput input = inputs[i];
            String error = EquipmentSwapValidator.inputError(input);
            Subscription__c subscription = null;
            Asset oldAsset = null;
            CatalogQueryService.ProductView device = null;

            if (error == null) {
                subscription = subscriptions.get(input.subscriptionId);
                error = EquipmentSwapValidator.subscriptionError(
                    input,
                    subscription
                );
            }
            if (error == null) {
                oldAsset = assets.get(subscription.Asset__c);
                error = EquipmentSwapValidator.assetError(oldAsset);
            }
            if (error == null) {
                error = EquipmentSwapValidator.duplicateError(
                    inFlight.get(subscription.Id)
                );
            }
            if (error == null) {
                device = devices.get(input.newProductId);
                error = EquipmentSwapValidator.deviceError(subscription, device);
            }
            if (error == null) {
                OrderItem sourceItem = orderItems.get(
                    subscription.Order_Product__c
                );
                if (sourceItem == null || sourceItem.OrderId == null) {
                    error =
                        'Subscription has no source OrderItem to preserve lineage.';
                } else if (entries.get(device.productId) == null) {
                    error =
                        'No active pricebook entry exists for the new device.';
                }
            }
            if (error != null) {
                results[i].failed(error);
                continue;
            }

            EquipmentSwapContext context = new EquipmentSwapContext();
            context.resultIndex = i;
            context.result = results[i];
            context.input = input;
            context.subscription = subscription;
            context.oldAsset = oldAsset;
            context.device = device;
            context.sourceOrderItem = orderItems.get(
                subscription.Order_Product__c
            );
            context.pricebookEntry = entries.get(device.productId);
            context.serialNumber = input.serialNumber;
            context.colour = String.isBlank(input.colour)
                ? null
                : input.colour;
            context.imageUrl = String.isBlank(input.imageUrl)
                ? device.deviceImageUrl
                : input.imageUrl;
            context.attempted = true;
            contexts.add(context);

            intakeInputs.add(
                EquipmentSwapValidator.toIntakeInput(input, device)
            );
            contextIndexByIntake.put(intakeInputs.size() - 1, contexts.size() - 1);
        }

        if (intakeInputs.isEmpty()) {
            return results;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            List<LifecycleRequestService.RequestOutput> outputs =
                LifecycleRequestService.createRequests(intakeInputs);
            Set<Id> requestIds = new Set<Id>();
            for (LifecycleRequestService.RequestOutput output : outputs) {
                if (output != null && output.requestId != null) {
                    requestIds.add(output.requestId);
                }
            }
            Map<Id, Customer_Request__c> requests =
                EquipmentSwapRepository.requests(requestIds);

            List<EquipmentSwapContext> prepared =
                new List<EquipmentSwapContext>();
            for (Integer j = 0; j < outputs.size(); j++) {
                Integer contextIndex = contextIndexByIntake.get(j);
                if (contextIndex == null) {
                    continue;
                }
                EquipmentSwapContext context = contexts[contextIndex];
                LifecycleRequestService.RequestOutput output = outputs[j];
                if (output == null || output.success != true) {
                    context.result.failed(
                        output == null
                            ? 'Request could not be created.'
                            : output.message
                    );
                    continue;
                }
                context.request = requests.get(output.requestId);
                if (context.request == null) {
                    context.result.failed('Created request could not be reloaded.');
                    continue;
                }
                context.correlationId = EquipmentSwapPolicy.correlationId(
                    context.request.Id
                );
                context.result.submitted(
                    context.request,
                    output.status,
                    output.message
                );
                prepared.add(context);
            }

            EquipmentSwapWriter.prepare(prepared);

            List<EquipmentSwapContext> approved =
                new List<EquipmentSwapContext>();
            for (EquipmentSwapContext context : prepared) {
                if (context.request.Status__c == EquipmentSwapPolicy.STATUS_APPROVED) {
                    approved.add(context);
                } else if (
                    context.request.Status__c == EquipmentSwapPolicy.STATUS_AWAITING
                ) {
                    context.result.submitted(
                        context.request,
                        EquipmentSwapPolicy.STATUS_AWAITING,
                        'Swap submitted; manager approval is required.'
                    );
                } else {
                    context.result.submitted(
                        context.request,
                        context.request.Status__c,
                        'Swap submitted.'
                    );
                }
            }
            if (!approved.isEmpty()) {
                EquipmentSwapFulfilment.apply(approved);
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            for (EquipmentSwapContext context : contexts) {
                context.result.failed(
                    'Equipment swap could not be submitted. ' + ex.getMessage()
                );
            }
        }
        return results;
    }
}
