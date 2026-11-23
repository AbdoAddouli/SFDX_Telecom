/** Non-PII input for one BSS status lookup. */
public class BssStatusRequest {
    public Id subscriptionId { get; set; }
    public String subscriptionNumber { get; set; }
    public String externalReference { get; set; }
    public String localStatus { get; set; }
    public String correlationId { get; set; }
}
