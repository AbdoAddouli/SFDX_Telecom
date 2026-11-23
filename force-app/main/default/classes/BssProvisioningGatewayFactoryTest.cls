@IsTest
private class BssProvisioningGatewayFactoryTest {
    @IsTest
    static void usesSimulatedGatewayByDefault() {
        BssProvisioningGateway gateway = BssProvisioningGatewayFactory.create();
        System.assert(
            gateway instanceof SimulatedBssProvisioningGateway,
            'The flag-off default must remain the simulated gateway.'
        );
    }

    @IsTest
    static void selectsRealGatewayWhenLiveRequested() {
        BssProvisioningGateway gateway =
            BssProvisioningGatewayFactory.create(true);
        System.assert(
            gateway instanceof RealBssProvisioningGateway,
            'The cutover seam must select the real gateway when requested.'
        );
    }

    @IsTest
    static void realGatewayBuildsNonPiiRequest() {
        RealBssProvisioningGateway gateway =
            new RealBssProvisioningGateway();
        BssProvisioningRequest request = sampleRequest();

        ExternalApiService.Request apiRequest =
            gateway.buildRequest(request);

        System.assertEquals('Bss_Provisioning', apiRequest.apiName);
        System.assertEquals('POST', apiRequest.method);
        System.assertEquals('provision', apiRequest.path);
        System.assertEquals(request.correlationId, apiRequest.correlationId);
        System.assertEquals(request.idempotencyKey, apiRequest.idempotencyKey);
        System.assertEquals(request.subscriptionId, apiRequest.subscriptionId);
        System.assertEquals(request.orderId, apiRequest.orderId);
        System.assertEquals('BSS', apiRequest.systemName);
        System.assertEquals('provision', apiRequest.operation);

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(apiRequest.body);
        System.assert(!body.containsKey('accountName'));
        System.assertEquals(request.subscriptionNumber, body.get('subscriptionNumber'));
        System.assertEquals(request.productCode, body.get('productCode'));
    }

    @IsTest
    static void realGatewayMapsSuccessResponse() {
        RealBssProvisioningGateway gateway =
            new RealBssProvisioningGateway();
        BssProvisioningRequest request = sampleRequest();
        ExternalApiService.Response apiResponse =
            new ExternalApiService.Response();
        apiResponse.statusCode = 200;
        apiResponse.durationMs = 42;
        apiResponse.endpoint = 'https://bss.example.invalid/provision';
        apiResponse.body = '{"success":true,"externalReference":"BSS-1",'
            + '"statusCode":"200","message":"ok"}';

        BssProvisioningResponse response =
            gateway.mapResponse(request, apiResponse);

        System.assertEquals(request.subscriptionId, response.subscriptionId);
        System.assertEquals(true, response.success);
        System.assertEquals('BSS-1', response.externalReference);
        System.assertEquals('200', response.statusCode);
        System.assertEquals('ok', response.message);
        System.assertEquals(42, response.durationMs);
        System.assertEquals(apiResponse.endpoint, response.endpoint);
    }

    @IsTest
    static void realGatewayFailsClosedOnBlankResponse() {
        RealBssProvisioningGateway gateway =
            new RealBssProvisioningGateway();
        ExternalApiService.Response apiResponse =
            new ExternalApiService.Response();

        BssProvisioningResponse response =
            gateway.mapResponse(sampleRequest(), apiResponse);

        System.assertEquals(false, response.success);
        System.assertEquals(
            'BSS returned an empty response body.',
            response.message
        );
    }

    private static BssProvisioningRequest sampleRequest() {
        BssProvisioningRequest request = new BssProvisioningRequest();
        request.orderId = (Id) (
            Order.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
        );
        request.orderItemId = (Id) (
            OrderItem.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
        );
        request.subscriptionId = (Id) (
            Subscription__c.SObjectType.getDescribe().getKeyPrefix()
            + '000000000000'
        );
        request.subscriptionNumber = 'SUB-E8-SCAFFOLD';
        request.idempotencyKey = 'SUB-E8-SCAFFOLD';
        request.correlationId = 'e8-scaffold-correlation';
        request.productCode = 'E8_MOBILE';
        request.serviceLineType = 'Mobile';
        request.accountName = 'DO NOT SEND - SENSITIVE CUSTOMER';
        return request;
    }
}
