/** Pure UC-LIF-05 validation. No SOQL or DML; safe per batch row. */
public with sharing class EquipmentSwapValidator {
    public static String inputError(
        EquipmentSwapService.EquipmentSwapInput input
    ) {
        if (input == null) {
            return 'Equipment swap details are required.';
        }
        if (input.accountId == null) {
            return 'Account is required.';
        }
        if (input.contactId == null) {
            return 'Contact is required.';
        }
        if (input.subscriptionId == null) {
            return 'Subscription is required.';
        }
        if (input.newProductId == null) {
            return 'New device product is required.';
        }
        if (String.isBlank(input.serialNumber)) {
            return 'Serial number is required.';
        }
        if (!Pattern.matches('^[A-Za-z0-9_-]{5,30}$', input.serialNumber)) {
            return 'Serial number must be 5 to 30 letters, digits, hyphens or underscores.';
        }
        if (!LifecycleRequestPolicy.VALID_CHANNELS.contains(input.channel)) {
            return 'Channel must be Portal, Advisor, API or Batch.';
        }
        if (
            input.goodwillWaiver == true &&
            String.isBlank(input.goodwillJustification)
        ) {
            return 'Goodwill justification is required for a waiver.';
        }
        return null;
    }

    public static String subscriptionError(
        EquipmentSwapService.EquipmentSwapInput input,
        Subscription__c subscription
    ) {
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (subscription.Id == null) {
            return 'Subscription could not be found.';
        }
        if (SubscriptionStateMachine.ACTIVE != subscription.Status__c) {
            return 'Only an active subscription can swap its device.';
        }
        if (input.accountId != subscription.Account__c) {
            return 'Subscription does not belong to the selected account.';
        }
        if (subscription.Asset__c == null) {
            return 'Subscription has no asset to swap.';
        }
        return null;
    }

    public static String assetError(Asset assetRecord) {
        if (assetRecord == null) {
            return 'The current device asset could not be found.';
        }
        if (EquipmentSwapPolicy.OLD_ASSET_STATUS == assetRecord.Status) {
            return 'The current device is already retired.';
        }
        return null;
    }

    public static String deviceError(
        Subscription__c subscription,
        CatalogQueryService.ProductView device
    ) {
        if (device == null || device.productId == null) {
            return 'New device is not in the active product catalogue.';
        }
        if (subscription == null || subscription.Product__r == null) {
            return 'Current product could not be resolved.';
        }
        if (subscription.Product__r.Family != device.family) {
            return 'Swap must keep the same product family as the current line.';
        }
        if (
            subscription.Product__r.Requires_Commitment__c !=
            device.requiresCommitment
        ) {
            return 'Device commitment tier changed. Use Renewal management instead.';
        }
        return null;
    }

    public static String duplicateError(Customer_Request__c inFlight) {
        if (inFlight == null) {
            return null;
        }
        return 'An equipment swap is already in progress for this subscription.';
    }

    public static String requestError(
        Customer_Request__c request,
        Subscription__c subscription,
        Asset oldAsset,
        CatalogQueryService.ProductView device
    ) {
        if (request == null) {
            return 'Equipment swap request could not be found.';
        }
        if (request.Request_Type__c != EquipmentSwapPolicy.REQUEST_TYPE) {
            return 'Request is not an equipment swap.';
        }
        if (request.Status__c == EquipmentSwapPolicy.STATUS_AWAITING) {
            return 'Manager approval is required before this swap can be applied.';
        }
        if (request.Status__c == EquipmentSwapPolicy.STATUS_COMPLETED) {
            return null;
        }
        if (request.Status__c != EquipmentSwapPolicy.STATUS_APPROVED) {
            return 'Equipment swap request is not in an approvable state.';
        }
        if (subscription == null) {
            return 'Subscription could not be found.';
        }
        if (oldAsset == null) {
            return 'Old asset could not be found.';
        }
        if (device == null) {
            return 'Requested device is no longer in the active catalogue.';
        }
        if (String.isBlank(request.New_Asset_Serial__c)) {
            return 'New asset serial is missing from the request.';
        }
        return null;
    }

    public static LifecycleRequestService.RequestInput toIntakeInput(
        EquipmentSwapService.EquipmentSwapInput input,
        CatalogQueryService.ProductView device
    ) {
        String detail = 'Device swap to ' +
            (device != null ? device.name : 'new device') +
            '. Service, contract and commitment are unchanged.';
        String comment = String.isBlank(input.customerComment)
            ? detail
            : detail + ' Customer comment: ' + input.customerComment;

        LifecycleRequestService.RequestInput intake =
            new LifecycleRequestService.RequestInput();
        intake.requestType = EquipmentSwapPolicy.REQUEST_TYPE;
        intake.accountId = input.accountId;
        intake.contactId = input.contactId;
        intake.subscriptionId = input.subscriptionId;
        intake.channel = input.channel;
        intake.requestedProduct = String.valueOf(input.newProductId);
        intake.customerComment = comment.left(1000);
        intake.goodwillWaiver = input.goodwillWaiver;
        intake.goodwillJustification = input.goodwillJustification;
        intake.priority = input.priority;
        return intake;
    }

    public static String summary(EquipmentSwapContext context) {
        return 'Swapped ' +
            (context.oldAsset != null ? context.oldAsset.Name : 'old device') +
            ' for ' +
            (context.device != null ? context.device.name : 'new device') +
            '; service and commitment unchanged.';
    }
}
