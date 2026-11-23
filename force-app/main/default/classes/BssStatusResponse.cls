/** BSS-side status for one subscription. */
public class BssStatusResponse {
    public Id subscriptionId { get; set; }
    public String externalStatus { get; set; }
    public Boolean success { get; set; }
    public String statusCode { get; set; }
    public String message { get; set; }
    public Decimal durationMs { get; set; }
    public String endpoint { get; set; }
}
