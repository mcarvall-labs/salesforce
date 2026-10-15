public with sharing class AXF_CLS_CTRL_ContractScope {
  public class PreviewRow {
    @AuraEnabled
    public Id entryId;
    @AuraEnabled
    public Integer ordinal;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String newName;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Date newDueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal newAmount;
  }

  public class Preview {
    @AuraEnabled
    public List<PreviewRow> rows = new List<PreviewRow>();
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public Integer kept = 0;
    @AuraEnabled
    public Integer preserved = 0;
    @AuraEnabled
    public Integer missing = 0;
  }

  public class Summary {
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public Integer created = 0;
  }

  // Contract field -> the scope field it is governed by (null: saved without a scope).
  private static final Map<SObjectField, String> SCOPE_OF = new Map<SObjectField, String>{
    AXF_OBJ_Contract__c.Name => ALT_CLS_ContractScope.FIELD_NAME,
    AXF_OBJ_Contract__c.AXF_CTR_CUR_Amount__c => ALT_CLS_ContractScope.FIELD_AMOUNT,
    AXF_OBJ_Contract__c.AXF_CTR_CUR_FinancedAmount__c => ALT_CLS_ContractScope.FIELD_AMOUNT,
    AXF_OBJ_Contract__c.AXF_CTR_NUM_DueDay__c => ALT_CLS_ContractScope.FIELD_DUE,
    AXF_OBJ_Contract__c.AXF_CTR_DAT_FirstDueDate__c => ALT_CLS_ContractScope.FIELD_DUE,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_Category__c => ALT_CLS_ContractScope.FIELD_CATEGORY,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_BankAccount__c => ALT_CLS_ContractScope.FIELD_ACCOUNT,
    AXF_OBJ_Contract__c.AXF_CTR_LKP_CreditCard__c => ALT_CLS_ContractScope.FIELD_ACCOUNT,
    AXF_OBJ_Contract__c.AXF_CTR_NUM_InstallmentCount__c => null,
    AXF_OBJ_Contract__c.AXF_CTR_TXT_Counterparty__c => null
  };

  private static final Set<String> VALID_SCOPES = new Set<String>{
    ALT_CLS_ContractScope.SCOPE_ALL,
    ALT_CLS_ContractScope.SCOPE_FUTURE,
    ALT_CLS_ContractScope.SCOPE_FROM,
    ALT_CLS_ContractScope.SCOPE_MONTH,
    ALT_CLS_ContractScope.SCOPE_OVERDUE,
    ALT_CLS_ContractScope.SCOPE_NONE
  };

  @TestVisible
  private static Date today = Date.today();

  // Preview of the entries the chosen scopes would change; no DML.
  @AuraEnabled
  public static Preview preview(
    Id contractId,
    Map<String, Object> values,
    Map<String, Object> scopes
  ) {
    try {
      AXF_OBJ_Contract__c current = loadVisible(contractId);
      Edit edit = prepare(current, values, scopes);
      ALT_CLS_ContractScope.Plan plan = planFor(edit);
      Preview preview = new Preview();
      preview.updated = plan.updated;
      preview.kept = plan.kept;
      preview.preserved = plan.preserved;
      preview.missing = plan.missing;
      for (ALT_CLS_ContractScope.Row source : plan.rows) {
        PreviewRow row = new PreviewRow();
        row.entryId = source.entryId;
        row.ordinal = source.ordinal;
        row.status = source.status;
        row.outcome = source.outcome;
        row.name = source.name;
        row.newName = source.newName;
        row.dueDate = source.dueDate;
        row.newDueDate = source.newDueDate;
        row.amount = source.amount;
        row.newAmount = source.newAmount;
        preview.rows.add(row);
      }
      return preview;
    } catch (Exception e) {
      throw failure(e);
    }
  }

  // Saves the contract and applies the scopes in one transaction; any failure undoes both.
  @AuraEnabled
  public static Summary save(
    Id contractId,
    Map<String, Object> values,
    Map<String, Object> scopes
  ) {
    Savepoint checkpoint = null;
    Boolean previousBypass = AXF_CLS_ContractHandler.bypass;
    try {
      if (
        !Schema.sObjectType.AXF_OBJ_Contract__c.isUpdateable() ||
        !Schema.sObjectType.AXF_OBJ_Entry__c.isUpdateable()
      ) {
        throw fail(
          'Você não tem permissão para editar o contrato e os lançamentos.'
        );
      }
      AXF_OBJ_Contract__c current = loadVisible(contractId);
      Edit edit = prepare(current, values, scopes);
      ALT_CLS_ContractScope.Plan plan = planFor(edit);
      checkpoint = Database.setSavepoint();
      AXF_CLS_ContractHandler.bypass = true;
      if (!edit.changes.isEmpty()) {
        AXF_OBJ_Contract__c toSave = new AXF_OBJ_Contract__c(Id = contractId);
        for (SObjectField field : edit.changes) {
          toSave.put(field, edit.proposed.get(field));
        }
        update as user toSave;
      }
      Summary summary = new Summary();
      if (!plan.toUpdate.isEmpty()) {
        List<Database.SaveResult> saves = Database.update(
          plan.toUpdate,
          false,
          AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < saves.size(); i++) {
          if (!saves[i].isSuccess()) {
            throw fail(
              'Não foi possível atualizar o lançamento ' +
                entryName(plan.toUpdate[i].Id, plan) +
                ': ' +
                saves[i].getErrors()[0].getMessage()
            );
          }
        }
        summary.updated = plan.toUpdate.size();
      }
      if (
        edit.proposed.AXF_CTR_PKL_Status__c ==
        ALT_CLS_ContractGeneration.STATUS_ACTIVE
      ) {
        ALT_CLS_ContractGeneration.Result generated = new ALT_CLS_ContractGeneration(
            today
          )
          .generate(new Set<Id>{ contractId }, false);
        if (!generated.messages.isEmpty()) {
          throw fail(
            'Não foi possível gerar os lançamentos faltantes: ' +
            String.join(generated.messages, ' ')
          );
        }
        summary.created = generated.created;
      }
      return summary;
    } catch (Exception e) {
      if (checkpoint != null) {
        Database.rollback(checkpoint);
      }
      throw failure(e);
    } finally {
      AXF_CLS_ContractHandler.bypass = previousBypass;
    }
  }

  private class Edit {
    AXF_OBJ_Contract__c proposed;
    List<SObjectField> changes = new List<SObjectField>();
    Map<String, ALT_CLS_ContractScope.Choice> choices = new Map<String, ALT_CLS_ContractScope.Choice>();
  }

  private static ALT_CLS_ContractScope.Plan planFor(Edit edit) {
    return new ALT_CLS_ContractScope(today).plan(edit.proposed, edit.choices);
  }

  private static String entryName(Id entryId, ALT_CLS_ContractScope.Plan plan) {
    for (ALT_CLS_ContractScope.Row row : plan.rows) {
      if (row.entryId == entryId) {
        return row.name;
      }
    }
    return '';
  }

  private static AXF_OBJ_Contract__c loadVisible(Id contractId) {
    if (contractId == null) {
      throw fail('Informe o contrato.');
    }
    List<AXF_OBJ_Contract__c> visible = [
      SELECT Id
      FROM AXF_OBJ_Contract__c
      WHERE Id = :contractId
      WITH USER_MODE
    ];
    if (visible.isEmpty()) {
      throw fail('Contrato não encontrado.');
    }
    AXF_OBJ_Contract__c contract = ALT_CLS_ContractGeneration.load(
      new Set<Id>{ contractId }
    )[0];
    String type = contract.RecordType.DeveloperName;
    if (!allowedFor(type).contains(AXF_OBJ_Contract__c.Name)) {
      throw fail('Este tipo de contrato não pode ser editado por aqui.');
    }
    return contract;
  }

  private static Set<SObjectField> allowedFor(String recordType) {
    Set<SObjectField> allowed = new Set<SObjectField>();
    if (
      recordType != ALT_CLS_ContractGeneration.RT_RECURRING &&
      recordType != ALT_CLS_ContractGeneration.RT_INSTALLMENT &&
      recordType != ALT_CLS_ContractGeneration.RT_CONSORTIUM &&
      recordType != ALT_CLS_ContractGeneration.RT_FINANCING
    ) {
      return allowed;
    }
    allowed.add(AXF_OBJ_Contract__c.Name);
    allowed.add(AXF_OBJ_Contract__c.AXF_CTR_LKP_Category__c);
    allowed.add(AXF_OBJ_Contract__c.AXF_CTR_LKP_BankAccount__c);
    allowed.add(AXF_OBJ_Contract__c.AXF_CTR_LKP_CreditCard__c);
    allowed.add(AXF_OBJ_Contract__c.AXF_CTR_TXT_Counterparty__c);
    if (recordType == ALT_CLS_ContractGeneration.RT_RECURRING) {
      allowed.add(AXF_OBJ_Contract__c.AXF_CTR_CUR_Amount__c);
      allowed.add(AXF_OBJ_Contract__c.AXF_CTR_NUM_DueDay__c);
    } else {
      allowed.add(AXF_OBJ_Contract__c.AXF_CTR_DAT_FirstDueDate__c);
      allowed.add(AXF_OBJ_Contract__c.AXF_CTR_NUM_InstallmentCount__c);
      allowed.add(
        recordType == ALT_CLS_ContractGeneration.RT_FINANCING
          ? AXF_OBJ_Contract__c.AXF_CTR_CUR_FinancedAmount__c
          : AXF_OBJ_Contract__c.AXF_CTR_CUR_Amount__c
      );
    }
    return allowed;
  }

  // Applies the typed values to the contract in memory and reads the scope of each changed field.
  private static Edit prepare(
    AXF_OBJ_Contract__c current,
    Map<String, Object> values,
    Map<String, Object> scopes
  ) {
    Edit edit = new Edit();
    Set<SObjectField> allowed = allowedFor(current.RecordType.DeveloperName);
    Map<String, SObjectField> fields = Schema.SObjectType.AXF_OBJ_Contract__c.fields.getMap();
    Set<String> changedScopes = new Set<String>();
    for (
      String apiName : (values == null ? new Set<String>() : values.keySet())
    ) {
      SObjectField field = fields.get(apiName);
      if (field == null || !allowed.contains(field)) {
        throw fail('O campo ' + apiName + ' não pode ser editado por aqui.');
      }
      Object typed = convert(field, values.get(apiName));
      if (typed != current.get(field)) {
        current.put(field, typed);
        edit.changes.add(field);
        String scopeField = SCOPE_OF.get(field);
        if (scopeField != null) {
          changedScopes.add(scopeField);
        }
      }
    }
    edit.proposed = current;
    for (String scopeField : changedScopes) {
      edit.choices.put(scopeField, choiceFor(scopeField, scopes));
    }
    return edit;
  }

  private static ALT_CLS_ContractScope.Choice choiceFor(
    String scopeField,
    Map<String, Object> scopes
  ) {
    Object raw = scopes?.get(scopeField);
    if (raw == null) {
      return new ALT_CLS_ContractScope.Choice(
        ALT_CLS_ContractScope.SCOPE_FUTURE,
        null
      );
    }
    Map<String, Object> choice = (Map<String, Object>) raw;
    String scope = (String) choice.get('scope');
    if (scope == null || !VALID_SCOPES.contains(scope)) {
      throw fail('Escopo inválido para ' + scopeField + '.');
    }
    Integer fromNumber = null;
    Object start = choice.get('fromNumber');
    if (start != null && String.isNotBlank(String.valueOf(start))) {
      fromNumber = Integer.valueOf(String.valueOf(start));
    }
    if (scope == ALT_CLS_ContractScope.SCOPE_FROM && fromNumber == null) {
      throw fail('Informe a parcela inicial do escopo "A partir da parcela".');
    }
    return new ALT_CLS_ContractScope.Choice(scope, fromNumber);
  }

  private static Object convert(SObjectField field, Object raw) {
    if (
      raw == null || (raw instanceof String && String.isBlank((String) raw))
    ) {
      return null;
    }
    String text = String.valueOf(raw);
    Schema.DisplayType type = field.getDescribe().getType();
    try {
      if (type == Schema.DisplayType.DATE) {
        return Date.valueOf(text);
      }
      if (
        type == Schema.DisplayType.CURRENCY ||
        type == Schema.DisplayType.DOUBLE ||
        type == Schema.DisplayType.PERCENT ||
        type == Schema.DisplayType.INTEGER
      ) {
        return Decimal.valueOf(text);
      }
      if (type == Schema.DisplayType.REFERENCE) {
        return Id.valueOf(text);
      }
    } catch (Exception e) {
      throw fail('Valor inválido para ' + field.getDescribe().getLabel() + '.');
    }
    return text;
  }

  private static AuraHandledException fail(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }

  private static AuraHandledException failure(Exception e) {
    if (e instanceof AuraHandledException) {
      return (AuraHandledException) e;
    }
    if (e instanceof ALT_CLS_ContractScope.ScopeException) {
      return fail('Não foi possível aplicar a edição: ' + e.getMessage());
    }
    if (e instanceof DmlException) {
      return fail('Não foi possível salvar o contrato: ' + e.getDmlMessage(0));
    }
    return fail('Não foi possível editar o contrato: ' + e.getMessage());
  }
}
