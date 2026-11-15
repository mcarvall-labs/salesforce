public with sharing class AXF_CLS_CTRL_PluggyConnection {
  public class TestView {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer accounts;
    @AuraEnabled
    public Integer cards;
  }

  // Tests the Item on Pluggy and, when it is valid, imports the bank accounts and credit
  // cards of the connection (they show up in the related lists).
  @AuraEnabled
  public static TestView testAndSync(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Informe a conexão.');
    }
    List<AXF_OBJ_PluggyConnection__c> found = [
      SELECT AXF_CON_EXI_PluggyItemId__c
      FROM AXF_OBJ_PluggyConnection__c
      WHERE Id = :connectionId
      WITH USER_MODE
    ];
    if (found.isEmpty()) {
      throw new AuraHandledException('Conexão não encontrada.');
    }
    TestView view = new TestView();
    view.success = false;
    view.accounts = 0;
    view.cards = 0;
    String itemId = found[0].AXF_CON_EXI_PluggyItemId__c;
    if (String.isBlank(itemId)) {
      view.message = 'Item Id não informado.';
      return view;
    }
    ALT_CLS_PluggyAccountSync.Result result;
    try {
      new ALT_CLS_PluggyConnection().validateItem(itemId);
      result = new ALT_CLS_PluggyAccountSync().sync(connectionId);
    } catch (ALT_CLS_PluggyCredential.PluggyException e) {
      view.message = e.getMessage();
      return view;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Não foi possível testar a conexão: ' + e.getMessage()
      );
    }
    view.success = result.success;
    view.message = result.success ? 'Conexão válida.' : result.message;
    view.accounts = result.accounts;
    view.cards = result.cards;
    return view;
  }
}
