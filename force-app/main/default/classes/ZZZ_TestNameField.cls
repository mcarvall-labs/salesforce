public with sharing class ZZZ_TestNameField {
    public class Wrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String otherField;
    }
    @AuraEnabled
    public static String echo(Wrapper w) {
        return 'name=[' + w.name + '] otherField=[' + w.otherField + ']';
    }
    @AuraEnabled
    public static String echoPrimitive(String s) {
        return 'primitive=[' + s + ']';
    }
}