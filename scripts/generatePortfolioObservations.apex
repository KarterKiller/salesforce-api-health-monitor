List<String> configKeys = new List<String>{ 'Public_Status_Demo', 'Public_503_Failure_Demo', 'Public_Get_Demo' };
for (String configKey : configKeys) {
    ApiHealthService.CheckResult result = ApiHealthController.checkNow(configKey);
    System.debug(LoggingLevel.ERROR, 'LIVE_OBSERVATION=' + JSON.serialize(result));
}
System.debug(LoggingLevel.ERROR, 'LIVE_DASHBOARD=' + JSON.serialize(ApiHealthController.getDashboard()));
System.debug(LoggingLevel.ERROR, 'LIVE_HISTORY=' + JSON.serialize(ApiHealthController.getLatencyHistory()));
