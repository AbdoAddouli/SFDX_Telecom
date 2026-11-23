/**
 * UC-INT-07: sanitised Change Data Capture subscriber scaffold.
 *
 * CDC object enablement is a Setup (CdcObjectEnablement) change and cannot be
 * deployed from source in this org. These triggers are inert until that Setup
 * step is done and CDC_Reporting_Live__c is enabled. Only fields in the explicit
 * allowlists below are ever read from a change event; MSISDN, contact, account,
 * free-text and location fields are deliberately excluded.
 */
public with sharing class CdcReportingService {
    private static final Map<String, List<String>> ALLOWED_FIELDS =
        new Map<String, List<String>>{
            'Subscription__c' => new List<String>{
                'Id', 'Status__c', 'Service_Line_Type__c',
                'ProductClassification__c', 'Monthly_Amount__c',
                'Is_Committed__c', 'Termination_Date__c',
                'Next_Renewal_Date__c', 'Activation_Date__c'
            },
            'Engagement__c' => new List<String>{
                'Id', 'Status__c', 'Start_Date__c', 'Planned_End_Date__c',
                'End_Date__c', 'Duration_Months__c', 'Monthly_Amount__c',
                'Months_Remaining__c', 'Early_Termination_Fee__c',
                'Breach_Amount__c', 'Renewal_Contacted__c',
                'Renewal_Contacted_On__c'
            },
            'Customer_Request__c' => new List<String>{
                'Id', 'Status__c', 'Request_Type__c', 'Priority__c',
                'Channel__c', 'Due_Date__c', 'Completed_On__c',
                'Approved_On__c', 'Calculated_Fee__c',
                'Is_Compliant_Request__c', 'Cancellation_Effective_Date__c',
                'Port_Direction__c'
            },
            'Eligibility__c' => new List<String>{
                'Id', 'Fiber_Available__c', 'Max_Downstream_Mbps__c',
                'Max_Upstream_Mbps__c', 'Technologies__c', 'Is_Active__c',
                'Last_Synced_On__c', 'Earliest_Activation_Date__c',
                'Source_System__c', 'Region__c'
            },
            'Asset' => new List<String>{
                'Id', 'Status', 'Product2Id', 'Provisioned_Status__c',
                'Service_Line_Type__c', 'Is_Primary__c'
            }
        };

    @TestVisible
    private static Boolean liveOverride;

    /** One sanitised audit event per trigger batch, never per row. */
    public static void handle(List<SObject> events, String objectName) {
        if (!isLive() || events == null || events.isEmpty()) {
            return;
        }

        IntegrationLogService.LogInput input =
            new IntegrationLogService.LogInput();
        input.systemName = 'CDC';
        input.operation = 'CDC.' + objectName;
        input.status = 'Success';
        input.inbound = true;
        input.payloadSummary = 'events=' + events.size()
            + '; sample=' + JSON.serialize(allowedValues(events[0], objectName));
        IntegrationLogService.publish(input);
    }

    @TestVisible
    static Map<String, Object> allowedValues(SObject record, String objectName) {
        Map<String, Object> values = new Map<String, Object>();
        List<String> fields = ALLOWED_FIELDS.get(objectName);
        if (record == null || fields == null) {
            return values;
        }
        for (String field : fields) {
            try {
                values.put(field, record.get(field));
            } catch (Exception ignored) {
                // A field can be absent from a specific change-event payload.
            }
        }
        return values;
    }

    @TestVisible
    static Boolean isLive() {
        if (liveOverride != null) {
            return liveOverride;
        }
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        return flags != null && flags.CDC_Reporting_Live__c == true;
    }
}
