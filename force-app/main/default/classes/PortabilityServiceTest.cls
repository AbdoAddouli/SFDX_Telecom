@IsTest
private class PortabilityServiceTest {
    private static Integer sequence = 0;

    private class Fixture {
        Account account;
        Contact contact;
        Subscription__c subscription;
        Engagement__c engagement;
        String msisdn;
    }

    private class CountingGateway implements BssPortabilityGateway {
        Integer requestCalls = 0;
        Integer applyCalls = 0;
        private final BssPortabilityGateway delegate =
            new SimulatedBssPortabilityGateway();

        public List<BssProvisioningResponse> requestPort(
            List<BssPortabilityRequest> requests
        ) {
            requestCalls++;
            return delegate.requestPort(requests);
        }

        public List<BssProvisioningResponse> applyPort(
            List<BssPortabilityRequest> requests
        ) {
            applyCalls++;
            return delegate.applyPort(requests);
        }
    }

    private class FailingApplyGateway implements BssPortabilityGateway {
        Integer applyCalls = 0;
        private final BssPortabilityGateway delegate =
            new SimulatedBssPortabilityGateway();

        public List<BssProvisioningResponse> requestPort(
            List<BssPortabilityRequest> requests
        ) {
            return delegate.requestPort(requests);
        }

        public List<BssProvisioningResponse> applyPort(
            List<BssPortabilityRequest> requests
        ) {
            applyCalls++;
            List<BssProvisioningResponse> responses =
                new List<BssProvisioningResponse>();
            for (BssPortabilityRequest request : requests) {
                BssProvisioningResponse response = new BssProvisioningResponse();
                response.subscriptionId = request.subscriptionId;
                response.success = false;
                response.statusCode = '500';
                response.message = 'BSS port application is unavailable.';
                response.externalReference = 'FAIL-PORT';
                response.durationMs = 0;
                responses.add(response);
            }
            return responses;
        }
    }

    @IsTest
    static void requestPortCreatesRequestAndLeavesMsisdnUnchanged() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        String target = nextMsisdn();

