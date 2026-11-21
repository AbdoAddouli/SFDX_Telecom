/** Reads callout settings from metadata and the hierarchy feature flag. */
public with sharing class ExternalApiConfigLoader {
    public ExternalApiService.Config load(String apiName) {
        List<External_Api__mdt> rows = [
            SELECT DeveloperName, Base_Url__c, AuthType__c, NamedCredential__c,
                Timeout_Ms__c, Cache_Ttl_Seconds__c,
                Rate_Limit_Per_Minute__c, Is_Active__c
            FROM External_Api__mdt
            WHERE DeveloperName = :apiName
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new ExternalApiException(
                'External API configuration not found: ' + apiName);
        }

        External_Api__mdt row = rows[0];
        ExternalApiService.Config config = new ExternalApiService.Config();
        config.apiName = row.DeveloperName;
        config.baseUrl = row.Base_Url__c;
        config.authType = row.AuthType__c;
        config.namedCredential = row.NamedCredential__c;
        config.timeoutMs = row.Timeout_Ms__c == null
            ? ExternalApiService.DEFAULT_TIMEOUT_MS
            : row.Timeout_Ms__c;
        config.cacheTtlSeconds = row.Cache_Ttl_Seconds__c;
        config.rateLimitPerMinute = row.Rate_Limit_Per_Minute__c;
        config.isActive = row.Is_Active__c != false;
        return config;
    }

    public Boolean globalEnabled() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        return flags == null || flags.External_Api_Enabled__c != false;
    }
}
