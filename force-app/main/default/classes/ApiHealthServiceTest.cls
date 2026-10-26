@IsTest
private class ApiHealthServiceTest {
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().startsWith('callout:ApiHealthDemo/'));
            HttpResponse response = new HttpResponse(); response.setStatusCode(200); return response;
        }
    }
    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse(); response.setStatusCode(503); return response;
        }
    }
    private class TimeoutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) { throw new CalloutException('Read timed out'); }
    }
    private static String demoKey() {
        String key = 'Public_Status_Demo';
        ApiHealthService.testConfigurations = new Map<String, API_Monitor_Config__mdt>{ key => new API_Monitor_Config__mdt(
            DeveloperName = key, MasterLabel = 'Public Status Demo', Named_Credential__c = 'ApiHealthDemo', Relative_Path__c = '/status/200', Expected_Status__c = 200
        )};
        ApiHealthService.bypassFlsForTests = true;
        return key;
    }
    @IsTest static void checkNowStoresSuccessfulResult() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest(); ApiHealthService.CheckResult result = ApiHealthService.checkNow(demoKey()); Test.stopTest();
        System.assertEquals(true, result.success); System.assertEquals(200, result.statusCode);
        API_Health_Log__c log = [SELECT Success__c, Http_Status__c, Error_Message__c FROM API_Health_Log__c WHERE Config_Key__c = :result.configKey LIMIT 1];
        System.assertEquals(true, log.Success__c); System.assertEquals(200, Integer.valueOf(log.Http_Status__c)); System.assertEquals(null, log.Error_Message__c);
    }
    @IsTest static void unexpectedStatusIsStoredWithoutResponseBody() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        Test.startTest(); ApiHealthService.CheckResult result = ApiHealthService.checkNow(demoKey()); Test.stopTest();
        System.assertEquals(false, result.success); System.assertEquals(503, result.statusCode);
        API_Health_Log__c log = [SELECT Success__c, Error_Type__c, Error_Message__c FROM API_Health_Log__c WHERE Config_Key__c = :result.configKey LIMIT 1];
        System.assertEquals(false, log.Success__c); System.assertEquals('UnexpectedStatus', log.Error_Type__c); System.assert(log.Error_Message__c.contains('503'));
    }
    @IsTest static void timeoutIsStoredAsSafeMessage() {
        Test.setMock(HttpCalloutMock.class, new TimeoutMock());
        Test.startTest(); ApiHealthService.CheckResult result = ApiHealthService.checkNow(demoKey()); Test.stopTest();
        System.assertEquals(false, result.success); System.assertEquals('The endpoint did not respond before the timeout.', result.errorMessage);
        API_Health_Log__c log = [SELECT Error_Type__c, Error_Message__c FROM API_Health_Log__c WHERE Config_Key__c = :result.configKey LIMIT 1];
        System.assertEquals('Timeout', log.Error_Type__c); System.assertEquals(result.errorMessage, log.Error_Message__c);
    }
    @IsTest static void rejectsUnknownEndpointKey() {
        try { ApiHealthService.checkNow('Not_Configured'); System.assert(false, 'Expected an exception'); }
        catch (AuraHandledException ex) { System.assertNotEquals(null, ex); }
    }
    @IsTest static void dashboardUsesPersistedLogs() {
        insert new API_Health_Log__c(Config_Key__c = demoKey(), Checked_At__c = System.now(), Success__c = true, Http_Status__c = 200, Duration_Ms__c = 50);
        ApiHealthService.DashboardResponse dashboard = ApiHealthService.getDashboard();
        System.assert(dashboard.healthyCount > 0); System.assertNotEquals(null, dashboard.averageLatencyMs);
    }
    @IsTest static void latencyHistoryUsesPersistedLogsInChronologicalOrder() {
        String key = demoKey();
        Datetime earlier = System.now().addMinutes(-2);
        insert new List<API_Health_Log__c>{
            new API_Health_Log__c(Config_Key__c = key, Checked_At__c = earlier, Success__c = true, Http_Status__c = 200, Duration_Ms__c = 42),
            new API_Health_Log__c(Config_Key__c = key, Checked_At__c = System.now(), Success__c = false, Http_Status__c = 503, Duration_Ms__c = 120)
        };
        List<ApiHealthService.LatencyPoint> history = ApiHealthService.getLatencyHistory();
        System.assertEquals(2, history.size());
        System.assertEquals(42, history[0].durationMs);
        System.assertEquals(false, history[1].success);
        System.assertEquals(503, history[1].statusCode);
        System.assert(history[0].checkedAt.getTime() <= history[1].checkedAt.getTime());
    }
    @IsTest static void controllerRejectsUserWithoutCustomPermission() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User user = new User(Alias = 'noaccess', Email = 'noaccess@example.test', EmailEncodingKey = 'UTF-8',
            LastName = 'No Access', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles', Username = 'noaccess' + DateTime.now().getTime() + '@example.test');
        insert user;
        System.runAs(user) {
            try { ApiHealthController.getDashboard(); System.assert(false, 'Expected access denial'); }
            catch (AuraHandledException ex) { System.assertNotEquals(null, ex); }
        }
    }
    @IsTest static void controllerReturnsDashboardForAuthorizedUser() {
        demoKey();
        ApiHealthService.bypassAuthorizationForTests = true;
        ApiHealthService.DashboardResponse dashboard = ApiHealthController.getDashboard();
        System.assertEquals(1, dashboard.endpoints.size());
    }
    @IsTest static void controllerReturnsLatencyHistoryForAuthorizedUser() {
        String key = demoKey();
        insert new API_Health_Log__c(Config_Key__c = key, Checked_At__c = System.now(), Success__c = true, Duration_Ms__c = 60);
        ApiHealthService.bypassAuthorizationForTests = true;
        System.assertEquals(1, ApiHealthController.getLatencyHistory().size());
    }
    @IsTest static void controllerRunsCheckForAuthorizedUser() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        ApiHealthService.bypassAuthorizationForTests = true;
        Test.startTest();
        ApiHealthService.CheckResult result = ApiHealthController.checkNow(demoKey());
        Test.stopTest();
        System.assertEquals(true, result.success);
    }
}
