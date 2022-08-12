/*
 * Jakub "Midora" Paliński, 2022
*/
@isTest
private class GetConnectedOrgDataTest {
    
    private static final String PROD_NAME = 'TestProdName';
    private static final String EXT_ID = 'TestProdName';
    private static final String ACCT_NAME = 'TestAcctName';
    
    @testSetup
    static void setupData() {
        Test.startTest();
        	insert new ConnectedOrgSetting__c(NC__c = 'NotBlank');
            insert new Product2(Name = PROD_NAME, ProductCode = EXT_ID);
            insert new Account(Name = ACCT_NAME);
        Test.stopTest();
    }
    
    @isTest
    static void shouldFetchProds() {
        Schema.SObjectField extId = getExtId(Product2.SObjectType);
        if (extId != null) {
            //Given
            Product2 existing = [SELECT Id FROM Product2 WHERE Name = :PROD_NAME];
            existing.put(extId, EXT_ID);
            Test.startTest();
            update existing;
            Test.stopTest();
            String changedName = 'changedName';
            Product2 toReplyProd = new Product2(ProductCode = EXT_ID, Name = changedName);
            toReplyProd.put(extId, EXT_ID);
            List<Product2> toReply = new List<Product2>{toReplyProd};
            
            //When        
            Test.setMock(HttpCalloutMock.class, new ConnDataMock(toReply));
            GetConnectedOrgData.ProductProcessor proc = new GetConnectedOrgData.ProductProcessor('');
            proc.externalIdField = extId;
            proc.wherePart = 'where Name != null';
            proc.fetchData(true);
            
            //Then
            System.assertEquals(changedName, [SELECT Id, Name FROM Product2 WHERE Id = :existing.Id].Name);            
        }
    }
    
    @isTest
    static void shouldFetchAccounts() {
        Schema.SObjectField extId = getExtId(Account.SObjectType);
        if (extId != null) {
            //Given
            Account existing = [SELECT Id FROM Account WHERE Name = :ACCT_NAME];
            existing.put(extId, EXT_ID);
            update existing;
            String changedName = 'changedName';
            Account toReplyAcct = new Account(Name = changedName);
            toReplyAcct.put(extId, EXT_ID);
            List<Account> toReply = new List<Account>{toReplyAcct};
            
            //When        
            Test.setMock(HttpCalloutMock.class, new ConnDataMock(toReply));
            GetConnectedOrgData.AccountProcessor proc = new GetConnectedOrgData.AccountProcessor('').setSampleWherePart();
            proc.externalIdField = extId;
            proc.wherePart = 'where Name != null';
            Test.startTest();
            	GetConnectedOrgData.GetDataQueueable one = new GetConnectedOrgData.GetDataQueueable(proc, null, 4);
            	System.enqueueJob(new GetConnectedOrgData.GetDataQueueable(proc));
            Test.stopTest();
            proc.fetchMore('not empty');
            
            //Then
            System.assertEquals(changedName, [SELECT Id, Name FROM Account WHERE Id = :existing.Id].Name);            
        }
    }
    
    @isTest
    static void testErrorLogs() {
        //Given
        Integer recCount = 10;
        List<Account> toInsert = new List<Account>();
        for (Integer i = 0; i < recCount; i++) {
            toInsert.add(new Account());
        }
        
        //When
        List<GetConnectedOrgErrorHelper.ErrorLog> results = GetConnectedOrgErrorHelper.upsertLoggingError(toInsert, null, 'Experimental Prefix');
        
        //Then
        System.assertEquals(10, results.size());
    }
    
    private static Schema.SObjectField getExtId(Schema.SObjectType objType) {
        for (Schema.SObjectField sf : objType.getDescribe().fields.getMap().values()) {
            if (sf.getDescribe().isExternalId()) {
                return sf;
            }
        }
        return null;
    }
    
    private class ConnDataMock implements HttpCalloutMock {
        List<SObject> toReply = new List<SObject>();
        Boolean replyMore = false;

        public ConnDataMock() {}
        
        public ConnDataMock(List<SObject> toReply) {
            this.toReply = toReply;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HTTPResponse();
            res.setHeader('Content-Type', 'application/JSON');
            if (!toReply.isEmpty()) {
                GetProductionData.QueryResult answer = new GetProductionData.QueryResult();
                answer.nextRecordsUrl = replyMore ? 'string' : null;
                answer.records = toReply;
                
                String bodyString = JSON.serialize(answer);
                res.setBody(bodyString);
                res.setStatusCode(201);
            } else {     
                res.setBody('{"token":"xxx", "error":"invalid invalid"}');      
                res.setStatusCode(400);
            }
            return res;
        }
    }

}