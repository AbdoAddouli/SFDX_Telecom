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

    private static void setAutosync(Boolean enabled) {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        if (flags == null) {
            flags = new ATS_Feature_Flags__c();
        }
        flags.SetupOwnerId = UserInfo.getOrganizationId();
        flags.Is_Autosync__c = enabled;
        upsert flags;
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
                Last_Activity_On__c, Expires_On__c
            FROM Subscription_Wizard_State__c
            WHERE Id = :sessionId
        ];
    }
}
