/**
 * A user-safe activation failure. The message is written to
 * Order.Failure_Reason__c and the audit log, so it must never contain a stack
 * trace or internal implementation detail.
 */
public class ActivationException extends Exception {
}
