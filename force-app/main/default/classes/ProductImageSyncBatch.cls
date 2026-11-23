/**
 * UC-INT-05: batch-populate Product2.Device_Image_URL__c from the image API.
 *
 * The live path is flag-off. Runtime pages and datatables only read the cached
 * field, so no callout ever happens during a render. A failed sync leaves the
 * last good URL untouched.
 */
public with sharing class ProductImageSyncBatch
    implements Database.Batchable<SObject>, Database.Stateful {
    private static final String API_NAME = 'Product_Image';
    private static final String PATH = 'images';
    private static final String OPERATION = 'syncImages';
    private static final String SYSTEM_NAME = 'ProductImage';

    @TestVisible
    private static Boolean liveOverride;

    @TestVisible
    private static ExternalApiService.Response responseOverride;

    @TestVisible
    private Integer updatedCount = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (!isLive()) {
            return Database.getQueryLocator([
                SELECT Id
                FROM Product2
                WHERE Id IN :new Set<Id>()
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, ATS_Product_Code__c, Device_Image_URL__c
            FROM Product2
            WHERE IsActive = true AND ATS_Product_Code__c != NULL
            ORDER BY ATS_Product_Code__c
        ]);
    }

    public void execute(
        Database.BatchableContext context,
        List<Product2> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<String> productCodes = new List<String>();
        for (Product2 product : scope) {
            if (String.isNotBlank(product.ATS_Product_Code__c)) {
                productCodes.add(product.ATS_Product_Code__c);
            }
        }
        if (productCodes.isEmpty()) {
            return;
        }

        ExternalApiService.Response apiResponse;
        try {
            apiResponse = responseOverride != null
                ? responseOverride
                : ExternalApiService.callout(buildRequest(productCodes));
        } catch (ExternalApiException error) {
            logFailure(null, error.getMessage(), null);
            return;
        }

        Map<String, String> urlsByCode;
        try {
            urlsByCode = parseUrls(apiResponse.body);
        } catch (Exception error) {
            logFailure(apiResponse.correlationId,
                'Product image response was unreadable.', error);
            return;
        }

        List<Product2> updates = new List<Product2>();
        for (Product2 product : scope) {
            String url = urlsByCode.get(product.ATS_Product_Code__c);
            if (String.isBlank(url)) {
                continue;
            }
            updates.add(new Product2(
                Id = product.Id,
                Device_Image_URL__c = url.left(255)
            ));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
            updatedCount += updates.size();
        }
    }

    public void finish(Database.BatchableContext context) {
        IntegrationLogService.LogInput summary =
            new IntegrationLogService.LogInput();
        summary.systemName = SYSTEM_NAME;
        summary.operation = 'ProductImageSyncSummary';
        summary.status = 'Success';
        summary.payloadSummary = 'cached=' + updatedCount;
        IntegrationLogService.publish(summary);
    }

    @TestVisible
    ExternalApiService.Request buildRequest(List<String> productCodes) {
        ExternalApiService.Request request =
            new ExternalApiService.Request();
        request.apiName = API_NAME;
        request.method = 'POST';
        request.path = PATH;
        request.headers = new Map<String, String>{
            'Content-Type' => 'application/json'
        };
        request.body = JSON.serialize(new Map<String, Object>{
            'productCodes' => productCodes
        });
        request.operation = OPERATION;
        request.systemName = SYSTEM_NAME;
        return request;
    }

    @TestVisible
    Map<String, String> parseUrls(String body) {
        Map<String, String> urls = new Map<String, String>();
        if (String.isBlank(body)) {
            return urls;
        }
        List<ImagePayload> payloads = (List<ImagePayload>) JSON.deserialize(
            body,
            List<ImagePayload>.class
        );
        for (ImagePayload payload : payloads) {
            if (String.isNotBlank(payload.productCode)
                && String.isNotBlank(payload.imageUrl)) {
                urls.put(payload.productCode, payload.imageUrl);
            }
        }
        return urls;
    }

    @TestVisible
    static Boolean isLive() {
        if (liveOverride != null) {
            return liveOverride;
        }
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return flags != null && flags.Product_Image_Live__c == true;
    }

    private static void logFailure(
        String correlationId,
        String message,
        Exception error
    ) {
        IntegrationLogService.LogInput input =
            new IntegrationLogService.LogInput();
        input.correlationId = correlationId;
        input.systemName = SYSTEM_NAME;
        input.operation = OPERATION;
        input.status = 'Failure';
        input.errorMessage = message;
        input.errorStack = error == null ? null : error.getStackTraceString();
        IntegrationLogService.publish(input);
    }

    private class ImagePayload {
        String productCode;
        String imageUrl;
    }
}
