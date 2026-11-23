@IsTest
private class ProductImageSyncTest {
    @TestSetup
    static void createFixture() {
        insert new ATS_Feature_Flags__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            External_Api_Enabled__c = true,
            Product_Image_Live__c = false
        );
        insert new Product2(
            Name = 'E8 Image Test Product',
            IsActive = true,
            ATS_Product_Code__c = 'E8IMG-1'
        );
    }

    @IsTest
    static void flagDefaultsOff() {
        ProductImageSyncBatch.liveOverride = null;
        ProductImageSyncBatch.responseOverride = null;
        System.assertEquals(false, ProductImageSyncBatch.isLive());
    }

    @IsTest
    static void flagOffSkipsCalloutAndCachedWrite() {
        ProductImageSyncBatch.liveOverride = false;
        ProductImageSyncBatch.responseOverride = null;
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        Database.executeBatch(new ProductImageSyncBatch(), 200);
        Test.stopTest();

        Product2 product = product();
        System.assertEquals(null, product.Device_Image_URL__c);
    }

    @IsTest
    static void liveBatchCachesImageUrlWithoutPii() {
        ProductImageSyncBatch.liveOverride = true;
        ExternalApiService.Response apiResponse =
            new ExternalApiService.Response();
        apiResponse.statusCode = 200;
        apiResponse.correlationId = 'e8-image-sync';
        apiResponse.body = '[{"productCode":"E8IMG-1",'
            + '"imageUrl":"https://images.example.invalid/e8img1.png"}]';
        ProductImageSyncBatch.responseOverride = apiResponse;

        ExternalApiService.Request request =
            new ProductImageSyncBatch().buildRequest(
                new List<String>{ 'E8IMG-1' }
            );
        System.assertEquals('Product_Image', request.apiName);
        System.assert(request.body.contains('E8IMG-1'));
        System.assert(!request.body.contains('MSISDN'));
        System.assert(!request.body.contains('accountName'));

        Test.startTest();
        Database.executeBatch(new ProductImageSyncBatch(), 200);
        Test.stopTest();
        Test.getEventBus().deliver();

        Product2 product = product();
        System.assertEquals(
            'https://images.example.invalid/e8img1.png',
            product.Device_Image_URL__c
        );
    }

    private static Product2 product() {
        return [
            SELECT Id, ATS_Product_Code__c, Device_Image_URL__c
            FROM Product2
            WHERE ATS_Product_Code__c = 'E8IMG-1'
            LIMIT 1
        ];
    }

    private class FailingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(false, 'No callout is allowed while the flag is off.');
            return null;
        }
    }
}
