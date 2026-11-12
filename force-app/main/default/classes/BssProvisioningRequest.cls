/**
 * One subscription to provision at the BSS. The subscription number is the
 * idempotency key sent to the BSS, so a retry cannot provision twice.
 */
public class BssProvisioningRequest {
    public Id orderId { get; set; }
    public Id orderItemId { get; set; }
    public Id subscriptionId { get; set; }
    public String subscriptionNumber { get; set; }
    public String idempotencyKey { get; set; }
    public String correlationId { get; set; }
    public String productCode { get; set; }
    public String serviceLineType { get; set; }
    public String accountName { get; set; }
}
