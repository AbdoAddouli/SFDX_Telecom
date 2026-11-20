/**
 * BSS request payload for a port request or confirmed port application.
 */
public with sharing class BssPortabilityRequest {
    public Id subscriptionId { get; set; }
    public String subscriptionNumber { get; set; }
    public String idempotencyKey { get; set; }
    public String correlationId { get; set; }
    public String msisdn { get; set; }
    public String direction { get; set; }
    public String requestReference { get; set; }
    public String confirmationReference { get; set; }
}
