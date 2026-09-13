@RestResource(urlMapping='/SCVCCApexService')
global class ContactCenterApexService {
    
    @httpGet
    global static void getCallerInfo() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        Map<String, Object> responseMap = new Map<String, Object>();
        try {               
            String phoneNumber = req.params.get('phoneNumber');
            if (String.isBlank(phoneNumber)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('Missing required parameter: phoneNumber');
                return;
            }
            List<String> formattedNumbersList = AccountHelper.formatPhoneNumber(phoneNumber);
            Set<String> formattedNumbers = new Set<String>(formattedNumbersList);
            formattedNumbers.remove('');
            if (!formattedNumbers.isEmpty()) {  
                String whereClause = AccountHelper.buildWhereClause(formattedNumbers);
                String query = 'SELECT Id FROM Account WHERE ' + whereClause + ' ORDER BY CreatedDate DESC LIMIT 1';
                //List<Account> accList = [SELECT Id FROM Account WHERE Phone IN :formattedNumbers OR PersonMobilePhone IN :formattedNumbers LIMIT 1];
                List<Account> accList = Database.query(query);
                responseMap.put('newCaller', accList.isEmpty());
            }
            
            Integer repeatedCallerCount = Integer.valueOf(System.Label.SCV_Repeated_Caller_Count);
            List<AggregateResult> aggrRes = [SELECT Count(Id) FROM VoiceCall 
                                             WHERE CreatedDate = TODAY AND CallQueuedDateTime != NULL 
                                             AND CallAcceptDateTime = NULL AND FromPhoneNumber =: phoneNumber 
                                             GROUP BY FromPhoneNumber HAVING Count(Id) >: repeatedCallerCount];
            responseMap.put('repeatedCaller', !aggrRes.isEmpty());
            res.statusCode = 200;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
        } catch(Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('Server error: ' + e.getMessage());
        }        
    }
}