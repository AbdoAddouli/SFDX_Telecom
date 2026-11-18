/**
 * Bulk write path for cancellation fulfilment. One DML statement per related
 * object covers the whole batch; the caller owns the savepoint.
 */
public with sharing class CancellationFulfilmentWriter {
    public static void apply(List<CancellationFulfilmentItem> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        Date today = Date.today();

        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Asset> assets = new List<Asset>();
        List<Contract> contracts = new List<Contract>();
        List<Engagement__c> engagements = new List<Engagement__c>();
        List<Case> cases = new List<Case>();
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        Set<Id> accountIds = new Set<Id>();

        for (CancellationFulfilmentItem item : items) {
            Subscription__c subscription = item.subscription;
            subscriptions.add(
                new Subscription__c(
                    Id = subscription.Id,
                    Status__c = SubscriptionStateMachine.CANCELLED,
                    External_Status__c = CancellationFulfilmentPolicy.EXTERNAL_CANCELLED,
                    Last_Sync_DateTime__c = now
                )
            );
            if (subscription.Account__c != null) {
                accountIds.add(subscription.Account__c);
            }
            if (subscription.Asset__c != null) {
                assets.add(
                    new Asset(
                        Id = subscription.Asset__c,
                        Status = CancellationFulfilmentPolicy.ASSET_RETIRED
                    )
                );
            }
            if (subscription.Contract__c != null) {
                contracts.add(
                    new Contract(
                        Id = subscription.Contract__c,
                        Status = CancellationFulfilmentPolicy.CONTRACT_TERMINATED
                    )
                );
            }
            if (subscription.Engagement__c != null) {
                Decimal fee = item.request.Calculated_Fee__c == null
                    ? 0
                    : item.request.Calculated_Fee__c;
                engagements.add(
                    new Engagement__c(
                        Id = subscription.Engagement__c,
                        Status__c = CancellationFulfilmentPolicy.ENGAGEMENT_BREACHED,
                        Early_Termination_Fee__c = fee,
                        Breach_Amount__c = fee
                    )
                );
            }
            if (item.request.Case__c != null) {
                cases.add(
                    new Case(
                        Id = item.request.Case__c,
                        Status = CancellationFulfilmentPolicy.CASE_CLOSED
                    )
                );
            }
            requests.add(
                new Customer_Request__c(
                    Id = item.request.Id,
                    Status__c = CancellationPolicy.STATUS_COMPLETED,
                    Completed_On__c = now,
                    Resolution_Summary__c = (
                        'Cancellation fulfilled on ' + today.format() + '.'
                    ).left(1000)
                )
            );
        }

        Database.update(subscriptions, true);

        Set<Id> activeAccountIds =
            CancellationFulfilmentRepository.activeAccountIds(accountIds);
        List<Account> churnedAccounts = new List<Account>();
        for (Id accountId : accountIds) {
            if (!activeAccountIds.contains(accountId)) {
                churnedAccounts.add(
                    new Account(
                        Id = accountId,
                        Customer_Status__c = CancellationFulfilmentPolicy.ACCOUNT_CHURNED
                    )
                );
            }
        }

        if (!assets.isEmpty()) {
            Database.update(assets, true);
        }
        if (!contracts.isEmpty()) {
            Database.update(contracts, true);
        }
        if (!engagements.isEmpty()) {
            Database.update(engagements, true);
        }
        if (!cases.isEmpty()) {
            Database.update(cases, true);
        }
        Database.update(requests, true);
        if (!churnedAccounts.isEmpty()) {
            Database.update(churnedAccounts, true);
        }
    }
}
