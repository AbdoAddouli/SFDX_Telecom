@isTest
private class SubscriptionWizardControllerTest {
    @TestSetup
    static void setup() {
        Account account = new Account(
            Name = 'Wizard Test Account',
            Segment__c = 'Consumer'
        );
        insert account;
        insert new Contact(
            FirstName = 'Wizard',
            LastName = 'Contact',
            Email = 'wizard.contact@example.com',
            Phone = '020 7000 0000',
            AccountId = account.Id
        );

        Pricebook2 pricebook = new Pricebook2(
            Name = 'Wizard Test Pricebook',
            IsActive = true
        );
        insert pricebook;
        Product2 product = new Product2(
            Name = 'Wizard Fiber 100',
            Family = 'TELCO_FIBER',
            Plan_Type__c = 'Fiber',
            Speed_Mbps__c = 100,
            Recurring__c = true,
            Requires_Commitment__c = true,
            IsActive = true,
            Is_Active__c = true,
            ATS_Product_Code__c = 'WIZ_FIBER'
        );
        insert product;

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 39.99,
                IsActive = true,
                UseStandardPrice = false
            ),
            new PricebookEntry(
                Pricebook2Id = pricebook.Id,
                Product2Id = product.Id,
                UnitPrice = 39.99,
                IsActive = true,
                UseStandardPrice = false
            )
        };
    }

    @isTest
    static void getAccountContextReturnsAccountAndContacts() {
        setAutosync(true);
        Account account = testAccount();

        Test.startTest();
        SubscriptionWizardController.AccountContext context =
            SubscriptionWizardController.getAccountContext(account.Id);
        Test.stopTest();

        System.assertEquals(account.Id, context.accountId);
        System.assertEquals('Wizard Test Account', context.accountName);
        System.assertEquals('Consumer', context.segment);
        System.assertEquals(true, context.isAutosync);
        System.assertEquals(1, context.contacts.size());
        System.assertEquals('Wizard Contact', context.contacts[0].name);
        System.assertEquals(
            'wizard.contact@example.com',
            context.contacts[0].email
        );
    }

    @isTest
    static void startCreatesResumableSession() {
        Account account = testAccount();
        Contact contact = testContact();

        Test.startTest();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        Test.stopTest();

        System.assertNotEquals(null, state.sessionId);
        System.assertEquals(account.Id, state.accountId);
        System.assertEquals(contact.Id, state.contactId);
        System.assertEquals(1, state.step);
        System.assertEquals('{}', state.stateJson);
        System.assertEquals(null, state.quoteId);

        Subscription_Wizard_State__c row = wizardRow(state.sessionId);
        System.assertEquals(UserInfo.getUserId(), row.Advisor__c);
        System.assertEquals(true, row.Is_Active__c);
        System.assertNotEquals(null, row.Last_Activity_On__c);
        System.assertNotEquals(null, row.Expires_On__c);
    }

    @isTest
    static void startResumesLatestActiveSession() {
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState first =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        first.step = 3;
        first.offerType = 'Mobile';
        first.commitmentCode = 'COMMIT12';
        first.stateJson = '{"postalCode":"OFB75001"}';
        SubscriptionWizardController.save(first);

        Test.startTest();
        SubscriptionWizardController.WizardState resumed =
            SubscriptionWizardController.start(
                account.Id,
                null,
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(first.sessionId, resumed.sessionId);
        System.assertEquals(3, resumed.step);
        System.assertEquals('Mobile', resumed.offerType);
        System.assertEquals('COMMIT12', resumed.commitmentCode);
        System.assertEquals('{"postalCode":"OFB75001"}', resumed.stateJson);
    }

    @isTest
    static void startLoadsSessionById() {
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState first =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );

        Test.startTest();
        SubscriptionWizardController.WizardState loaded =
            SubscriptionWizardController.start(null, null, null, first.sessionId);
        Test.stopTest();

        System.assertEquals(first.sessionId, loaded.sessionId);
        System.assertEquals(account.Id, loaded.accountId);
    }

    @isTest
    static void startDeactivatesPreviousActiveSession() {
        Account firstAccount = testAccount();
        insert new Subscription_Wizard_State__c(
            Account__c = firstAccount.Id,
            Advisor__c = UserInfo.getUserId(),
            Step__c = 2,
            State_Json__c = '{}',
            Is_Active__c = true,
            Last_Activity_On__c = DateTime.now(),
            Expires_On__c = Date.today().addDays(7)
        );
        Account secondAccount = new Account(
            Name = 'Wizard Second Account',
            Segment__c = 'Business'
        );
        insert secondAccount;

        Test.startTest();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                secondAccount.Id,
                null,
                null,
                null
            );
        Test.stopTest();

        Subscription_Wizard_State__c oldRow = [
            SELECT Is_Active__c
            FROM Subscription_Wizard_State__c
            WHERE Account__c = :firstAccount.Id
        ];
        System.assertEquals(false, oldRow.Is_Active__c);
        System.assertEquals(secondAccount.Id, state.accountId);
    }

    @isTest
    static void savePersistsStepAndSelections() {
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );

        state.step = 4;
        state.offerType = 'Fiber';
        state.commitmentCode = 'COMMIT24';
        state.stateJson = '{"postalCode":"OFB13001","effectiveDate":"2026-11-10"}';

        Test.startTest();
        SubscriptionWizardController.save(state);
        Test.stopTest();

        Subscription_Wizard_State__c row = wizardRow(state.sessionId);
        System.assertEquals(4, row.Step__c);
        System.assertEquals('Fiber', row.Offer_Type__c);
        System.assertEquals('COMMIT24', row.Commitment_Code__c);
        System.assertEquals(
            '{"postalCode":"OFB13001","effectiveDate":"2026-11-10"}',
            row.State_Json__c
        );
        System.assertEquals(true, row.Is_Active__c);
    }

    @isTest
    static void saveClampsStepToOneAndFive() {
        Account account = testAccount();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                null,
                null,
                null
            );

        state.step = 99;
        SubscriptionWizardController.save(state);
        System.assertEquals(5, wizardRow(state.sessionId).Step__c);

        state.step = 0;
        SubscriptionWizardController.save(state);
        System.assertEquals(1, wizardRow(state.sessionId).Step__c);
    }

    @isTest
    static void startRequiresAccountOrSession() {
        try {
            SubscriptionWizardController.start(null, null, null, null);
            System.assert(false, 'Expected an account validation error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Account is required'));
        }
    }

    @isTest
    static void startRejectsUnknownSession() {
        try {
            SubscriptionWizardController.start(null, null, null, null);
            System.assert(false, 'Expected a session validation error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Account is required'));
        }

        try {
            SubscriptionWizardController.start(
                null,
                null,
                null,
                'a0B000000000001'
            );
            System.assert(false, 'Expected a missing-session error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Wizard session not found'));
        }
    }

    @isTest
    static void saveRequiresSession() {
        try {
            SubscriptionWizardController.save(null);
            System.assert(false, 'Expected a session validation error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Wizard session is required'));
        }
    }

    @isTest
    static void createQuoteRequiresRequest() {
        try {
            SubscriptionWizardController.createQuote(null);
            System.assert(false, 'Expected an offer validation error.');
        } catch (AuraHandledException error) {
            System.assert(
                error.getMessage().contains('Offer selection is required')
            );
        }
    }

    @isTest
    static void saveContactDetailsUpdatesContact() {
        setAutosync(true);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );

        Test.startTest();
        SubscriptionWizardController.ContactOption saved =
            SubscriptionWizardController.saveContactDetails(
                state.sessionId,
                contact.Id,
                'new.contact@example.com',
                '+33 6 12 34 56 78'
            );
        Test.stopTest();

        System.assertNotEquals(null, saved);
        System.assertEquals('new.contact@example.com', saved.email);
        Contact refreshed = [
            SELECT Email, Phone
            FROM Contact
            WHERE Id = :contact.Id
        ];
        System.assertEquals('new.contact@example.com', refreshed.Email);
        System.assertEquals('+33 6 12 34 56 78', refreshed.Phone);
    }

    @isTest
    static void saveContactDetailsSkipsWhenAutosyncDisabled() {
        setAutosync(false);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );

        Test.startTest();
        try {
            SubscriptionWizardController.saveContactDetails(
                state.sessionId,
                contact.Id,
                'blocked@example.com',
                '000'
            );
            System.assert(false, 'Expected an autosync-disabled error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Auto-sync is disabled'));
        }
        Test.stopTest();

        Contact refreshed = [
            SELECT Email
            FROM Contact
            WHERE Id = :contact.Id
        ];
        System.assertEquals('wizard.contact@example.com', refreshed.Email);
    }

    @isTest
    static void saveContactDetailsRejectsForeignContact() {
        setAutosync(true);
        Account account = testAccount();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                null,
                null,
                null
            );

        Account otherAccount = new Account(Name = 'Wizard Other Account');
        insert otherAccount;
        Contact foreignContact = new Contact(
            FirstName = 'Other',
            LastName = 'Contact',
            Email = 'other.contact@example.com',
            AccountId = otherAccount.Id
        );
        insert foreignContact;

        try {
            SubscriptionWizardController.saveContactDetails(
                state.sessionId,
                foreignContact.Id,
                'foreign@example.com',
                '111'
            );
            System.assert(false, 'Expected an account mismatch error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('does not belong'));
        }
    }

    @isTest
    static void saveContactDetailsRequiresSession() {
        try {
            SubscriptionWizardController.saveContactDetails(
                null,
                testContact().Id,
                'x@example.com',
                '222'
            );
            System.assert(false, 'Expected a session validation error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('Wizard session is required'));
        }
    }

    @isTest
    static void finishAndActivateCreatesOrderAndActivates() {
        setBssFlag(true);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        Quote quote = wizardQuote(account, contact, state.sessionId, true);

        Test.startTest();
        SubscriptionWizardController.ActivationHandoff handoff =
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );
        Test.stopTest();

        System.assertEquals('Activated', handoff.status, handoff.message);
        System.assertNotEquals(null, handoff.orderId);
        System.assertNotEquals(null, handoff.orderNumber);
        System.assertEquals(1, handoff.assetCount);
        System.assertEquals(1, handoff.subscriptionCount);
        System.assertEquals(1, handoff.engagementCount);
        System.assertNotEquals(null, handoff.contractId);

        Order order = [
            SELECT
                Id,
                Name,
                OrderNumber,
                AccountId,
                BillToContactId,
                Pricebook2Id,
                Status,
                Activation_State__c,
                ContractId
            FROM Order
            WHERE Id = :handoff.orderId
        ];
        Quote activatedQuote = [
            SELECT QuoteNumber, Status
            FROM Quote
            WHERE Id = :quote.Id
        ];
        System.assertEquals(activatedQuote.QuoteNumber, order.Name);
        System.assertEquals(account.Id, order.AccountId);
        System.assertEquals(contact.Id, order.BillToContactId);
        System.assertEquals(pricebook().Id, order.Pricebook2Id);
        System.assertEquals('Activated', order.Status);
        System.assertEquals('Activated', order.Activation_State__c);
        System.assertEquals(handoff.contractId, order.ContractId);

        OrderItem item = [
            SELECT
                Id,
                Product2Id,
                Commitment_Option_Code__c,
                Subscription_Number__c
            FROM OrderItem
            WHERE OrderId = :order.Id
        ];
        System.assertEquals('COMMIT12', item.Commitment_Option_Code__c);
        System.assertNotEquals(null, item.Subscription_Number__c);

        System.assertEquals('Accepted', activatedQuote.Status);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Engagement__c
                WHERE Account__c = :account.Id
            ]
        );

        Subscription_Wizard_State__c session = wizardRow(state.sessionId);
        System.assertEquals(false, session.Is_Active__c);
        System.assertEquals(quote.Id, session.Quote__c);
        System.assert(
            session.State_Json__c.contains(String.valueOf(order.Id)),
            session.State_Json__c
        );
        System.assert(
            session.State_Json__c.contains('"activationStatus":"Activated"'),
            session.State_Json__c
        );
    }

    @isTest
    static void finishAndActivateIsIdempotent() {
        setBssFlag(true);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        Quote quote = wizardQuote(account, contact, state.sessionId, true);

        Test.startTest();
        SubscriptionWizardController.ActivationHandoff first =
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );
        SubscriptionWizardController.ActivationHandoff second =
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );
        Test.stopTest();

        System.assertEquals('Activated', first.status, first.message);
        System.assertEquals('Activated', second.status, second.message);
        System.assertEquals(first.orderId, second.orderId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Order
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Engagement__c
                WHERE Account__c = :account.Id
            ]
        );
    }

    @isTest
    static void finishAndActivateFailureKeepsRetryableReadyOrder() {
        setBssFlag(true);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        Quote quote = wizardQuote(account, contact, state.sessionId, true);

        ActivationService.setBssGateway(new FailingGateway());
        Test.startTest();
        SubscriptionWizardController.ActivationHandoff failed =
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );
        Test.stopTest();
        ActivationService.setBssGateway(
            new SimulatedBssProvisioningGateway()
        );

        System.assertEquals('Failed', failed.status);
        System.assert(
            failed.message.contains('BSS unavailable'),
            failed.message
        );
        System.assertNotEquals(null, failed.orderId);

        Order pending = [
            SELECT
                Id,
                Status,
                Activation_State__c,
                Failure_Reason__c
            FROM Order
            WHERE Id = :failed.orderId
        ];
        System.assertEquals('Draft', pending.Status);
        System.assertEquals('Ready', pending.Activation_State__c);
        System.assert(pending.Failure_Reason__c.contains('BSS unavailable'));
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Engagement__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Contract
                WHERE AccountId = :account.Id
            ]
        );

        Subscription_Wizard_State__c failedSession = wizardRow(state.sessionId);
        System.assertEquals(true, failedSession.Is_Active__c);
        System.assert(
            failedSession.State_Json__c.contains('"activationStatus":"Failed"')
        );

        SubscriptionWizardController.ActivationHandoff retried =
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );

        System.assertEquals('Activated', retried.status, retried.message);
        System.assertEquals(failed.orderId, retried.orderId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Asset
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Subscription__c
                WHERE Account__c = :account.Id
            ]
        );
        System.assertEquals(
            false,
            wizardRow(state.sessionId).Is_Active__c
        );
    }

    @isTest
    static void finishAndActivateRequiresQuoteLines() {
        setBssFlag(true);
        Account account = testAccount();
        Contact contact = testContact();
        SubscriptionWizardController.WizardState state =
            SubscriptionWizardController.start(
                account.Id,
                contact.Id,
                null,
                null
            );
        Quote quote = wizardQuote(account, contact, state.sessionId, false);

        try {
            SubscriptionWizardController.finishAndActivate(
                state.sessionId,
                quote.Id
            );
            System.assert(false, 'Expected a quote-line validation error.');
        } catch (AuraHandledException error) {
            System.assert(error.getMessage().contains('no line items'));
        }

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Order
                WHERE AccountId = :account.Id
            ]
        );
        System.assertEquals(
            true,
            wizardRow(state.sessionId).Is_Active__c
        );
    }

    @isTest
    static void finishAndActivateRequiresSession() {
        try {
            SubscriptionWizardController.finishAndActivate(null, null);
            System.assert(false, 'Expected a session validation error.');
        } catch (AuraHandledException error) {
            System.assert(
                error.getMessage().contains('Wizard session is required')
            );
        }
    }

    private class FailingGateway implements BssProvisioningGateway {
        public List<BssProvisioningResponse> provision(
            List<BssProvisioningRequest> requests
        ) {
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            for (BssProvisioningRequest request : requests) {
                BssProvisioningResponse response =
                    new BssProvisioningResponse();
                response.subscriptionId = request.subscriptionId;
                response.success = false;
                response.statusCode = '503';
                response.message = 'BSS unavailable';
                responses.add(response);
            }
            return responses;
        }
    }

    private static void setBssFlag(Boolean enabled) {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        if (flags == null) {
            flags = new ATS_Feature_Flags__c();
        }
        flags.SetupOwnerId = UserInfo.getOrganizationId();
        flags.BSS_Provisioning_Enabled__c = enabled;
        upsert flags;
    }

    private static void setAutosync(Boolean enabled) {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        if (flags == null) {
            flags = new ATS_Feature_Flags__c();
        }
        flags.SetupOwnerId = UserInfo.getOrganizationId();
        flags.Is_Autosync__c = enabled;
        upsert flags;
    }

    private static Pricebook2 pricebook() {
        return [
            SELECT Id, Name
            FROM Pricebook2
            WHERE Name = 'Wizard Test Pricebook'
            LIMIT 1
        ];
    }

    private static Product2 wizardProduct() {
        return [
            SELECT
                Id,
                Name,
                Family,
                Plan_Type__c,
                Recurring__c,
                ATS_Product_Code__c
            FROM Product2
            WHERE ATS_Product_Code__c = 'WIZ_FIBER'
            LIMIT 1
        ];
    }

    private static PricebookEntry wizardEntry() {
        Pricebook2 book = pricebook();
        Product2 product = wizardProduct();
        return [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :book.Id AND Product2Id = :product.Id
            LIMIT 1
        ];
    }

    private static Quote wizardQuote(
        Account account,
        Contact contact,
        Id sessionId,
        Boolean withLine
    ) {
        Pricebook2 book = pricebook();
        Opportunity opportunity = new Opportunity(
            Name = 'Wizard Activation Opportunity',
            AccountId = account.Id,
            Primary_Contact__c = contact.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = book.Id
        );
        insert opportunity;

        Quote quote = new Quote(
            Name = 'Wizard Activation Quote',
            OpportunityId = opportunity.Id,
            Pricebook2Id = book.Id,
            ContactId = contact.Id,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30),
            Wizard_Session__c = sessionId
        );
        insert quote;

        if (withLine == true) {
            Product2 product = wizardProduct();
            PricebookEntry entry = wizardEntry();
            insert new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = entry.Id,
                Product2Id = product.Id,
                Quantity = 1,
                UnitPrice = entry.UnitPrice,
                Description = 'Wizard Fiber line',
                ServiceDate = Date.today(),
                Commitment_Option_Code__c = 'COMMIT12'
            );
        }
        return quote;
    }

    private static Account testAccount() {
        return [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Name = 'Wizard Test Account'
            LIMIT 1
        ];
    }

    private static Contact testContact() {
        return [
            SELECT Id
            FROM Contact
            WHERE Email = 'wizard.contact@example.com'
            LIMIT 1
        ];
    }

    private static Subscription_Wizard_State__c wizardRow(Id sessionId) {
        return [
            SELECT Id, Account__c, Contact__c, Advisor__c, Offer_Type__c,
                Commitment_Code__c, Step__c, State_Json__c, Is_Active__c,
                Quote__c, Last_Activity_On__c, Expires_On__c
            FROM Subscription_Wizard_State__c
            WHERE Id = :sessionId
        ];
    }
}
