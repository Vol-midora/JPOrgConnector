/*
 * Jakub "Midora" Paliński, 2022
*/
public class GetConnectedOrgData {

    public static final Set<Integer> SUCCESS_CODES = new Set<Integer>{ 200, 201, 202, 203, 204, 205, 206, 207, 208, 226 };
    
    public static ConnectedOrgSetting__c ORG_SETTINGS {
		get {
			if (ORG_SETTINGS == null) {
				ORG_SETTINGS = ConnectedOrgSetting__c.getOrgDefaults();
			}
			return ORG_SETTINGS;
		}
		private set;
	}
    
    public static final Integer MAX_QUEUE_DEPTH = Test.isRunningTest() ? 1 : 40;
    
    public class GetDataQueueable implements System.Queueable, Database.AllowsCallouts {
        public Integer depth;
        public Processor proc;
        public String nextData;
        
        public GetDataQueueable(Processor proc) {
            this.proc = proc;
            this.depth = 0;
        }
        
        public GetDataQueueable(Processor proc, String nextData, Integer depth) {
            this.proc = proc;
            this.nextData = nextData;
            this.depth = depth;
        }
        
        public void execute(System.QueueableContext qc) {
            if (this.nextData == null) {
               this.nextData = proc.fetchData(false); 
            } else {
                this.nextData = proc.fetchMore(this.nextData);
            }
            Integer nextDepth = this.depth + 1;
            if (String.isNotBlank(this.nextData) && nextDepth < MAX_QUEUE_DEPTH) {
                System.enqueueJob(new GetDataQueueable(this.proc, this.nextData, nextDepth));
            }
        }
    }
    
    public virtual class Processor {
        public String wherePart;
        public Schema.SObjectType objType;
        public Boolean createable;
        public String query;
        
        public String fetchData() {
            return fetchData(true);
        }
        
        public void setQuery() {
            if (this.query == null) {
                this.query = getChangeableQuery(this.objType, this.wherePart, this.createable, false);
            }
        }
        
        public String fetchData(Boolean sync) {
            setQuery();
            QueryResult result = getResults(this.query);
            List<SObject> toProcess = new List<SObject>();
            toProcess.addAll(result.records);
            if (sync) {
                while (String.isNotBlank(result.nextRecordsUrl)) {
                    result = getResults(result.nextRecordsUrl);
                    toProcess.addAll(result.records);
                }                
            }
            processRecords(toProcess);
            return result.nextRecordsUrl;
        }
        
        public virtual String fetchMore(String next) {
            String toReturn;
            if (String.isNotBlank(next)) {
            	QueryResult result = getResults(next);
                toReturn = result.nextRecordsUrl;
                processRecords(result.records);
            }
            return toReturn;
        }
        
        public virtual void processRecords(List<SObject> toProcess) {}
        
        public Boolean areValid(List<SObject> toProcess) {
            return toProcess != null && !toProcess.isEmpty();
        }
    }
    
    public class AccountProcessor extends Processor {        
        public Schema.SObjectField externalIdField;
        
        public AccountProcessor(String wherePart) {
            this.objType = Account.SObjectType;
            this.createable = false;
            this.wherePart = wherePart;
        }
        
        public override void processRecords(List<SObject> toProcess) {
            if (externalIdField != null && areValid(toProcess)) {                
                processAccs((List<Account>) toProcess); 
            }
        }
        
        public void processAccs(List<Account> accts) {
            GetConnectedOrgErrorHelper.upsertLoggingError(accts, externalIdField, 'Account retrieval error: ');
        }
        
        public AccountProcessor setSampleWherePart() {
            this.wherePart = ' WHERE IsPersonAccount = false';
            if (externalIdField != null) {
                this.wherePart += ' AND ' + externalIdField.getDescribe().getName() + ' != null';
            }
            return this;
        }
    }
    
    public class ProductProcessor extends Processor {
        public Schema.SObjectField externalIdField;
        public ProductProcessor(String wherePart) {
            this.objType = Product2.SObjectType;
            this.createable = false;
            this.wherePart = wherePart;
        }
        
        public override void processRecords(List<SObject> toProcess) {
            if (externalIdField != null && areValid(toProcess)) {                
                processProds((List<Product2>) toProcess); 
            }
        }
        
        public void processProds(List<Product2> prods) {
            GetConnectedOrgErrorHelper.upsertLoggingError(prods, externalIdField, 'Product2 retrieval error: ');
        }
    }
    
