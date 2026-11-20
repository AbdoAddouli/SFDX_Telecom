@IsTest
private class RenewalOutreachServiceTest {
    private static Integer uniqueIndex = 0;

    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
    }

    @IsTest
    static void t60TaskIsCreatedOnceAndMarksEngagementContacted() {
        Fixture fixture = createFixture(45, false);

        Test.startTest();
        Database.executeBatch(new RenewalOutreachBatch(), 200);
        Database.executeBatch(new RenewalOutreachBatch(), 200);
        Test.stopTest();

        List<Task> tasks = [
            SELECT Subject, WhatId
            FROM Task
            WHERE WhatId = :fixture.engagement.Id
        ];
        System.assertEquals(1, tasks.size());
        System.assert(tasks[0].Subject.startsWith('Renewal T-60'));
        System.assertEquals(
            true,
            [
                SELECT Renewal_Contacted__c
                FROM Engagement__c
                WHERE Id = :fixture.engagement.Id
            ].Renewal_Contacted__c
        );
    }

    @IsTest
    static void t30AndT7StagesCreateDistinctTasks() {
        Fixture offer = createFixture(20, false);
        Fixture escalation = createFixture(5, false);

        Test.startTest();
        Database.executeBatch(new RenewalOutreachBatch(), 200);
        Test.stopTest();

        List<Task> offerTasks = [
            SELECT Subject, Priority
            FROM Task
            WHERE WhatId = :offer.engagement.Id
        ];
        System.assertEquals(1, offerTasks.size());
        System.assert(offerTasks[0].Subject.startsWith('Renewal T-30'));

        List<Task> escalationTasks = [
            SELECT Subject, Priority
            FROM Task
            WHERE WhatId = :escalation.engagement.Id
        ];
        System.assertEquals(1, escalationTasks.size());
        System.assert(escalationTasks[0].Subject.startsWith('Renewal T-7'));
        System.assertEquals('High', escalationTasks[0].Priority);
    }

    @IsTest
    static void dncContactGetsEmailOnlyTask() {
        Fixture fixture = createFixture(30, true);

        Test.startTest();
        Database.executeBatch(new RenewalOutreachBatch(), 200);
        Test.stopTest();

        Task task = [
            SELECT Subject, Description
            FROM Task
            WHERE WhatId = :fixture.engagement.Id
            LIMIT 1
        ];
        System.assert(task.Subject.contains('Email only (DNC)'));
        System.assert(task.Description.contains('no phone contact'));
        System.assertEquals(false, task.Subject.toLowerCase().contains('call'));
    }

    @IsTest
    static void engagementOutsideWindowIsIgnored() {
        Fixture fixture = createFixture(90, false);

        Test.startTest();
        Database.executeBatch(new RenewalOutreachBatch(), 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Task
                WHERE WhatId = :fixture.engagement.Id
            ]
        );
        System.assertEquals(
            false,
            [
                SELECT Renewal_Contacted__c
                FROM Engagement__c
                WHERE Id = :fixture.engagement.Id
            ].Renewal_Contacted__c
        );
    }

    private static Fixture createFixture(
        Integer daysToRenewal,
        Boolean doNotCall
    ) {
        uniqueIndex++;
        String suffix = String.valueOf(uniqueIndex);
        Fixture fixture = new Fixture();
        fixture.account = new Account(
            Name = 'Renewal Outreach ' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '7500' + suffix
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Outreach' + suffix,
            AccountId = fixture.account.Id,
            Do_Not_Call__c = doNotCall
        );
        insert fixture.contact;

        Product2 productRecord = new Product2(
            Name = 'Outreach Plan ' + suffix,
            ProductCode = 'REN_OUT_' + suffix,
            ATS_Product_Code__c = 'REN_OUT_' + suffix,
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true
        );
        insert productRecord;

        Asset assetRecord = new Asset(
            Name = 'Outreach Asset ' + suffix,
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = productRecord.Id,
            Monthly_Amount__c = 29.99,
            Billing_Start_Date__c = Date.today().addMonths(-12),
            Billing_End_Date__c = Date.today().addDays(daysToRenewal),
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Asset__c = assetRecord.Id,
            Start_Date__c = Date.today().addMonths(-12),
            End_Date__c = Date.today().addDays(daysToRenewal),
            Duration_Months__c = 12,
            Monthly_Amount__c = 29.99,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = SubscriptionStateMachine.ACTIVE;
        update fixture.subscription;
        return fixture;
    }
}
