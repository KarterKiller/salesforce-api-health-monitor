ApiHealthService.CheckResult checkResult = ApiHealthController.checkNow('Public_Status_Demo');
System.debug(LoggingLevel.ERROR, 'LIVE_CHECK=' + JSON.serialize(checkResult));

ApiHealthService.DashboardResponse dashboard = ApiHealthController.getDashboard();
System.debug(LoggingLevel.ERROR, 'LIVE_DASHBOARD=' + JSON.serialize(dashboard));
