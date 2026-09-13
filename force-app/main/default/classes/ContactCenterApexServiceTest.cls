@isTest
private class ContactCenterApexServiceTest {
    
    
    @testSetup
    static void setupData() {
        
        Account acc = new Account(Name = 'Test Account', Phone = '(123) 456-7890');
        insert acc;
        CallCenter cc = [SELECT Id FROM CallCenter LIMIT 1];
        
        for (Integer i = 0; i < 4; i++) {
            insert new VoiceCall(
                CallType = 'Inbound',
                CallCenterId = cc.Id,
                VendorType = 'ContactCenter',
                FromPhoneNumber = '+11234567890',
                ToPhoneNumber = '+10987654321',
                CallStartDateTime = System.now().addMinutes(-i * 5),
                CallEndDateTime = System.now().addMinutes(-i * 5 + 1),
                CallQueuedDateTime = System.now().addMinutes(-i * 5),
                CallAcceptDateTime = null
            );
        }
    }
    
    static testMethod void testGetCallerInfo_ValidPhone() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/SCVCCApexService';
        req.httpMethod = 'GET';
        req.addParameter('phoneNumber', '+11234567890');
        
        Test.startTest();
        RestContext.request = req;
        RestContext.response = res;
        
        ContactCenterApexService.getCallerInfo();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"repatedCaller":true'));
        System.assert(body.contains('"newCaller":false'));
    }
    
    static testMethod void testGetCallerInfo_MissingPhone() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/SCVCCApexService';
        req.httpMethod = 'GET';
        
        Test.startTest();
        RestContext.request = req;
        RestContext.response = res;
        
        ContactCenterApexService.getCallerInfo();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode);
        System.assertEquals(true, res.responseBody.toString().contains('Missing required parameter'));
    }
    
    static testMethod void testGetCallerInfo_NewCaller() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/SCVCCApexService';
        req.httpMethod = 'GET';
        req.addParameter('phoneNumber', '9999999999'); // No Account and no VoiceCalls
        
        Test.startTest();
        RestContext.request = req;
        RestContext.response = res;
        
        ContactCenterApexService.getCallerInfo();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode);
        String body = res.responseBody.toString();
        System.assert(body.contains('"newCaller":true'));
        System.assert(body.contains('"repatedCaller":false'));
    }
    
    static testMethod void testGetCallerInfo_Exception() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestUri = '/services/apexrest/SCVCCApexService';
        req.httpMethod = 'GET';
        req.addParameter('phoneNumber', '');
        
        Test.startTest();
        RestContext.request = req;
        RestContext.response = res;
        
        ContactCenterApexService.getCallerInfo();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode);
        System.assert(res.responseBody.toString().contains('Missing required parameter'));
    }
}