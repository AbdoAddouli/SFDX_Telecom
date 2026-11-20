/** Manager-approval orchestration for UC-LIF-05. */
public with sharing class EquipmentSwapApproval {
    public static List<EquipmentSwapService.EquipmentSwapResult> execute(
        List<EquipmentSwapService.ApprovalInput> inputs
    ) {
        List<EquipmentSwapService.EquipmentSwapResult> results =
            new List<EquipmentSwapService.EquipmentSwapResult>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        Set<Id> requestIds = new Set<Id>();
        for (Integer i = 0; i < inputs.size(); i++) {
            results.add(new EquipmentSwapService.EquipmentSwapResult());
            if (inputs[i] != null && inputs[i].requestId != null) {
                requestIds.add(inputs[i].requestId);
            } else {
                results[i].failed('Request Id is required.');
            }
        }
        if (requestIds.isEmpty()) {
            return results;
        }

        Map<Id, Customer_Request__c> requests =
            EquipmentSwapRepository.requests(requestIds);
        Set<Id> subscriptionIds = new Set<Id>();
        Set<Id> assetIds = new Set<Id>();
        Set<Id> orderItemIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();

        for (Integer i = 0; i < inputs.size(); i++) {
            if (inputs[i] == null || inputs[i].requestId == null) {
                continue;
            }
            Customer_Request__c request = requests.get(inputs[i].requestId);
            if (request == null) {
                results[i].failed('Equipment swap request could not be found.');
                continue;
            }
            if (request.Status__c == EquipmentSwapPolicy.STATUS_COMPLETED) {
                results[i].success = true;
                results[i].requestId = request.Id;
                results[i].caseId = request.Case__c;
                results[i].subscriptionId = request.Subscription__c;
                results[i].oldAssetId = request.Old_Asset__c;
                results[i].newAssetId = request.New_Asset__c;
                results[i].status = EquipmentSwapPolicy.STATUS_COMPLETED;
                results[i].calculatedFee = EquipmentSwapPolicy.FEE;
                results[i].message = 'Swap already completed.';
                continue;
            }
            if (
                request.Request_Type__c != EquipmentSwapPolicy.REQUEST_TYPE ||
                request.Status__c != EquipmentSwapPolicy.STATUS_APPROVED
            ) {
                results[i].failed(
                    'Request is not an approved equipment swap.'
                );
                continue;
            }
            if (request.Subscription__c != null) {
                subscriptionIds.add(request.Subscription__c);
            }
            if (request.Old_Asset__c != null) {
                assetIds.add(request.Old_Asset__c);
            }
            if (request.Requested_Product__c != null) {
                productIds.add(request.Requested_Product__c);
            }
        }
        if (subscriptionIds.isEmpty()) {
            return results;
        }

        Map<Id, Subscription__c> subscriptions =
            EquipmentSwapRepository.subscriptions(subscriptionIds);
        for (Subscription__c subscription : subscriptions.values()) {
            if (subscription.Order_Product__c != null) {
                orderItemIds.add(subscription.Order_Product__c);
            }
        }
        Map<Id, Asset> assets = EquipmentSwapRepository.assets(assetIds);
        Map<Id, CatalogQueryService.ProductView> devices =
            EquipmentSwapRepository.devices();
        Map<Id, OrderItem> orderItems =
            EquipmentSwapRepository.sourceOrderItems(orderItemIds);
        Map<Id, PricebookEntry> entries =
            EquipmentSwapRepository.pricebookEntries(productIds);

        List<EquipmentSwapContext> approved = new List<EquipmentSwapContext>();
        for (Integer i = 0; i < inputs.size(); i++) {
            if (inputs[i] == null || inputs[i].requestId == null) {
                continue;
            }
            Customer_Request__c request = requests.get(inputs[i].requestId);
            if (
                request == null ||
                request.Status__c == EquipmentSwapPolicy.STATUS_COMPLETED ||
                request.Status__c != EquipmentSwapPolicy.STATUS_APPROVED
            ) {
                continue;
            }

            EquipmentSwapContext context = new EquipmentSwapContext();
            context.resultIndex = i;
            context.result = results[i];
            context.request = request;
            EquipmentSwapRepository.populateFromRequest(
                context,
                subscriptions,
                assets,
                devices,
                orderItems,
                entries
            );

            String error = EquipmentSwapValidator.requestError(
                request,
                context.subscription,
                context.oldAsset,
                context.device
            );
            if (error == null && context.sourceOrderItem == null) {
                error = 'Subscription has no source OrderItem to preserve lineage.';
            }
            if (error == null && context.pricebookEntry == null) {
                error = 'No active pricebook entry exists for the new device.';
            }
            if (error != null) {
                context.result.failed(error);
                continue;
            }
            approved.add(context);
        }

        EquipmentSwapFulfilment.apply(approved);
        return results;
    }
}
