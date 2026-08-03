trigger AXF_TRG_CreditCard on AXF_OBJ_CreditCard__c (before insert, before update) {
    AXF_CLS_TH_AccountCardNaming.handleCreditCards(Trigger.new);
}