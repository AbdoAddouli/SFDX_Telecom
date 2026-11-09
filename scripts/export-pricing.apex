/**
 * ATS pricing export.
 *
 * Run:
 *   sf apex run --target-org abdo@telecom.com --file scripts/export-pricing.apex
 *
 * The script queries the three custom metadata types, writes one JSON file per
 * procedure, pricing rule, and configuration rule, computes a SHA-256 for every
 * file, and attaches the manifest plus all files as pricing-export.zip to the
 * running user.
 *
 * The CLI alternative scripts/export-pricing.ps1 writes the same logical layout
 * directly to pricing-export/ without email; use it when email deliverability is
 * not enabled in the org.
 */

List<Pricing_Procedure__mdt> procedures = [
    SELECT DeveloperName, MasterLabel, Procedure_Name__c, Step_Number__c,
        Step_Name__c, Apex_Class__c, On_Error__c, Active__c
    FROM Pricing_Procedure__mdt
    ORDER BY Procedure_Name__c, Step_Number__c
];

List<Pricing_Rule__mdt> rules = [
    SELECT DeveloperName, MasterLabel, Rule_Type__c, Product__c,
        Requires_Product__c, Commitment_Code__c, Segment__c,
        Adjustment_Type__c, Adjustment_Value__c, Priority__c,
        Effective_From__c, Effective_To__c, Active__c
    FROM Pricing_Rule__mdt
    ORDER BY DeveloperName
];

List<Config_Rule__mdt> configRules = [
    SELECT DeveloperName, MasterLabel, Rule_Kind__c, Product__c,
        Companion_Product__c, Applies_When_Commitment__c, Message__c,
        Severity__c, Active__c
    FROM Config_Rule__mdt
    ORDER BY DeveloperName
];

Map<String, List<Map<String, Object>>> procedureSteps =
    new Map<String, List<Map<String, Object>>>();

for (Pricing_Procedure__mdt procedure : procedures) {
    Map<String, Object> step = new Map<String, Object>{
        'developerName' => procedure.DeveloperName,
        'label' => procedure.MasterLabel,
        'procedureName' => procedure.Procedure_Name__c,
        'stepNumber' => procedure.Step_Number__c,
        'stepName' => procedure.Step_Name__c,
        'apexClass' => procedure.Apex_Class__c,
        'onError' => procedure.On_Error__c,
        'active' => procedure.Active__c
    };
    if (!procedureSteps.containsKey(procedure.Procedure_Name__c)) {
        procedureSteps.put(procedure.Procedure_Name__c, new List<Map<String, Object>>());
    }
    procedureSteps.get(procedure.Procedure_Name__c).add(step);
}

Compression.ZipWriter writer = new Compression.ZipWriter();
List<Map<String, Object>> files = new List<Map<String, Object>>();
Integer totalRecords = 0;

List<String> procedureNames = new List<String>(procedureSteps.keySet());
procedureNames.sort();
for (String procedureName : procedureNames) {
    Map<String, Object> payload = new Map<String, Object>{
        'procedure' => procedureName,
        'steps' => procedureSteps.get(procedureName)
    };
    String json = JSON.serializePretty(payload);
    String safeName = procedureName.replaceAll('[^A-Za-z0-9._-]', '_');
    String path = 'procedures/' + safeName + '.json';
    writer.addEntry(path, Blob.valueOf(json));
    files.add(new Map<String, Object>{
        'path' => path,
        'recordCount' => procedureSteps.get(procedureName).size(),
        'sha256' => EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(json))
        )
    });
    totalRecords += procedureSteps.get(procedureName).size();
}

for (Pricing_Rule__mdt rule : rules) {
    Map<String, Object> payload = new Map<String, Object>{
        'developerName' => rule.DeveloperName,
        'label' => rule.MasterLabel,
        'ruleType' => rule.Rule_Type__c,
        'product' => rule.Product__c,
        'requiresProduct' => rule.Requires_Product__c,
        'commitmentCode' => rule.Commitment_Code__c,
        'segment' => rule.Segment__c,
        'adjustmentType' => rule.Adjustment_Type__c,
        'adjustmentValue' => rule.Adjustment_Value__c,
        'priority' => rule.Priority__c,
        'effectiveFrom' => rule.Effective_From__c,
        'effectiveTo' => rule.Effective_To__c,
        'active' => rule.Active__c
    };
    String json = JSON.serializePretty(payload);
    String safeName = rule.DeveloperName.replaceAll('[^A-Za-z0-9._-]', '_');
    String path = 'rules/' + safeName + '.json';
    writer.addEntry(path, Blob.valueOf(json));
    files.add(new Map<String, Object>{
        'path' => path,
        'recordCount' => 1,
        'sha256' => EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(json))
        )
    });
    totalRecords++;
}

for (Config_Rule__mdt rule : configRules) {
    Map<String, Object> payload = new Map<String, Object>{
        'developerName' => rule.DeveloperName,
        'label' => rule.MasterLabel,
        'ruleKind' => rule.Rule_Kind__c,
        'product' => rule.Product__c,
        'companionProduct' => rule.Companion_Product__c,
        'appliesWhenCommitment' => rule.Applies_When_Commitment__c,
        'message' => rule.Message__c,
        'severity' => rule.Severity__c,
        'active' => rule.Active__c
    };
    String json = JSON.serializePretty(payload);
    String safeName = rule.DeveloperName.replaceAll('[^A-Za-z0-9._-]', '_');
    String path = 'config-rules/' + safeName + '.json';
    writer.addEntry(path, Blob.valueOf(json));
    files.add(new Map<String, Object>{
        'path' => path,
        'recordCount' => 1,
        'sha256' => EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(json))
        )
    });
    totalRecords++;
}

Map<String, Object> manifest = new Map<String, Object>{
    'formatVersion' => 1,
    'exportedAt' => String.valueOfGmt(DateTime.now()).replace(' ', 'T') + 'Z',
    'targetOrg' => UserInfo.getUserName(),
    'source' => 'scripts/export-pricing.apex',
    'algorithm' => 'SHA-256',
    'files' => files,
    'totals' => new Map<String, Object>{
        'files' => files.size(),
        'records' => totalRecords
    }
};
String manifestJson = JSON.serializePretty(manifest);
writer.addEntry('manifest.json', Blob.valueOf(manifestJson));

Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
attachment.setFileName('pricing-export.zip');
attachment.setBody(writer.getArchive());

if (String.isNotBlank(UserInfo.getUserEmail())) {
    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
    email.setSubject('ATS pricing export ' + String.valueOfGmt(DateTime.now()));
    email.setPlainTextBody(
        'Attached is the ATS pricing export: ' +
        files.size() + ' files, ' + totalRecords + ' records.'
    );
    email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });

    try {
        List<Messaging.SendEmailResult> results =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        System.debug(
            'Pricing export email sent: ' + results[0].isSuccess() +
            ', files: ' + files.size() +
            ', records: ' + totalRecords
        );
    } catch (Exception e) {
        System.debug('Pricing export email failed: ' + e.getMessage());
    }
} else {
    System.debug('Pricing export has no recipient email address.');
}

System.debug(
    'Pricing export built: ' + files.size() +
    ' files, ' + totalRecords + ' records, manifest sha: ' +
    EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(manifestJson))
    )
);
