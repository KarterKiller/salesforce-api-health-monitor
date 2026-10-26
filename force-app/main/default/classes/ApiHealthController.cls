public with sharing class ApiHealthController {
    @AuraEnabled(cacheable=true)
    public static ApiHealthService.DashboardResponse getDashboard() {
        ApiHealthService.requireAccess();
        return ApiHealthService.getDashboard();
    }

    @AuraEnabled(cacheable=true)
    public static List<ApiHealthService.LatencyPoint> getLatencyHistory() {
        ApiHealthService.requireAccess();
        return ApiHealthService.getLatencyHistory();
    }

    @AuraEnabled
    public static ApiHealthService.CheckResult checkNow(String configKey) {
        ApiHealthService.requireAccess();
        return ApiHealthService.checkNow(configKey);
    }
}
