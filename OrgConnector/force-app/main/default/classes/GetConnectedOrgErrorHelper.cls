public class GetConnectedOrgErrorHelper {
    
    public static List<ErrorLog> upsertLoggingError(List<SObject> dmlObjects, Schema.SObjectField externalIdField, String errorMessagePrefix) {
        List<Database.UpsertResult> svrs = externalIdField == null ? Database.upsert(dmlObjects, false) : Database.upsert(dmlObjects, externalIdField, false);
        if (errorMessagePrefix == null) {
            errorMessagePrefix = '';
        }
        List<ErrorLog> toReturn = new List<ErrorLog>();
        for (Integer i = 0; i < dmlObjects.size(); i++) {
            if (!svrs[i].isSuccess()) {
                toReturn.add(getDmlErrorLog(svrs[i].getErrors(), dmlObjects[i], errorMessagePrefix, externalIdField));
            }
        }
        return toReturn;
    }
    
    public static ErrorLog getDmlErrorLog(List<Database.Error> dmlErrors, SObject erroredObject, String errorMessagePrefix, Schema.SObjectField externalIdField) {
        ErrorLog toReturn = new ErrorLog(errorMessagePrefix, erroredObject.Id);
        if (externalIdField != null) {
            toReturn.recOrExtId = (String) erroredObject.get(externalIdField);
        }
        toReturn.descr += String.valueOf(erroredObject) + '; ';
        for (Database.Error err : dmlErrors) {
            toReturn.descr += err.getMessage() + ', ';
        }
        toReturn.descr = toReturn.descr.removeEnd(', ');
        System.debug(LOGGINGLEVEL.DEBUG, toReturn);
        return toReturn;
    }
    
    public class ErrorLog {
        public String descr;
        public String recOrExtId;
        
        public ErrorLog(String descr, String recOrExtId) {
            this.descr = descr;
            this.recOrExtId = recOrExtId;            
        }
    }
}