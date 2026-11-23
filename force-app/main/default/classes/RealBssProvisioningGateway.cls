/**
 * Placeholder for the real BSS provisioning callout.
 *
 * This class is intentionally unreachable while BSS_Provisioning_Live__c is
 * false. It uses ExternalApiService (never a direct Http call), sends only
 * non-PII identifiers/product data, and maps the BSS response into the
 * existing gateway DTO. Supply the BSS_Api endpoint/auth and the
 * Bss_Provisioning metadata before enabling the flag.
 */
public with sharing class RealBssProvisioningGateway
    implements BssProvisioningGateway {
    private static final String API_NAME = 'Bss_Provisioning';
    private static final String PATH = 'provision';
    private static final String OPERATION = 'provision';
    private static final String SYSTEM_NAME = 'BSS';

    public List<BssProvisioningResponse> provision(
        List<BssProvisioningRequest> requests
    ) {
        List<BssProvisioningResponse> responses =
            new List<BssProvisioningResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        for (BssProvisioningRequest request : requests) {
            ExternalApiService.Response apiResponse =
                ExternalApiService.callout(buildRequest(request));
            responses.add(mapResponse(request, apiResponse));
        }
        return responses;
    }

    @TestVisible
    ExternalApiService.Request buildRequest(BssProvisioningRequest request) {
        Map<String, Object> body = new Map<String, Object>{
            'subscriptionNumber' => request.subscriptionNumber,
            'productCode' => request.productCode,
            'serviceLineType' => request.serviceLineType,
            'idempotencyKey' => request.idempotencyKey
        };

        ExternalApiService.Request apiRequest =
            new ExternalApiService.Request();
        apiRequest.apiName = API_NAME;
        apiRequest.method = 'POST';
        apiRequest.path = PATH;
        apiRequest.headers = new Map<String, String>{
            'Content-Type' => 'application/json'
        };
        apiRequest.body = JSON.serialize(body);
        apiRequest.correlationId = request.correlationId;
        apiRequest.idempotencyKey = request.idempotencyKey;
        apiRequest.operation = OPERATION;
        apiRequest.systemName = SYSTEM_NAME;
        apiRequest.subscriptionId = request.subscriptionId;
        apiRequest.orderId = request.orderId;
        return apiRequest;
    }

    @TestVisible
    BssProvisioningResponse mapResponse(
        BssProvisioningRequest request,
        ExternalApiService.Response apiResponse
    ) {
        BssProvisioningResponse response = new BssProvisioningResponse();
        response.subscriptionId = request.subscriptionId;
        response.success = false;
        response.statusCode = apiResponse == null || apiResponse.statusCode == null
            ? null
            : String.valueOf(apiResponse.statusCode);
        response.durationMs = apiResponse == null || apiResponse.durationMs == null
            ? 0
            : apiResponse.durationMs.intValue();
        response.endpoint = apiResponse == null ? null : apiResponse.endpoint;

        if (apiResponse == null || String.isBlank(apiResponse.body)) {
            response.message = 'BSS returned an empty response body.';
            return response;
        }

        BssHttpResponse payload;
        try {
            payload = (BssHttpResponse) JSON.deserialize(
                apiResponse.body,
                BssHttpResponse.class
            );
        } catch (Exception error) {
            response.message = 'BSS returned an unreadable response body.';
            return response;
        }

        response.success = payload.success == true;
        response.externalReference = payload.externalReference;
        response.msisdn = payload.msisdn;
        response.lineNumber = payload.lineNumber;
        response.statusCode = String.isBlank(payload.statusCode)
            ? response.statusCode
            : payload.statusCode;
        response.message = payload.message;
        return response;
    }

    private class BssHttpResponse {
        Boolean success;
        String externalReference;
        String msisdn;
        String lineNumber;
        String statusCode;
        String message;
    }
}
