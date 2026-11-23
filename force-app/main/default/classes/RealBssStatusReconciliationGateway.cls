/**
 * Placeholder for the real BSS status lookup. Unreachable while
 * BSS_Status_Live__c is false. Supply the BSS_Api endpoint/auth and update
 * External_Api__mdt.Bss_Status before enabling the flag.
 *
 * Only subscription numbers and external references are sent. No MSISDN,
 * account name, or other customer PII leaves Salesforce.
 */
public with sharing class RealBssStatusReconciliationGateway
    implements BssStatusReconciliationGateway {
    private static final String API_NAME = 'Bss_Status';
    private static final String PATH = 'status';
    private static final String OPERATION = 'reconcileStatus';
    private static final String SYSTEM_NAME = 'BSS';

    public List<BssStatusResponse> status(List<BssStatusRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<BssStatusResponse>();
        }
        ExternalApiService.Response apiResponse =
            ExternalApiService.callout(buildRequest(requests));
        return mapResponses(requests, apiResponse);
    }

    @TestVisible
    ExternalApiService.Request buildRequest(List<BssStatusRequest> requests) {
        List<Map<String, String>> items = new List<Map<String, String>>();
        for (BssStatusRequest request : requests) {
            items.add(new Map<String, String>{
                'subscriptionNumber' => request.subscriptionNumber,
                'externalReference' => request.externalReference
            });
        }

        ExternalApiService.Request apiRequest =
            new ExternalApiService.Request();
        apiRequest.apiName = API_NAME;
        apiRequest.method = 'POST';
        apiRequest.path = PATH;
        apiRequest.headers = new Map<String, String>{
            'Content-Type' => 'application/json'
        };
        apiRequest.body = JSON.serialize(new Map<String, Object>{
            'subscriptions' => items
        });
        apiRequest.correlationId = requests[0].correlationId;
        apiRequest.operation = OPERATION;
        apiRequest.systemName = SYSTEM_NAME;
        return apiRequest;
    }

    @TestVisible
    List<BssStatusResponse> mapResponses(
        List<BssStatusRequest> requests,
        ExternalApiService.Response apiResponse
    ) {
        List<BssStatusResponse> responses =
            new List<BssStatusResponse>();
        Map<String, BssStatusRequest> byNumber =
            new Map<String, BssStatusRequest>();
        for (BssStatusRequest request : requests) {
            byNumber.put(request.subscriptionNumber, request);
        }

        if (apiResponse == null || String.isBlank(apiResponse.body)) {
            return failAll(requests, apiResponse,
                'BSS returned an empty status response.');
        }

        List<BssStatusPayload> payloads;
        try {
            payloads = (List<BssStatusPayload>) JSON.deserialize(
                apiResponse.body,
                List<BssStatusPayload>.class
            );
        } catch (Exception error) {
            return failAll(requests, apiResponse,
                'BSS returned an unreadable status response.');
        }

        for (BssStatusPayload payload : payloads) {
            BssStatusRequest request =
                byNumber.get(payload.subscriptionNumber);
            if (request == null) {
                continue;
            }
            BssStatusResponse response = new BssStatusResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = payload.success == true;
            response.externalStatus = payload.externalStatus;
            response.statusCode = String.isBlank(payload.statusCode)
                ? (apiResponse.statusCode == null
                    ? null
                    : String.valueOf(apiResponse.statusCode))
                : payload.statusCode;
            response.message = payload.message;
            response.durationMs = apiResponse.durationMs;
            response.endpoint = apiResponse.endpoint;
            responses.add(response);
            byNumber.remove(payload.subscriptionNumber);
        }

        for (BssStatusRequest missing : byNumber.values()) {
            BssStatusResponse response = new BssStatusResponse();
            response.subscriptionId = missing.subscriptionId;
            response.success = false;
            response.message = 'BSS status response missed a subscription.';
            response.durationMs = apiResponse.durationMs;
            response.endpoint = apiResponse.endpoint;
            responses.add(response);
        }
        return responses;
    }

    private static List<BssStatusResponse> failAll(
        List<BssStatusRequest> requests,
        ExternalApiService.Response apiResponse,
        String message
    ) {
        List<BssStatusResponse> responses =
            new List<BssStatusResponse>();
        for (BssStatusRequest request : requests) {
            BssStatusResponse response = new BssStatusResponse();
            response.subscriptionId = request.subscriptionId;
            response.success = false;
            response.message = message;
            response.durationMs = apiResponse == null
                ? 0
                : apiResponse.durationMs;
            response.endpoint = apiResponse == null
                ? null
                : apiResponse.endpoint;
            responses.add(response);
        }
        return responses;
    }

    private class BssStatusPayload {
        String subscriptionNumber;
        String externalStatus;
        Boolean success;
        String statusCode;
        String message;
    }
}