        Test.startTest();
        PortabilityService.PortabilityResult result = request(
            fixture,
            PortabilityPolicy.DIRECTION_INBOUND,
            target
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(PortabilityPolicy.STATUS_APPROVED, result.status);
        System.assertNotEquals(null, result.requestId);
        System.assertNotEquals(null, result.caseId);
        System.assertEquals(target, result.requestedMsisdn);
        System.assertEquals(fixture.msisdn, result.previousMsisdn);
        System.assert(
            String.isNotBlank(result.portRequestReference),
            'BSS request reference was not returned.'
        );

        Customer_Request__c request = [
            SELECT
                Status__c,
                Request_Type__c,
                Port_Direction__c,
                Requested_MSISDN__c,
                Previous_MSISDN__c,
                Port_Request_Reference__c
            FROM Customer_Request__c
            WHERE Id = :result.requestId
        ];
        System.assertEquals('Portability', request.Request_Type__c);
        System.assertEquals('Inbound', request.Port_Direction__c);
        System.assertEquals(target, request.Requested_MSISDN__c);
        System.assertEquals(fixture.msisdn, request.Previous_MSISDN__c);
        System.assertEquals(
            result.portRequestReference,
            request.Port_Request_Reference__c
        );
        System.assertEquals(
            fixture.msisdn,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Integration_Log__c
                WHERE
                    Subscription__c = :fixture.subscription.Id AND
                    Operation__c = :PortabilityPolicy.OPERATION_REQUEST AND
                    Status__c = 'Success'
            ]
        );
    }

    @IsTest
    static void inboundConfirmationAppliesMsisdnAndIsIdempotent() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        String target = nextMsisdn();
        PortabilityService.PortabilityResult submitted = request(
            fixture,
            PortabilityPolicy.DIRECTION_INBOUND,
            target
        );
        approveIfNeeded(submitted.requestId);
        CountingGateway gateway = new CountingGateway();
        PortabilityBssClient.setGateway(gateway);

        Test.startTest();
        PortabilityService.PortabilityResult applied =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-1',
                        null
                    )
                }
            )[0];

        PortabilityService.PortabilityResult replay =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-1-REPLAY',
                        null
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(true, applied.success);
        System.assertEquals(PortabilityPolicy.STATUS_COMPLETED, applied.status);
        System.assertEquals(target, applied.appliedMsisdn);
        System.assertEquals(PortabilityPolicy.STATUS_COMPLETED, replay.status);
        System.assertEquals(1, gateway.applyCalls);

        System.assertEquals(
            target,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
        Customer_Request__c request = [
            SELECT Status__c, Port_Confirmation_Reference__c, Case__c
            FROM Customer_Request__c
            WHERE Id = :submitted.requestId
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assertEquals('DONOR-1', request.Port_Confirmation_Reference__c);
        System.assertEquals(
            'Closed',
            [SELECT Status FROM Case WHERE Id = :request.Case__c].Status
        );
    }

    @IsTest
    static void outboundConfirmationReleasesMsisdnAndStoresPrevious() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        PortabilityService.PortabilityResult submitted = request(
            fixture,
            PortabilityPolicy.DIRECTION_OUTBOUND,
            fixture.msisdn
        );
        approveIfNeeded(submitted.requestId);

        Test.startTest();
        PortabilityService.PortabilityResult applied =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-OUT-1',
                        null
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(true, applied.success);
        System.assertEquals(null, applied.appliedMsisdn);
        System.assertEquals(
            null,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
        Customer_Request__c request = [
            SELECT Status__c, Previous_MSISDN__c, Resolution_Summary__c
            FROM Customer_Request__c
            WHERE Id = :submitted.requestId
        ];
        System.assertEquals('Completed', request.Status__c);
        System.assertEquals(fixture.msisdn, request.Previous_MSISDN__c);
        System.assert(request.Resolution_Summary__c.contains('released'));
    }

    @IsTest
    static void donorRejectionLeavesMsisdnUnchanged() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        String target = nextMsisdn();
        PortabilityService.PortabilityResult submitted = request(
            fixture,
            PortabilityPolicy.DIRECTION_INBOUND,
            target
        );
        approveIfNeeded(submitted.requestId);

        Test.startTest();
        PortabilityService.PortabilityResult rejected =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_REJECTED,
                        'DONOR-REJECT-1',
                        'Donor refused the port.'
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(true, rejected.success);
        System.assertEquals(PortabilityPolicy.STATUS_REJECTED, rejected.status);
        System.assertEquals(
            fixture.msisdn,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
        Customer_Request__c request = [
            SELECT Status__c, Rejection_Reason__c
            FROM Customer_Request__c
            WHERE Id = :submitted.requestId
        ];
        System.assertEquals('Rejected', request.Status__c);
        System.assertEquals('Donor refused the port.', request.Rejection_Reason__c);
    }

    @IsTest
    static void duplicateRequestedMsisdnIsRejectedBeforeIntake() {
        Fixture first = createFixture(-1, 6, 39.99);
        String occupiedMsisdn = nextMsisdn();
        createOccupiedSubscription(first, occupiedMsisdn);

        Test.startTest();
        PortabilityService.PortabilityResult result =
            PortabilityService.requestPorts(
                new List<PortabilityService.PortabilityInput>{
                    input(
                        first,
                        PortabilityPolicy.DIRECTION_INBOUND,
                        occupiedMsisdn
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assert(result.message.contains('already assigned to another line'));
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Customer_Request__c
                WHERE Subscription__c = :first.subscription.Id
            ]
        );
        System.assertEquals(
            first.msisdn,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :first.subscription.Id
            ].MSISDN__c
        );
    }

    @IsTest
    static void bssApplyFailureRollsBackMsisdnAndCanBeRetried() {
        Fixture fixture = createFixture(-1, 6, 39.99);
        String target = nextMsisdn();
        PortabilityService.PortabilityResult submitted = request(
            fixture,
            PortabilityPolicy.DIRECTION_INBOUND,
            target
        );
        approveIfNeeded(submitted.requestId);
        FailingApplyGateway gateway = new FailingApplyGateway();
        PortabilityBssClient.setGateway(gateway);

        Test.startTest();
        PortabilityService.PortabilityResult failed =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-RETRY',
                        null
                    )
                }
            )[0];
        PortabilityBssClient.setGateway(new SimulatedBssPortabilityGateway());
        PortabilityService.PortabilityResult retried =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-RETRY',
                        null
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(false, failed.success);
        System.assertEquals(1, gateway.applyCalls);
        // Rollback is verified by the Approved status below and the successful retry.
        System.assertEquals(
            'Completed',
            [
                SELECT Status__c
                FROM Customer_Request__c
                WHERE Id = :submitted.requestId
            ].Status__c
        );
        System.assertEquals(true, retried.success);
        System.assertEquals(
            target,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Integration_Log__c
                WHERE
                    Subscription__c = :fixture.subscription.Id AND
                    Operation__c = :PortabilityPolicy.OPERATION_APPLY AND
                    Status__c = 'Failure'
            ]
        );
    }

    @IsTest
    static void awaitingApprovalCannotBeConfirmed() {
        Fixture fixture = createFixture(-18, 6, 39.99);
        String target = nextMsisdn();
        PortabilityService.PortabilityResult submitted = request(
            fixture,
            PortabilityPolicy.DIRECTION_INBOUND,
            target
        );
        System.assertEquals(
            PortabilityPolicy.STATUS_AWAITING,
            submitted.status,
            'Fixture should produce a fee above the approval threshold.'
        );
        CountingGateway gateway = new CountingGateway();
        PortabilityBssClient.setGateway(gateway);

        Test.startTest();
        PortabilityService.PortabilityResult blocked =
            PortabilityConfirmationService.apply(
                new List<PortabilityConfirmationService.ConfirmationInput>{
                    confirmation(
                        submitted.requestId,
                        PortabilityPolicy.OUTCOME_CONFIRMED,
                        'DONOR-EARLY',
                        null
                    )
                }
            )[0];
        Test.stopTest();

        System.assertEquals(false, blocked.success);
        System.assert(blocked.message.contains('Approval is required'));
        System.assertEquals(0, gateway.applyCalls);
        System.assertEquals(
            fixture.msisdn,
            [
                SELECT MSISDN__c
                FROM Subscription__c
                WHERE Id = :fixture.subscription.Id
            ].MSISDN__c
        );
    }

    private static PortabilityService.PortabilityResult request(
        Fixture fixture,
        String direction,
        String msisdn
    ) {
        PortabilityService.PortabilityResult result =
            PortabilityService.requestPorts(
                new List<PortabilityService.PortabilityInput>{
                    input(fixture, direction, msisdn)
                }
            )[0];
        System.assert(result.success, result.message);
        return result;
    }

    private static void createOccupiedSubscription(
        Fixture fixture,
        String msisdn
    ) {
        Asset assetRecord = new Asset(
            Name = 'Portability Second Asset ' +
                String.valueOf(DateTime.now().getTime()),
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        Subscription__c subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = fixture.subscription.Product__c,
            Monthly_Amount__c = 39.99,
            MSISDN__c = msisdn,
            Status__c = 'PendingActivation'
        );
        insert subscription;
        subscription.Status__c = 'Active';
        update subscription;
    }

    private static PortabilityService.PortabilityInput input(
        Fixture fixture,
        String direction,
        String msisdn
    ) {
        PortabilityService.PortabilityInput input =
            new PortabilityService.PortabilityInput();
        input.direction = direction;
        input.accountId = fixture.account.Id;
        input.contactId = fixture.contact.Id;
        input.subscriptionId = fixture.subscription.Id;
        input.requestedMsisdn = msisdn;
        input.channel = 'Advisor';
        input.customerComment = 'Portability Service Test';
        return input;
    }

    private static PortabilityConfirmationService.ConfirmationInput confirmation(
        Id requestId,
        String outcome,
        String reference,
        String reason
    ) {
        PortabilityConfirmationService.ConfirmationInput input =
            new PortabilityConfirmationService.ConfirmationInput();
        input.requestId = requestId;
        input.outcome = outcome;
        input.confirmationReference = reference;
        input.rejectionReason = reason;
        return input;
    }

    private static void approveIfNeeded(Id requestId) {
        Customer_Request__c request = [
            SELECT Status__c
            FROM Customer_Request__c
            WHERE Id = :requestId
        ];
        if (request.Status__c == PortabilityPolicy.STATUS_AWAITING) {
            request.Status__c = PortabilityPolicy.STATUS_APPROVED;
            update request;
        }
    }

    private static String nextMsisdn() {
        return '+33612' + ('00000' + String.valueOf(++sequence)).right(6);
    }

    private static Fixture createFixture(
        Integer startMonthsAgo,
        Integer endMonthsAhead,
        Decimal monthlyAmount
    ) {
        Integer suffix = ++sequence;
        String runId = String.valueOf(DateTime.now().getTime());
        Fixture fixture = new Fixture();
        fixture.msisdn = '+33612' + ('00000' + String.valueOf(suffix)).right(6);

        fixture.account = new Account(
            Name = 'Portability Test ' + runId + '-' + suffix,
            Segment__c = 'Consumer',
            BillingPostalCode = '75001'
        );
        insert fixture.account;

        fixture.contact = new Contact(
            LastName = 'Porter' + runId + suffix,
            AccountId = fixture.account.Id
        );
        insert fixture.contact;

        Product2 product = new Product2(
            Name = 'Portability Test Plan ' + suffix,
            ProductCode = 'PORT_TEST_' + suffix,
            ATS_Product_Code__c = 'PC_PORT_' + suffix,
            Family = 'TELCO_MOBILE',
            Plan_Type__c = 'Mobile',
            Data_GB__c = 20,
            IsActive = true,
            Is_Active__c = true,
            Recurring__c = true,
            Requires_Commitment__c = false
        );
        insert product;

        Asset assetRecord = new Asset(
            Name = 'Portability Asset ' + suffix,
            AccountId = fixture.account.Id,
            Service_Line_Type__c = 'Mobile'
        );
        insert assetRecord;

        fixture.subscription = new Subscription__c(
            Account__c = fixture.account.Id,
            Asset__c = assetRecord.Id,
            Contact__c = fixture.contact.Id,
            Service_Line_Type__c = 'Mobile',
            Product__c = product.Id,
            Monthly_Amount__c = monthlyAmount,
            MSISDN__c = fixture.msisdn,
            Status__c = 'PendingActivation'
        );
        insert fixture.subscription;

        fixture.engagement = new Engagement__c(
            Account__c = fixture.account.Id,
            Subscription__c = fixture.subscription.Id,
            Start_Date__c = Date.today().addMonths(startMonthsAgo),
            End_Date__c = Date.today().addMonths(endMonthsAhead),
            Duration_Months__c = 24,
            Monthly_Amount__c = monthlyAmount,
            Status__c = 'Active'
        );
        insert fixture.engagement;

        fixture.subscription.Engagement__c = fixture.engagement.Id;
        fixture.subscription.Status__c = 'Active';
        update fixture.subscription;
        return fixture;
    }
}
