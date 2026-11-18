/**
 * Outcome returned for one cancellation fulfilment row.
 */
public with sharing class CancellationFulfilmentResult {
    public Id requestId;
    public Boolean success;
    public String message;

    public CancellationFulfilmentResult() {
        success = false;
    }

    public void completed() {
        success = true;
        message = 'Cancellation fulfilled.';
    }

    public void failed(String messageText) {
        success = false;
        message = messageText;
    }
}
