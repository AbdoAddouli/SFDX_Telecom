/**
 * Raised when the BSS rejects a provisioning request. ActivationService
 * catches it, rolls back the whole order transaction, and returns the Order
 * to Ready with a friendly failure reason.
 */
public class BssProvisioningException extends Exception {
}
