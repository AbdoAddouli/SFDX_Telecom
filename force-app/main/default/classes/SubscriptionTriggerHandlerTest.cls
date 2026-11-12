@IsTest
private class SubscriptionTriggerHandlerTest {
    private static final String ACCOUNT_NAME = 'Subscription Trigger Test';
    private static final String ASSET_NAME = 'Subscription Trigger Asset';

    @TestSetup
    static void createData() {
        Account account = new Account(Name = ACCOUNT_NAME);
        insert account;
        insert new Asset(Name = ASSET_NAME, AccountId = account.Id);
    }

    private static Account testAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = :ACCOUNT_NAME
            LIMIT 1
        ];
    }

    private static Asset testAsset() {
        return [
            SELECT Id
            FROM Asset
            WHERE Name = :ASSET_NAME
            LIMIT 1
        ];
    }

    private static Subscription__c newSubscription(String status) {
        return new Subscription__c(
            Account__c = testAccount().Id,
            Asset__c = testAsset().Id,
            Service_Line_Type__c = 'Mobile',
            Status__c = status
        );
    }

    private static Subscription__c insertAt(String targetStatus) {
        Subscription__c subscription = newSubscription(
            SubscriptionStateMachine.DRAFT
        );
        insert subscription;

        if (targetStatus == SubscriptionStateMachine.DRAFT) {
            return subscription;
        }

        moveTo(subscription, SubscriptionStateMachine.PENDING_ACTIVATION);
        if (targetStatus == SubscriptionStateMachine.PENDING_ACTIVATION) {
            return subscription;
        }

        moveTo(subscription, SubscriptionStateMachine.ACTIVE);
        if (targetStatus == SubscriptionStateMachine.ACTIVE) {
            return subscription;
        }

        if (targetStatus == SubscriptionStateMachine.SUSPENDED) {
            moveTo(subscription, SubscriptionStateMachine.SUSPENDED);
            return subscription;
        }

        if (targetStatus == SubscriptionStateMachine.SUPERSEDED) {
            moveTo(subscription, SubscriptionStateMachine.SUPERSEDED);
            return subscription;
        }

        moveTo(
            subscription,
            SubscriptionStateMachine.PENDING_CANCELLATION
        );
        if (targetStatus == SubscriptionStateMachine.PENDING_CANCELLATION) {
            return subscription;
        }

        moveTo(subscription, SubscriptionStateMachine.CANCELLED);
        return subscription;
    }

    private static void moveTo(
        Subscription__c subscription,
        String status
    ) {
        subscription.Status__c = status;
        update subscription;
    }

    @IsTest
    static void blankInsertStatusDefaultsToDraft() {
        Subscription__c subscription = newSubscription(null);

        Test.startTest();
        insert subscription;
        Test.stopTest();

        Subscription__c saved = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :subscription.Id
        ];
        System.assertEquals(
            SubscriptionStateMachine.DRAFT,
            saved.Status__c,
            'A blank initial status must default to Draft'
        );
    }

    @IsTest
    static void insertAllowsOnlyDraftOrPendingActivation() {
        insert new List<Subscription__c>{
            newSubscription(SubscriptionStateMachine.DRAFT),
            newSubscription(SubscriptionStateMachine.PENDING_ACTIVATION)
        };

        Database.SaveResult result = Database.insert(
            newSubscription(SubscriptionStateMachine.ACTIVE),
            false
        );

        System.assert(
            !result.isSuccess(),
            'A subscription must not be inserted directly as Active'
        );
        System.assert(
            result.getErrors()[0].getMessage().contains(
                'must start in Draft or PendingActivation'
            ),
            'The initial status error must explain the allowed values'
        );
    }

    @IsTest
    static void validLifecycleTransitionsAreAllowed() {
        Subscription__c subscription = insertAt(
            SubscriptionStateMachine.DRAFT
        );

        List<String> transitions = new List<String>{
            SubscriptionStateMachine.PENDING_ACTIVATION,
            SubscriptionStateMachine.ACTIVE,
            SubscriptionStateMachine.SUSPENDED,
            SubscriptionStateMachine.ACTIVE,
            SubscriptionStateMachine.PENDING_CANCELLATION,
            SubscriptionStateMachine.CANCELLED
        };

        Test.startTest();
        for (String nextStatus : transitions) {
            moveTo(subscription, nextStatus);
            System.assertEquals(
                nextStatus,
                subscription.Status__c,
                'Transition to ' + nextStatus + ' must succeed'
            );
        }
        Test.stopTest();

        System.assert(
            SubscriptionStateMachine.isTerminal(subscription.Status__c),
            'Cancelled must be terminal'
        );
    }

    @IsTest
    static void activeToSupersededIsAllowed() {
        Subscription__c subscription = insertAt(
            SubscriptionStateMachine.ACTIVE
        );

        Test.startTest();
        moveTo(subscription, SubscriptionStateMachine.SUPERSEDED);
        Test.stopTest();

        System.assertEquals(
            SubscriptionStateMachine.SUPERSEDED,
            subscription.Status__c
        );
        System.assert(
            SubscriptionStateMachine.isTerminal(subscription.Status__c),
            'Superseded must be terminal'
        );
    }

    @IsTest
    static void activeCannotMoveDirectlyToCancelled() {
        Subscription__c subscription = insertAt(
            SubscriptionStateMachine.ACTIVE
        );
        subscription.Status__c = SubscriptionStateMachine.CANCELLED;

        Test.startTest();
        Database.SaveResult result = Database.update(
            subscription,
            false
        );
        Test.stopTest();

        System.assert(
            !result.isSuccess(),
            'Direct Active -> Cancelled must be rejected'
        );
        System.assert(
            result.getErrors()[0].getMessage().contains(
                'Illegal subscription status transition'
            ),
            'The transition error must be clear'
        );

        Subscription__c saved = [
            SELECT Status__c
            FROM Subscription__c
            WHERE Id = :subscription.Id
        ];
        System.assertEquals(
            SubscriptionStateMachine.ACTIVE,
            saved.Status__c,
            'The rejected transition must not change the stored status'
        );
    }

    @IsTest
    static void pendingActivationCannotMoveToSuspended() {
        Subscription__c subscription = insertAt(
            SubscriptionStateMachine.PENDING_ACTIVATION
        );
        subscription.Status__c = SubscriptionStateMachine.SUSPENDED;

        Database.SaveResult result = Database.update(subscription, false);

        System.assert(
            !result.isSuccess(),
            'PendingActivation -> Suspended must be rejected'
        );
        System.assert(
            result.getErrors()[0].getMessage().contains(
                'Illegal subscription status transition'
            )
        );
    }

    @IsTest
    static void terminalStatusesCannotBeReopened() {
        for (String terminal : new List<String>{
            SubscriptionStateMachine.CANCELLED,
            SubscriptionStateMachine.SUPERSEDED
        }) {
            Subscription__c subscription = insertAt(terminal);
            subscription.Status__c = SubscriptionStateMachine.ACTIVE;

            Database.SaveResult result = Database.update(
                subscription,
                false
            );

            System.assert(
                !result.isSuccess(),
                terminal + ' must not be reopened as Active'
            );
            System.assert(
                result.getErrors()[0].getMessage().contains(
                    'Illegal subscription status transition'
                )
            );
        }
    }

    @IsTest
    static void sameStatusUpdateIsAllowed() {
        Subscription__c subscription = insertAt(
            SubscriptionStateMachine.ACTIVE
        );
        subscription.Status__c = SubscriptionStateMachine.ACTIVE;
        subscription.Monthly_Amount__c = 39.99;

        Test.startTest();
        Database.SaveResult result = Database.update(
            subscription,
            false
        );
        Test.stopTest();

        System.assert(
            result.isSuccess(),
            'A no-op status update must not block unrelated edits'
        );
    }

    @IsTest
    static void bulkMixedUpdatesAreBulkSafe() {
        List<Subscription__c> subscriptions = new List<Subscription__c>();
        for (Integer i = 0; i < 20; i++) {
            subscriptions.add(
                newSubscription(SubscriptionStateMachine.DRAFT)
            );
        }
        insert subscriptions;

        for (Subscription__c subscription : subscriptions) {
            subscription.Status__c =
                SubscriptionStateMachine.PENDING_ACTIVATION;
        }
        update subscriptions;

        for (Subscription__c subscription : subscriptions) {
            subscription.Status__c = SubscriptionStateMachine.ACTIVE;
        }
        update subscriptions;

        for (Integer i = 0; i < subscriptions.size(); i++) {
            Subscription__c subscription = subscriptions[i];
            subscription.Status__c = i == 0
                ? SubscriptionStateMachine.CANCELLED
                : SubscriptionStateMachine.SUSPENDED;
        }

        Test.startTest();
        Database.SaveResult[] results = Database.update(
            subscriptions,
            false
        );
        Test.stopTest();

        Integer failures = 0;
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                failures++;
                System.assert(
                    result.getErrors()[0].getMessage().contains(
                        'Illegal subscription status transition'
                    )
                );
            }
        }

        System.assertEquals(
            1,
            failures,
            'Only the direct Active -> Cancelled row must fail'
        );
        System.assertEquals(
            19,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Status__c = :SubscriptionStateMachine.SUSPENDED
            ],
            'Valid rows in a partial bulk update must persist'
        );
    }

    @IsTest
    static void hardDeleteIsBlocked() {
        Subscription__c subscription = newSubscription(
            SubscriptionStateMachine.DRAFT
        );
        insert subscription;

        Test.startTest();
        Database.DeleteResult result = Database.delete(
            subscription,
            false
        );
        Test.stopTest();

        System.assert(
            !result.isSuccess(),
            'Subscriptions must be soft-closed, never hard-deleted'
        );
        System.assert(
            result.getErrors()[0].getMessage().contains(
                'cannot be deleted'
            )
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Id = :subscription.Id
            ],
            'The subscription must remain after a blocked delete'
        );
    }

    @IsTest
    static void stateMachineMapExposesOnlyAllowedMoves() {
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.DRAFT,
                SubscriptionStateMachine.PENDING_ACTIVATION
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.PENDING_ACTIVATION,
                SubscriptionStateMachine.ACTIVE
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.ACTIVE,
                SubscriptionStateMachine.SUSPENDED
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.SUSPENDED,
                SubscriptionStateMachine.ACTIVE
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.ACTIVE,
                SubscriptionStateMachine.PENDING_CANCELLATION
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.PENDING_CANCELLATION,
                SubscriptionStateMachine.CANCELLED
            )
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.ACTIVE,
                SubscriptionStateMachine.SUPERSEDED
            )
        );

        System.assert(
            !SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.ACTIVE,
                SubscriptionStateMachine.CANCELLED
            ),
            'Cancellation must go through PendingCancellation'
        );
        System.assert(
            !SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.CANCELLED,
                SubscriptionStateMachine.ACTIVE
            ),
            'Cancelled is terminal'
        );
        System.assert(
            !SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.SUPERSEDED,
                SubscriptionStateMachine.ACTIVE
            ),
            'Superseded is terminal'
        );
        System.assert(
            !SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.SUSPENDED,
                SubscriptionStateMachine.PENDING_CANCELLATION
            ),
            'A suspended line must resume before cancellation'
        );
        System.assert(
            !SubscriptionStateMachine.isAllowed(null, SubscriptionStateMachine.DRAFT),
            'A null source status is never valid'
        );
        System.assert(
            SubscriptionStateMachine.isAllowed(
                SubscriptionStateMachine.ACTIVE,
                SubscriptionStateMachine.ACTIVE
            ),
            'A no-op status update is allowed'
        );

        System.assert(
            SubscriptionStateMachine.isTerminal(
                SubscriptionStateMachine.CANCELLED
            )
        );
        System.assert(
            SubscriptionStateMachine.isTerminal(
                SubscriptionStateMachine.SUPERSEDED
            )
        );
        System.assert(
            !SubscriptionStateMachine.isTerminal(
                SubscriptionStateMachine.ACTIVE
            )
        );
    }
}
