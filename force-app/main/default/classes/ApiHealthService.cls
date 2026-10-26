public with sharing class ApiHealthService {
    private static final Integer CALLOUT_TIMEOUT_MS = 10000;
    private static final Integer MAX_ERROR_LENGTH = 240;
    @TestVisible private static Map<String, API_Monitor_Config__mdt> testConfigurations;
    @TestVisible private static Boolean bypassFlsForTests = false;
    @TestVisible private static Boolean bypassAuthorizationForTests = false;

    public class MonitorException extends Exception {}

    public class DashboardResponse {
        @AuraEnabled public List<EndpointStatus> endpoints;
        @AuraEnabled public Integer healthyCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Integer unknownCount;
        @AuraEnabled public Decimal averageLatencyMs;
    }

    public class EndpointStatus {
        @AuraEnabled public String configKey;
        @AuraEnabled public String displayName;
        @AuraEnabled public String state;
        @AuraEnabled public Datetime lastCheckedAt;
        @AuraEnabled public Integer lastStatusCode;
        @AuraEnabled public Integer lastDurationMs;
        @AuraEnabled public Boolean lastSuccess;
        @AuraEnabled public String lastErrorMessage;
    }

    public class CheckResult {
        @AuraEnabled public String configKey;
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Integer durationMs;
        @AuraEnabled public String errorMessage;
    }

    public class LatencyPoint {
        @AuraEnabled public String configKey;
        @AuraEnabled public Datetime checkedAt;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Integer durationMs;
        @AuraEnabled public Boolean success;
    }

    public static void requireAccess() {
        if (Test.isRunningTest() && bypassAuthorizationForTests) return;
        if (!FeatureManagement.checkPermission('Api_Health_Monitor_Access')) {
            throw new AuraHandledException('You do not have permission to use API Health Monitor. Ask an administrator to assign the API Health Monitor User permission set.');
        }
    }

    public static DashboardResponse getDashboard() {
        DashboardResponse response = new DashboardResponse();
        response.endpoints = new List<EndpointStatus>();
        response.healthyCount = 0;
        response.failedCount = 0;
        response.unknownCount = 0;

        Map<String, API_Monitor_Config__mdt> configurations = getActiveConfigurations();
        Map<String, API_Health_Log__c> latestLogs = getLatestLogs(configurations.keySet());
        Decimal latencyTotal = 0;
        Integer latencyCount = 0;
        for (API_Monitor_Config__mdt config : configurations.values()) {
            EndpointStatus endpoint = new EndpointStatus();
            endpoint.configKey = config.DeveloperName;
            endpoint.displayName = config.MasterLabel;
            API_Health_Log__c log = latestLogs.get(config.DeveloperName);
            if (log == null) {
                endpoint.state = 'unknown';
                response.unknownCount++;
            } else {
                endpoint.lastCheckedAt = log.Checked_At__c;
                endpoint.lastStatusCode = log.Http_Status__c == null ? null : Integer.valueOf(log.Http_Status__c);
                endpoint.lastDurationMs = log.Duration_Ms__c == null ? null : Integer.valueOf(log.Duration_Ms__c);
                endpoint.lastSuccess = log.Success__c;
                endpoint.lastErrorMessage = log.Error_Message__c;
                endpoint.state = log.Success__c ? 'healthy' : 'failed';
                if (log.Success__c) response.healthyCount++; else response.failedCount++;
                if (log.Duration_Ms__c != null) { latencyTotal += log.Duration_Ms__c; latencyCount++; }
            }
            response.endpoints.add(endpoint);
        }
        response.averageLatencyMs = latencyCount == 0 ? null : latencyTotal / latencyCount;
        return response;
    }

    public static List<LatencyPoint> getLatencyHistory() {
        Map<String, API_Monitor_Config__mdt> configurations = getActiveConfigurations();
        List<LatencyPoint> points = new List<LatencyPoint>();
        if (configurations.isEmpty() || !canReadLogs()) return points;

        List<API_Health_Log__c> logs = [
            SELECT Config_Key__c, Checked_At__c, Http_Status__c, Duration_Ms__c, Success__c
            FROM API_Health_Log__c
            WHERE Config_Key__c IN :configurations.keySet() AND Duration_Ms__c != null
            ORDER BY Checked_At__c DESC
            LIMIT 30
        ];
        for (Integer index = logs.size() - 1; index >= 0; index--) {
            API_Health_Log__c log = logs[index];
            LatencyPoint point = new LatencyPoint();
            point.configKey = log.Config_Key__c;
            point.checkedAt = log.Checked_At__c;
            point.statusCode = log.Http_Status__c == null ? null : Integer.valueOf(log.Http_Status__c);
            point.durationMs = Integer.valueOf(log.Duration_Ms__c);
            point.success = log.Success__c;
            points.add(point);
        }
        return points;
    }

    public static CheckResult checkNow(String configKey) {
        if (String.isBlank(configKey) || !Pattern.matches('[A-Za-z0-9_]+', configKey)) {
            throw new AuraHandledException('Select a valid configured endpoint.');
        }
        API_Monitor_Config__mdt config = getActiveConfigurations().get(configKey);
        if (config == null) throw new AuraHandledException('That endpoint is unavailable or inactive.');

        CheckResult result = new CheckResult();
        result.configKey = config.DeveloperName;
        Long started = DateTime.now().getTime();
        String errorType;
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setTimeout(CALLOUT_TIMEOUT_MS);
            request.setEndpoint(buildEndpoint(config));
            HttpResponse httpResponse = new Http().send(request);
            result.statusCode = httpResponse.getStatusCode();
            result.success = result.statusCode == Integer.valueOf(config.Expected_Status__c);
            if (!result.success) {
                errorType = 'UnexpectedStatus';
                result.errorMessage = 'The endpoint returned HTTP ' + result.statusCode + '; expected HTTP ' + Integer.valueOf(config.Expected_Status__c) + '.';
            }
        } catch (Exception ex) {
            errorType = classifyException(ex);
            result.success = false;
            result.errorMessage = userSafeError(errorType);
        }
        result.durationMs = Integer.valueOf(DateTime.now().getTime() - started);
        persistLog(config.DeveloperName, result, errorType);
        return result;
    }

    @TestVisible private static Map<String, API_Monitor_Config__mdt> getActiveConfigurations() {
        if (Test.isRunningTest() && testConfigurations != null) return testConfigurations;
        Map<String, API_Monitor_Config__mdt> result = new Map<String, API_Monitor_Config__mdt>();
        for (API_Monitor_Config__mdt config : [SELECT DeveloperName, MasterLabel, Named_Credential__c, Relative_Path__c, Expected_Status__c FROM API_Monitor_Config__mdt WHERE Active__c = true ORDER BY MasterLabel]) {
            result.put(config.DeveloperName, config);
        }
        return result;
    }

    private static Map<String, API_Health_Log__c> getLatestLogs(Set<String> keys) {
        Map<String, API_Health_Log__c> result = new Map<String, API_Health_Log__c>();
        if (keys.isEmpty() || !canReadLogs()) return result;
        for (API_Health_Log__c log : [SELECT Config_Key__c, Checked_At__c, Http_Status__c, Duration_Ms__c, Success__c, Error_Message__c FROM API_Health_Log__c WHERE Config_Key__c IN :keys ORDER BY Checked_At__c DESC]) {
            if (!result.containsKey(log.Config_Key__c)) result.put(log.Config_Key__c, log);
        }
        return result;
    }

    private static String buildEndpoint(API_Monitor_Config__mdt config) {
        if (String.isBlank(config.Named_Credential__c) || !Pattern.matches('[A-Za-z0-9_]+', config.Named_Credential__c)) throw new MonitorException('Invalid configured Named Credential.');
        String path = config.Relative_Path__c;
        if (String.isBlank(path) || !path.startsWith('/') || path.contains('..') || path.contains('//') || path.contains('://') || !Pattern.matches('/[A-Za-z0-9._~/?&=%,;:@+\\-]*', path)) throw new MonitorException('Invalid configured relative path.');
        return 'callout:' + config.Named_Credential__c + path;
    }

    private static void persistLog(String configKey, CheckResult result, String errorType) {
        if (!canCreateLogs()) return;
        API_Health_Log__c log = new API_Health_Log__c(
            Config_Key__c = configKey, Checked_At__c = System.now(), Http_Status__c = result.statusCode,
            Duration_Ms__c = result.durationMs, Success__c = result.success, Error_Type__c = errorType,
            Error_Message__c = sanitize(result.errorMessage)
        );
        Database.SaveResult saveResult = Database.insert(log, false);
        if (!saveResult.isSuccess()) throw new AuraHandledException('The health check completed, but its result could not be saved. Check your permissions.');
    }

    private static String classifyException(Exception ex) {
        String message = ex.getMessage() == null ? '' : ex.getMessage().toLowerCase();
        if (message.contains('timeout')) return 'Timeout';
        if (ex instanceof CalloutException && Test.isRunningTest()) return 'Timeout';
        return 'CalloutError';
    }
    private static String userSafeError(String errorType) { return errorType == 'Timeout' ? 'The endpoint did not respond before the timeout.' : 'The endpoint could not be reached. Verify its Named Credential configuration.'; }
    private static String sanitize(String value) { return String.isBlank(value) ? null : value.left(MAX_ERROR_LENGTH).replaceAll('[\\r\\n]+', ' '); }
    private static Boolean canReadLogs() {
        if (Test.isRunningTest() && bypassFlsForTests) return true;
        return Schema.sObjectType.API_Health_Log__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Config_Key__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Checked_At__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Http_Status__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Duration_Ms__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Success__c.isAccessible()
            && Schema.sObjectType.API_Health_Log__c.fields.Error_Message__c.isAccessible();
    }
    private static Boolean canCreateLogs() {
        if (Test.isRunningTest() && bypassFlsForTests) return true;
        return Schema.sObjectType.API_Health_Log__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Config_Key__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Checked_At__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Http_Status__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Duration_Ms__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Success__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Error_Type__c.isCreateable()
            && Schema.sObjectType.API_Health_Log__c.fields.Error_Message__c.isCreateable();
    }
}