    public static QueryResult getResults(String param) {
        QueryResult toReturn = new QueryResult();
        if (String.isNotBlank(param)) {
            String response = makePRODQueryCallout(param);
            if (String.isNotBlank(response)) {
            	toReturn = (QueryResult) JSON.deserialize(response, QueryResult.class);
        	} else {
            	toReturn.records = new List<SObject>();
        	}
        }
        System.debug(LOGGINGLEVEL.DEBUG, 'Result: ' + toReturn);
        return toReturn;
    }
    
    public static String makePRODQueryCallout(String param) {
        String toReturn;
        HTTPResponse res;
        if (String.isNotBlank(param)) {
            param = param.startsWithIgnoreCase('SELECT') ? ('/services/data/v49.0/query/?q=' + param.replaceAll(' ', '+')) : param;
            HttpRequest req = getRequest(param);
            res = new Http().send(req);
            System.debug(res.getBody());
            if (SUCCESS_CODES.contains(res.getStatusCode())) {
                toReturn = res.getBody();
            } else {
                System.debug(LOGGINGLEVEL.DEBUG, res.getBody());
                System.debug(LOGGINGLEVEL.DEBUG, res.getStatus());
                System.debug(LOGGINGLEVEL.DEBUG, res.getStatusCode());
            }
        }
        return toReturn;
    }
    
    public static HttpRequest getRequest(String params) {
        HttpRequest toReturn = new HttpRequest();
        toReturn.setMethod('GET');
        toReturn.setEndpoint('callout:' + ORG_SETTINGS.NC__c + params);
        return toReturn;
    }
    
    public static String getChangeableQuery(Schema.SObjectType objType, String wherePart, Boolean createable, Boolean excludeDates) {
        return getChangeableQuery(objType, wherePart, createable, excludeDates, true);
    }
    
    public static String getChangeableQuery(Schema.SObjectType objType, String wherePart, Boolean createable, Boolean excludeDates, Boolean excludePersonAccountFields) {
        Schema.DescribeSObjectResult sobj = objType.getDescribe();
        String query;
        Map<String, Schema.DescribeFieldResult> fields = getObjectFields(sobj);
        List<String> toQuery = new List<String>();
        Set<String> excludedPAFields = objType == Contact.SObjectType ? new Set<String>() : new Set<String>{'Salutation', 'FirstName', 'LastName'};
        for (Schema.DescribeFieldResult dfr : fields.values()) {
            if ((createable ? dfr.isCreateable() : dfr.isUpdateable()) 
                && dfr.getReferenceTo().IsEmpty() 
                && (!excludeDates || (dfr.getType() != Schema.DisplayType.DATE &&  dfr.getType() != Schema.DisplayType.DATETIME))
                && (!excludePersonAccountFields || (!dfr.getName().contains('__pc') && !dfr.getName().startsWith('Person') && !excludedPAFields.contains(dfr.getName())))) {
                toQuery.add(dfr.getName());
            }
        }
        if (!toQuery.isEmpty()) {
            query = 'SELECT ' + String.join(toQuery, ', ') + ' FROM ' + sobj.getName() + '' + wherePart;
        }
        System.debug(query);
        return query;
    }
    
    public static Map<String, Schema.DescribeFieldResult> getObjectFields(Schema.DescribeSObjectResult sobj) {
        Map<String, Schema.DescribeFieldResult> toReturn = new Map<String, Schema.DescribeFieldResult>();
        Map<String, Schema.DescribeFieldResult> candidates = new Map<String, Schema.DescribeFieldResult>();
        for (Schema.SObjectField sfield : sobj.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = sfield.getDescribe();
            candidates.put(dfr.getName(), dfr);
            
        }
        String param = '/services/data/v55.0/sobjects/' + sobj.getName() + '/describe/';
        MdtResult result;
        try {
            result = (MdtResult) JSON.deserialize(makePRODQueryCallout(param), MdtResult.class);
        } catch (Exception ex) {
            System.debug(LOGGINGLEVEL.DEBUG, 'Error retrieving metadata from the target org');
            System.debug(LOGGINGLEVEL.DEBUG, ex.getMessage());
            System.debug(LOGGINGLEVEL.DEBUG, ex.getStackTraceString());
            if (!Test.isRunningTest()) {
            	throw new OrgConnectionException(ex);                
            }
        }
        if (result?.fields != null) {
            for (Field f : result.fields) {
                if (candidates.containsKey(f.name)) {
                    toReturn.put(f.name, candidates.get(f.name));
                }
            }            
        } else {
            toReturn = candidates;
        }
        return toReturn;
    }
    
    
    public class QueryResult {
        public List<SObject> records;
        public String nextRecordsUrl;
    }
    
    public class MdtResult {
        public String name;
        public List<Field> fields;
    }
    
    public class Field {
        public String name;
        public Boolean createable;
        public Boolean updateable;
        
    }
    
    
    public class OrgConnectionException extends Exception {}
}