/**
 * Tests for SubscriptionMSISDNDuplicateHandler and
 * SubscriptionMSISDNTrigger.
 */
@IsTest
private class SubscriptionMSISDNDuplicateHandlerTest {
    private static final String MSISDN_A = '+33612345678';
    private static final String MSISDN_B = '+33687654321';

    private class Setup {
        Account account;
        Asset asset;
    }

    private static Setup setup() {
        Account a = new Account(Name = 'ATS MSISDN Duplicate Test');
        insert a;
        Asset ast = new Asset(Name = 'ATS MSISDN Test Asset', AccountId = a.Id);
        insert ast;
        Setup s = new Setup();
        s.account = a;
        s.asset = ast;
        return s;
    }

    private static Subscription__c sub(Setup s, String msisdn) {
        return new Subscription__c(
            Account__c = s.account.Id,
            Asset__c = s.asset.Id,
            Service_Line_Type__c = 'Mobile',
            Status__c = 'Active',
            MSISDN__c = msisdn
        );
    }

    @IsTest
    static void blankMsisdnNeverDuplicates() {
        Setup s = setup();
        List<Subscription__c> rows = new List<Subscription__c> {
            sub(s, null), sub(s, null), sub(s, ''), sub(s, '   ')
        };
        Test.startTest();
        Database.SaveResult[] results = Database.insert(rows, false);
        Test.stopTest();
        for (Database.SaveResult r : results) {
            System.assert(r.isSuccess(), 'Blank MSISDN must never be treated as a duplicate');
        }
    }

    @IsTest
    static void duplicateInsertIsBlocked() {
        Setup s = setup();
        Subscription__c first = sub(s, MSISDN_A);
        insert first;

        Subscription__c dup = sub(s, MSISDN_A);
        Database.SaveResult result = Database.insert(dup, false);
        Test.startTest();
        Test.stopTest();
        System.assert(!result.isSuccess(), 'Duplicate insert must fail');
        System.assert(
            result.getErrors()[0].getMessage().contains('already exists'),
            'Duplicate message must be friendly'
        );
        System.assert(
            [SELECT COUNT() FROM Subscription__c WHERE MSISDN__c = :MSISDN_A] == 1,
            'Only one subscription may hold the MSISDN'
        );
    }

    @IsTest
    static void duplicateUpdateIsBlocked() {
        Setup s = setup();
        Subscription__c first = sub(s, MSISDN_A);
        Subscription__c second = sub(s, MSISDN_B);
        insert first;
        insert second;

        second.MSISDN__c = MSISDN_A;
        Database.SaveResult result = Database.update(second, false);
        Test.startTest();
        Test.stopTest();
        System.assert(!result.isSuccess(), 'Duplicate update must fail');
        System.assert(
            result.getErrors()[0].getMessage().contains('already exists'),
            'Duplicate update message must be friendly'
        );
    }

    @IsTest
    static void whitespaceVariantIsBlocked() {
        Setup s = setup();
        Subscription__c first = sub(s, MSISDN_A);
        insert first;

        Subscription__c dup = sub(s, ' ' + MSISDN_A + ' ');
        Database.SaveResult result = Database.insert(dup, false);
        Test.startTest();
        Test.stopTest();
        System.assert(!result.isSuccess(), 'Whitespace variant must be blocked before the format rule');
    }

    @IsTest
    static void keepingOwnMsisdnIsAllowed() {
        Setup s = setup();
        Subscription__c first = sub(s, MSISDN_A);
        insert first;

        first.Status__c = 'Suspended';
        Database.SaveResult result = Database.update(first, false);
        Test.startTest();
        Test.stopTest();
        System.assert(result.isSuccess(), 'Updating a record without changing its MSISDN must succeed');
    }

    @IsTest
    static void clearingMsisdnIsAllowed() {
        Setup s = setup();
        Subscription__c first = sub(s, MSISDN_A);
        insert first;

        first.MSISDN__c = null;
        Database.SaveResult result = Database.update(first, false);
        Test.startTest();
        Test.stopTest();
        System.assert(result.isSuccess(), 'Clearing the MSISDN must succeed');
    }

    @IsTest
    static void bulkInsertIsBulkSafe() {
        Setup s = setup();
        List<Subscription__c> rows = new List<Subscription__c>();
        String digits = null;
        for (Integer i = 0; i < 50; i++) {
            digits = '61234567' + String.valueOf(10 + i);
            if (digits.length() > 15) {
                digits = digits.substring(0, 15);
            }
            rows.add(sub(s, digits));
        }
        rows.add(sub(s, digits));
        Test.startTest();
        Database.SaveResult[] results = Database.insert(rows, false);
        Test.stopTest();
        Integer failures = 0;
        for (Database.SaveResult r : results) {
            if (!r.isSuccess()) {
                failures++;
                System.assert(
                    r.getErrors()[0].getMessage().contains('already exists'),
                    'Bulk failure must be the friendly duplicate message'
                );
            }
        }
        System.assert(failures == 1, 'Expected exactly one duplicate failure');
        System.assert(
            [SELECT COUNT() FROM Subscription__c] == 50,
            '50 unique rows must save; the duplicate must not'
        );
    }
}
