/** E8 replacement point for the device IMEI swap callout. */
public interface BssEquipmentSwapGateway {
    List<BssProvisioningResponse> swap(List<BssEquipmentSwapRequest> requests);
}
