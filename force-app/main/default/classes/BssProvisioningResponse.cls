/**
 * BSS response for one subscription. ExternalReference is the BSS-side key;
 * MSISDN and LineNumber are persisted on the Subscription when returned.
 */
public class BssProvisioningResponse {
    public Id subscriptionId { get; set; }
    public Boolean success { get; set; }
    public String externalReference { get; set; }
    public String msisdn { get; set; }
    public String lineNumber { get; set; }
    public String statusCode { get; set; }
    public String message { get; set; }
    public Integer durationMs { get; set; }
    public String endpoint { get; set; }
}
