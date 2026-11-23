trigger ServiceActivatedEventTrigger on Service_Activated__e (after insert) {
    ServiceActivatedEventHandler.handle(Trigger.new);
}
