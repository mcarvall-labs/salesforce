/**
 * @description Standardized record name of bank accounts and credit cards, as in production:
 * "HOLDER - INSTITUTION" in upper case, institution codes in parentheses and diacritics removed.
 * Falls back to the holder alone, the institution alone or the current name.
 */
public inherited sharing class ALT_CLS_SourceNaming {
  public void nameBankAccounts(List<AXF_OBJ_BankAccount__c> records) {
    Set<Id> holderIds = new Set<Id>();
    Set<Id> institutionIds = new Set<Id>();
    for (AXF_OBJ_BankAccount__c record : records) {
      holderIds.add(record.AXF_BA_LKP_Account__c);
      institutionIds.add(record.AXF_BA_LKP_BankInstitution__c);
    }
    Map<Id, String> holders = holderNames(holderIds);
    Map<Id, String> institutions = institutionNames(institutionIds);
    for (AXF_OBJ_BankAccount__c record : records) {
      String institution = institutions.get(
        record.AXF_BA_LKP_BankInstitution__c
      );
      record.Name = standardizedName(
        holders.get(record.AXF_BA_LKP_Account__c),
        institution != null
          ? institution
          : record.AXF_BA_TXT_InstitutionName__c,
        record.Name
      );
    }
  }

  public void nameCreditCards(List<AXF_OBJ_CreditCard__c> records) {
    Set<Id> holderIds = new Set<Id>();
    Set<Id> institutionIds = new Set<Id>();
    for (AXF_OBJ_CreditCard__c record : records) {
      holderIds.add(record.AXF_CC_LKP_Account__c);
      institutionIds.add(record.AXF_CC_LKP_BankInstitution__c);
    }
    Map<Id, String> holders = holderNames(holderIds);
    Map<Id, String> institutions = institutionNames(institutionIds);
    for (AXF_OBJ_CreditCard__c record : records) {
      String institution = institutions.get(
        record.AXF_CC_LKP_BankInstitution__c
      );
      record.Name = standardizedName(
        holders.get(record.AXF_CC_LKP_Account__c),
        institution != null
          ? institution
          : record.AXF_CC_TXT_InstitutionName__c,
        record.Name
      );
    }
  }

  @TestVisible
  private static String standardizedName(
    String holderName,
    String institutionName,
    String fallbackName
  ) {
    String holder = String.isNotBlank(holderName) ? holderName.trim() : null;
    String institution = String.isNotBlank(institutionName)
      ? removeDiacritics(
          institutionName.replaceAll('\\s*\\([^)]*\\)', '').trim()
        )
      : null;
    String raw;
    if (String.isNotBlank(holder) && String.isNotBlank(institution)) {
      raw = holder + ' - ' + institution;
    } else if (String.isNotBlank(holder)) {
      raw = holder;
    } else if (String.isNotBlank(institution)) {
      raw = institution;
    } else {
      raw = fallbackName;
    }
    return String.isNotBlank(raw) ? raw.trim().toUpperCase().left(80) : raw;
  }

  private static String removeDiacritics(String value) {
    return value.toUpperCase()
      .replaceAll('[ÁÀÂÃÄ]', 'A')
      .replaceAll('[ÉÈÊË]', 'E')
      .replaceAll('[ÍÌÎÏ]', 'I')
      .replaceAll('[ÓÒÔÕÖ]', 'O')
      .replaceAll('[ÚÙÛÜ]', 'U')
      .replace('Ç', 'C');
  }

  private static Map<Id, String> holderNames(Set<Id> ids) {
    ids.remove(null);
    Map<Id, String> result = new Map<Id, String>();
    if (!ids.isEmpty()) {
      for (Account row : [SELECT Id, Name FROM Account WHERE Id IN :ids]) {
        result.put(row.Id, row.Name);
      }
    }
    return result;
  }

  private static Map<Id, String> institutionNames(Set<Id> ids) {
    ids.remove(null);
    Map<Id, String> result = new Map<Id, String>();
    if (!ids.isEmpty()) {
      for (AXF_OBJ_BankInstitution__c row : [
        SELECT Id, Name
        FROM AXF_OBJ_BankInstitution__c
        WHERE Id IN :ids
      ]) {
        result.put(row.Id, row.Name);
      }
    }
    return result;
  }
}
