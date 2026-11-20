/**
 * Signals a failed UC-LIF-07 phase. Callers convert it to a Flow-friendly
 * result and never leak raw exception text to the UI.
 */
public with sharing class PortabilityException extends Exception {
}
