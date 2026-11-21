/** Generates 36-character correlation IDs for integration audit rows. */
public class IntegrationCorrelation {
    public static String next() {
        String hex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-'
            + hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-'
            + hex.substring(20, 32);
    }
}
