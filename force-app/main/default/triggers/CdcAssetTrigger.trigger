trigger CdcAssetTrigger on AssetChangeEvent (after insert) {
    CdcReportingService.handle(Trigger.new, 'Asset');
}
