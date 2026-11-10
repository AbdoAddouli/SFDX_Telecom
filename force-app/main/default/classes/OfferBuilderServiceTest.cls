@IsTest
private class OfferBuilderServiceTest {
    private static final String POSTAL_FULL = 'OFB75001';
    private static final String POSTAL_NO_FIBER = 'OFB59000';
    private static final String POSTAL_FUTURE = 'OFB13001';
    private static final String MOBILE_CODE = 'OFB_MOBILE_20';
    private static final String DEVICE_CODE = 'OFB_DEVICE';
    private static final String FIBER_CODE = 'OFB_FIBER_100';
    private static final String PRICEBOOK_NAME = 'ATS Offer Test Pricebook';

    @TestSetup
    static void createTestData() {
        Pricebook2 pricebook = new Pricebook2(
            Name = PRICEBOOK_NAME,
            IsActive = true
        );
        insert pricebook;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = 'Offer Mobile 20',
                Family = 'TELCO_MOBILE',
                Plan_Type__c = 'Mobile',
                Data_GB__c = 20,
                Unlimited_Calls__c = true,
                Unlimited_SMS__c = true,
                Recurring__c = true,
                Requires_Commitment__c = false,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = MOBILE_CODE
            ),
            new Product2(
                Name = 'Offer Device',
                Family = 'TELCO_DEVICE',
                Recurring__c = false,
                Requires_Commitment__c = true,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = DEVICE_CODE
            ),
            new Product2(
                Name = 'Offer Fiber 100',
                Family = 'TELCO_FIBER',
                Plan_Type__c = 'Fiber',
                Speed_Mbps__c = 100,
                Recurring__c = true,
                Requires_Commitment__c = false,
                IsActive = true,
                Is_Active__c = true,
                ATS_Product_Code__c = FIBER_CODE
            )
        };
        insert products;

        Map<String, Product2> byCode = new Map<String, Product2>();
        for (Product2 product : products) {
            byCode.put(product.ATS_Product_Code__c, product);
        }

        Id standardPricebookId = Test.getStandardPricebookId();
        insert new List<PricebookEntry>{
            standardEntry(
                standardPricebookId,
                byCode.get(MOBILE_CODE).Id,
                100
            ),
            standardEntry(
                standardPricebookId,
                byCode.get(DEVICE_CODE).Id,
                1000
            ),
            standardEntry(
                standardPricebookId,
                byCode.get(FIBER_CODE).Id,
                500
            )
        };
        insert new List<PricebookEntry>{
            customEntry(pricebook.Id, byCode.get(MOBILE_CODE).Id, 100),
            customEntry(pricebook.Id, byCode.get(DEVICE_CODE).Id, 1000),
            customEntry(pricebook.Id, byCode.get(FIBER_CODE).Id, 500)
        };

        Account account = new Account(
            Name = 'Offer Builder Test Account',
            Segment__c = 'Consumer'
        );
        insert account;

        Contact contact = new Contact(
            FirstName = 'Offer',
            LastName = 'Builder',
            Email = 'offer.builder@example.com',
            AccountId = account.Id
        );
        insert contact;

        Opportunity opportunity = new Opportunity(
            Name = 'Offer Builder Test Opportunity',
            AccountId = account.Id,
            Primary_Contact__c = contact.Id,
            Pricebook2Id = pricebook.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        insert new Subscription_Wizard_State__c(
            Account__c = account.Id,
            Contact__c = contact.Id,
            Opportunity__c = opportunity.Id,
            Advisor__c = UserInfo.getUserId(),
            Offer_Type__c = 'Mobile',
            Product__c = byCode.get(MOBILE_CODE).Id,
            Device__c = byCode.get(DEVICE_CODE).Id,
            Commitment_Code__c = 'COMMIT12',
            Step__c = 4,
            Is_Active__c = true,
            Last_Activity_On__c = DateTime.now(),
            Expires_On__c = Date.today().addDays(7)
        );

        insert new List<Eligibility__c>{
            new Eligibility__c(
                Name = 'Offer Full Fibre',
                Postal_Code__c = POSTAL_FULL,
                Country__c = 'FR',
                Fiber_Available__c = true,
                Max_Downstream_Mbps__c = 500,
                Earliest_Activation_Date__c = Date.today().addDays(-1),
                Is_Active__c = true
            ),
            new Eligibility__c(
                Name = 'Offer No Fibre',
                Postal_Code__c = POSTAL_NO_FIBER,
                Country__c = 'FR',
                Fiber_Available__c = false,
                Is_Active__c = true
            ),
            new Eligibility__c(
                Name = 'Offer Future Fibre',
                Postal_Code__c = POSTAL_FUTURE,
                Country__c = 'FR',
                Fiber_Available__c = true,
                Max_Downstream_Mbps__c = 500,
                Earliest_Activation_Date__c = Date.today().addDays(30),
                Is_Active__c = true
            )
        };
    }

    private static PricebookEntry standardEntry(
        Id pricebookId,
        Id productId,
        Decimal unitPrice
    ) {
        return new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            UnitPrice = unitPrice,
            IsActive = true,
            UseStandardPrice = false
        );
    }

    private static PricebookEntry customEntry(
        Id pricebookId,
        Id productId,
        Decimal unitPrice
    ) {
        return standardEntry(pricebookId, productId, unitPrice);
    }

    private static Account testAccount() {
        return [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Name = 'Offer Builder Test Account'
            LIMIT 1
        ];
    }

    private static Contact testContact() {
        return [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = 'offer.builder@example.com'
            LIMIT 1
        ];
    }

    private static Pricebook2 testPricebook() {
        return [
            SELECT Id, Name
            FROM Pricebook2
            WHERE Name = :PRICEBOOK_NAME
            LIMIT 1
        ];
    }

    private static Opportunity testOpportunity() {
        return [
            SELECT Id, AccountId, Primary_Contact__c
            FROM Opportunity
            WHERE Name = 'Offer Builder Test Opportunity'
            LIMIT 1
        ];
    }

    private static Subscription_Wizard_State__c testWizard() {
        return [
            SELECT Id, Account__c, Contact__c, Opportunity__c
            FROM Subscription_Wizard_State__c
            WHERE Advisor__c = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    private static Product2 product(String productCode) {
        return [
            SELECT Id, Name, Family, Plan_Type__c
            FROM Product2
            WHERE ATS_Product_Code__c = :productCode
            LIMIT 1
        ];
    }

    private static OfferBuilderService.Selection baseSelection() {
        Account account = testAccount();
        Contact contact = testContact();
        Opportunity opportunity = testOpportunity();
        Subscription_Wizard_State__c wizard = testWizard();
        Product2 mobile = product(MOBILE_CODE);
        Product2 device = product(DEVICE_CODE);

        OfferBuilderService.Selection selection =
            new OfferBuilderService.Selection();
        selection.accountId = account.Id;
        selection.contactId = contact.Id;
        selection.opportunityId = opportunity.Id;
        selection.wizardSessionId = wizard.Id;
        selection.offerType = 'Mobile';
        selection.planProductId = mobile.Id;
        selection.deviceProductId = device.Id;
        selection.commitmentCode = 'COMMIT12';
        selection.segment = 'Consumer';
        selection.effectiveDate = Date.today();
        selection.portalSubmitted = false;
        return selection;
    }

    private static OfferBuilderService.Selection fibreSelection(String postalCode) {
        OfferBuilderService.Selection selection = baseSelection();
        selection.planProductId = product(FIBER_CODE).Id;
        selection.deviceProductId = null;
        selection.offerType = 'Fiber';
        selection.commitmentCode = 'NOCOMMIT';
        selection.postalCode = postalCode;
        selection.opportunityId = null;
        selection.wizardSessionId = null;
        return selection;
    }

    private static String createQuoteError(
        OfferBuilderService.Selection selection
    ) {
        try {
            OfferBuilderService.createQuote(selection);
        } catch (OfferBuilderService.OfferException error) {
            return error.getMessage();
        }
        System.assert(false, 'Expected an OfferException.');
        return null;
    }

    @IsTest
    static void createsPricedQuoteWithDeviceBundle() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.portalSubmitted = true;

        Test.startTest();
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(selection);
        Test.stopTest();

        System.assertNotEquals(null, result.quoteId);
        System.assertNotEquals(null, result.quoteNumber);
        System.assertEquals(2, result.lineCount);
        System.assertEquals(2, result.quoteLineItemIds.size());
        System.assertEquals(1100.00, result.totalListPrice);
        System.assertEquals(310.00, result.totalAdjustment);
        System.assertEquals(790.00, result.totalPrice);
        System.assert(
            result.priceBreakdownJson.contains('Device_Bundle_30_Percent')
        );

        Quote quote = [
            SELECT Id, OpportunityId, Pricebook2Id, ContactId,
                Wizard_Session__c, Portal_Submitted__c, Status,
                ExpirationDate
            FROM Quote
            WHERE Id = :result.quoteId
        ];
        System.assertEquals(testOpportunity().Id, quote.OpportunityId);
        System.assertEquals(testContact().Id, quote.ContactId);
        System.assertEquals(testPricebook().Id, quote.Pricebook2Id);
        System.assertEquals(selection.wizardSessionId, quote.Wizard_Session__c);
        System.assertEquals(true, quote.Portal_Submitted__c);
        System.assertEquals('Draft', quote.Status);
        System.assertEquals(Date.today().addDays(30), quote.ExpirationDate);

        Id mobileId = product(MOBILE_CODE).Id;
        Id deviceId = product(DEVICE_CODE).Id;
        QuoteLineItem planLine = null;
        QuoteLineItem deviceLine = null;
        for (QuoteLineItem line : [
            SELECT Id, Product2Id, UnitPrice, ListPrice, Quantity,
                Commitment_Option_Code__c, Subscription_Key__c, Description
            FROM QuoteLineItem
            WHERE QuoteId = :result.quoteId
        ]) {
            if (line.Product2Id == mobileId) {
                planLine = line;
            } else if (line.Product2Id == deviceId) {
                deviceLine = line;
            }
        }

        System.assertNotEquals(null, planLine);
        System.assertNotEquals(null, deviceLine);
        System.assertEquals(90.00, planLine.UnitPrice);
        System.assertEquals(100.00, planLine.ListPrice);
        System.assertEquals(700.00, deviceLine.UnitPrice);
        System.assertEquals(1000.00, deviceLine.ListPrice);
        System.assertEquals(1, planLine.Quantity);
        System.assertEquals('COMMIT12', planLine.Commitment_Option_Code__c);
        System.assertEquals('COMMIT12', deviceLine.Commitment_Option_Code__c);
        System.assertNotEquals(null, planLine.Subscription_Key__c);
        System.assertNotEquals(null, deviceLine.Subscription_Key__c);
        System.assertNotEquals(
            planLine.Subscription_Key__c,
            deviceLine.Subscription_Key__c
        );
        System.assert(planLine.Subscription_Key__c.length() <= 30);
        System.assert(deviceLine.Subscription_Key__c.length() <= 30);

        Subscription_Wizard_State__c wizard = [
            SELECT Quote__c, Opportunity__c, Product__c, Device__c,
                Offer_Type__c, Commitment_Code__c, Step__c,
                Price_Breakdown__c
            FROM Subscription_Wizard_State__c
            WHERE Id = :selection.wizardSessionId
        ];
        System.assertEquals(result.quoteId, wizard.Quote__c);
        System.assertEquals(result.opportunityId, wizard.Opportunity__c);
        System.assertEquals(5, wizard.Step__c);
        System.assertEquals('COMMIT12', wizard.Commitment_Code__c);
        System.assert(
            wizard.Price_Breakdown__c.contains('Device_Bundle_30_Percent')
        );
    }

    @IsTest
    static void createsOpportunityWhenSelectionHasNone() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.opportunityId = null;
        selection.wizardSessionId = null;
        selection.deviceProductId = null;
        selection.portalSubmitted = true;

        Test.startTest();
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(selection);
        Test.stopTest();

        System.assertEquals(1, result.lineCount);
        System.assertEquals(100.00, result.totalListPrice);
        System.assertEquals(10.00, result.totalAdjustment);
        System.assertEquals(90.00, result.totalPrice);

        Opportunity opportunity = [
            SELECT AccountId, Primary_Contact__c, Pricebook2Id,
                Journey_Step__c, Eligibility_Checked__c, Portal_Source__c
            FROM Opportunity
            WHERE Id = :result.opportunityId
        ];
        System.assertEquals(testAccount().Id, opportunity.AccountId);
        System.assertEquals(testContact().Id, opportunity.Primary_Contact__c);
        System.assertEquals(testPricebook().Id, opportunity.Pricebook2Id);
        System.assertEquals('Quoting', opportunity.Journey_Step__c);
        System.assertEquals(false, opportunity.Eligibility_Checked__c);
        System.assertEquals(true, opportunity.Portal_Source__c);

        Quote quote = [
            SELECT Wizard_Session__c, Portal_Submitted__c
            FROM Quote
            WHERE Id = :result.quoteId
        ];
        System.assertEquals(null, quote.Wizard_Session__c);
        System.assertEquals(true, quote.Portal_Submitted__c);
    }

    @IsTest
    static void createsEligibleFibreQuote() {
        OfferBuilderService.Selection selection = fibreSelection(POSTAL_FULL);

        Test.startTest();
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(selection);
        Test.stopTest();

        System.assertEquals(1, result.lineCount);
        System.assertEquals(500.00, result.totalListPrice);
        System.assertEquals(0.00, result.totalAdjustment);
        System.assertEquals(500.00, result.totalPrice);

        Opportunity opportunity = [
            SELECT Eligibility_Checked__c
            FROM Opportunity
            WHERE Id = :result.opportunityId
        ];
        System.assertEquals(true, opportunity.Eligibility_Checked__c);

        QuoteLineItem line = [
            SELECT UnitPrice, Commitment_Option_Code__c
            FROM QuoteLineItem
            WHERE QuoteId = :result.quoteId
            LIMIT 1
        ];
        System.assertEquals(500.00, line.UnitPrice);
        System.assertEquals('NOCOMMIT', line.Commitment_Option_Code__c);
    }

    @IsTest
    static void blocksFibreWithoutCoverage() {
        String message = createQuoteError(fibreSelection(POSTAL_NO_FIBER));

        System.assert(message.contains('not available'), message);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Quote],
            'A rejected fibre quote must not create a Quote.'
        );
    }

    @IsTest
    static void blocksFutureFibreActivation() {
        String message = createQuoteError(fibreSelection(POSTAL_FUTURE));

        System.assert(message.contains('until'), message);
        System.assertEquals(0, [SELECT COUNT() FROM Quote]);
    }

    @IsTest
    static void blocksFibreWithoutPostalCode() {
        String message = createQuoteError(fibreSelection(null));

        System.assert(message.contains('Postal code is required'), message);
        System.assertEquals(0, [SELECT COUNT() FROM Quote]);
    }

    @IsTest
    static void blocksDeviceWithoutCommitment() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.commitmentCode = 'NOCOMMIT';

        String message = createQuoteError(selection);

        System.assert(
            message.contains('requires a 12 or 24 month commitment'),
            message
        );
        System.assertEquals(0, [SELECT COUNT() FROM Quote]);
    }

    @IsTest
    static void rejectsContactFromAnotherAccount() {
        Account otherAccount = new Account(
            Name = 'Other Offer Account',
            Segment__c = 'Consumer'
        );
        insert otherAccount;
        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Contact',
            Email = 'other.offer.contact@example.com',
            AccountId = otherAccount.Id
        );
        insert otherContact;

        OfferBuilderService.Selection selection = baseSelection();
        selection.contactId = otherContact.Id;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('contact does not belong'),
            message
        );
        System.assertEquals(0, [SELECT COUNT() FROM Quote]);
    }

    @IsTest
    static void rejectsMissingPricebookEntry() {
        Product2 noPrice = new Product2(
            Name = 'Offer No Price',
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Recurring__c = true,
            Requires_Commitment__c = false,
            IsActive = true,
            Is_Active__c = true,
            ATS_Product_Code__c = 'OFB_NO_PRICE'
        );
        insert noPrice;

        OfferBuilderService.Selection selection = baseSelection();
        selection.planProductId = noPrice.Id;
        selection.opportunityId = null;
        selection.wizardSessionId = null;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('No active pricebook entry'),
            message
        );
        System.assertEquals(0, [SELECT COUNT() FROM Quote]);
    }

    @IsTest
    static void quoteLinePriceIsSnapshot() {
        OfferBuilderService.Selection selection = baseSelection();

        Test.startTest();
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(selection);
        Test.stopTest();

        Id deviceId = product(DEVICE_CODE).Id;
        Id pricebookId = testPricebook().Id;
        QuoteLineItem before = [
            SELECT Id, UnitPrice, ListPrice
            FROM QuoteLineItem
            WHERE QuoteId = :result.quoteId AND Product2Id = :deviceId
            LIMIT 1
        ];
        System.assertEquals(700.00, before.UnitPrice);
        System.assertEquals(1000.00, before.ListPrice);

        PricebookEntry entry = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id = :deviceId AND Pricebook2Id = :pricebookId
            LIMIT 1
        ];
        entry.UnitPrice = 1200;
        update entry;

        QuoteLineItem after = [
            SELECT UnitPrice
            FROM QuoteLineItem
            WHERE Id = :before.Id
        ];
        System.assertEquals(700.00, after.UnitPrice);
    }

    @IsTest
    static void commitmentOptionIsImmutable() {
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(baseSelection());

        QuoteLineItem line = [
            SELECT Id, Commitment_Option_Code__c
            FROM QuoteLineItem
            WHERE QuoteId = :result.quoteId
            LIMIT 1
        ];
        line.Commitment_Option_Code__c = 'COMMIT24';

        try {
            update line;
            System.assert(false, 'The commitment snapshot must be immutable.');
        } catch (DmlException error) {
            System.assert(
                error.getMessage().contains('snapshot'),
                error.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsNullSelection() {
        String message = createQuoteError(null);

        System.assert(
            message.contains('Offer selection is required'),
            message
        );
    }

    @IsTest
    static void rejectsUnsupportedOfferType() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.offerType = 'Television';

        String message = createQuoteError(selection);

        System.assert(message.contains('Unsupported offer type'), message);
    }

    @IsTest
    static void rejectsUnsupportedCommitment() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.commitmentCode = 'COMMIT99';

        String message = createQuoteError(selection);

        System.assert(
            message.contains('Unsupported commitment option'),
            message
        );
    }

    @IsTest
    static void rejectsSelectionWithoutAccountOrOpportunity() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.accountId = null;
        selection.opportunityId = null;
        selection.wizardSessionId = null;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('Account or opportunity is required'),
            message
        );
    }

    @IsTest
    static void rejectsPlanFromAnotherOfferType() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.planProductId = product(FIBER_CODE).Id;
        selection.offerType = 'Mobile';

        String message = createQuoteError(selection);

        System.assert(message.contains('not available'), message);
    }

    @IsTest
    static void rejectsDeviceFromAnotherFamily() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.deviceProductId = product(MOBILE_CODE).Id;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('device is not available'),
            message
        );
    }

    @IsTest
    static void rejectsWizardSessionMismatch() {
        Contact secondContact = new Contact(
            FirstName = 'Second',
            LastName = 'OfferBuilder',
            Email = 'second.offer.builder@example.com',
            AccountId = testAccount().Id
        );
        insert secondContact;

        OfferBuilderService.Selection selection = baseSelection();
        selection.contactId = secondContact.Id;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('wizard session does not belong'),
            message
        );
    }

    @IsTest
    static void createQuotesHandlesNullList() {
        System.assertEquals(
            0,
            OfferBuilderService.createQuotes(null).size()
        );
    }

    @IsTest
    static void createQuotesProcessesSelectionList() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.opportunityId = null;
        selection.wizardSessionId = null;
        selection.deviceProductId = null;

        Test.startTest();
        List<OfferBuilderService.OfferResult> results =
            OfferBuilderService.createQuotes(
                new List<OfferBuilderService.Selection>{ selection }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(1, results[0].lineCount);
        System.assertEquals(90.00, results[0].totalPrice);
    }

    @IsTest
    static void usesOpportunityAccountAndContact() {
        OfferBuilderService.Selection selection =
            new OfferBuilderService.Selection();
        selection.opportunityId = testOpportunity().Id;
        selection.offerType = 'Mobile';
        selection.planProductId = product(MOBILE_CODE).Id;
        selection.commitmentCode = 'COMMIT12';
        selection.effectiveDate = Date.today();

        Test.startTest();
        OfferBuilderService.OfferResult result =
            OfferBuilderService.createQuote(selection);
        Test.stopTest();

        Quote quote = [
            SELECT AccountId, ContactId, OpportunityId
            FROM Quote
            WHERE Id = :result.quoteId
        ];
        System.assertEquals(testAccount().Id, quote.AccountId);
        System.assertEquals(testContact().Id, quote.ContactId);
        System.assertEquals(testOpportunity().Id, quote.OpportunityId);
        System.assertEquals(1, result.lineCount);
    }

    @IsTest
    static void rejectsOpportunityFromAnotherAccount() {
        Account otherAccount = new Account(
            Name = 'Wrong Offer Account',
            Segment__c = 'Consumer'
        );
        insert otherAccount;

        OfferBuilderService.Selection selection = baseSelection();
        selection.accountId = otherAccount.Id;

        String message = createQuoteError(selection);

        System.assert(
            message.contains('opportunity does not belong'),
            message
        );
    }

    @IsTest
    static void rejectsMissingPlan() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.planProductId = null;

        String message = createQuoteError(selection);

        System.assert(message.contains('Plan product is required'), message);
    }

    @IsTest
    static void rejectsUnknownAccount() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.accountId = UserInfo.getUserId();
        selection.opportunityId = null;
        selection.wizardSessionId = null;

        String message = createQuoteError(selection);

        System.assert(message.contains('Account not found'), message);
    }

    @IsTest
    static void rejectsUnknownContact() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.contactId = UserInfo.getUserId();
        selection.opportunityId = null;
        selection.wizardSessionId = null;

        String message = createQuoteError(selection);

        System.assert(message.contains('Contact not found'), message);
    }

    @IsTest
    static void rejectsMissingOfferType() {
        OfferBuilderService.Selection selection = baseSelection();
        selection.offerType = null;

        String message = createQuoteError(selection);

        System.assert(message.contains('Offer type is required'), message);
    }
}
