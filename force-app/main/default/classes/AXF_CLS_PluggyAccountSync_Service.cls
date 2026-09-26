public with sharing class AXF_CLS_PluggyAccountSync_Service {

    private static final String ACCOUNTS_ENDPOINT = 'callout:AXF_NC_Pluggy_API/accounts?itemId=';
    private static final String TYPE_BANK = 'BANK';
    private static final String TYPE_CREDIT = 'CREDIT';
    private static final String SUBTYPE_CREDIT_CARD = 'CREDIT_CARD';

    public class AccountSyncResult {
        public List<AXF_OBJ_BankAccount__c> bankAccounts = new List<AXF_OBJ_BankAccount__c>();
        public List<AXF_OBJ_CreditCard__c> creditCards = new List<AXF_OBJ_CreditCard__c>();
    }

    public static AccountSyncResult fetchAccountsForConnection(Id connectionId, String pluggyItemId, String apiKey) {
        AccountSyncResult result = new AccountSyncResult();

        if (String.isBlank(pluggyItemId)) {
            return result;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ACCOUNTS_ENDPOINT + EncodingUtil.urlEncode(pluggyItemId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('X-API-KEY', apiKey);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() == 200) {
            parseAccounts(res.getBody(), connectionId, result);
        }

        return result;
    }

    public static void upsertAccounts(AccountSyncResult result) {
        if (!result.bankAccounts.isEmpty()) {
            for (AXF_OBJ_BankAccount__c acc : result.bankAccounts) {
                if (acc.Name != null) {
                    acc.Name = acc.Name.toUpperCase();
                }
            }
            Database.upsert(result.bankAccounts, AXF_OBJ_BankAccount__c.AXF_BA_EXI_PluggyAccountId__c, false);
        }
        if (!result.creditCards.isEmpty()) {
            // Garantir que cartões sem Account/BankInstitution atribuídos usem os mapas de fallback
            Map<Id, Id> connAccountMap = buildConnectionIdToAccountMap();
            Map<Id, Id> connBankInstMap = buildConnectionIdToBankInstMap();
            Set<Id> accountIds = new Set<Id>();
            Set<Id> bankInstitutionIds = new Set<Id>();

            for (AXF_OBJ_CreditCard__c card : result.creditCards) {
                if (card.AXF_CC_LKP_Account__c == null && card.AXF_CC_LKP_PluggyConnection__c != null && connAccountMap.containsKey(card.AXF_CC_LKP_PluggyConnection__c)) {
                    card.AXF_CC_LKP_Account__c = connAccountMap.get(card.AXF_CC_LKP_PluggyConnection__c);
                }
                if (card.AXF_CC_LKP_BankInstitution__c == null && card.AXF_CC_LKP_PluggyConnection__c != null && connBankInstMap.containsKey(card.AXF_CC_LKP_PluggyConnection__c)) {
                    card.AXF_CC_LKP_BankInstitution__c = connBankInstMap.get(card.AXF_CC_LKP_PluggyConnection__c);
                }
                accountIds.add(card.AXF_CC_LKP_Account__c);
                bankInstitutionIds.add(card.AXF_CC_LKP_BankInstitution__c);
            }

            accountIds.remove(null);
            bankInstitutionIds.remove(null);
            Map<Id, String> accountIdToNameMap = buildAccountIdToNameMap(accountIds);
            Map<Id, String> bankInstIdToNameMap = buildBankInstIdToNameMap(bankInstitutionIds);
            for (AXF_OBJ_CreditCard__c card : result.creditCards) {
                String holderName = card.AXF_CC_LKP_Account__c != null ? accountIdToNameMap.get(card.AXF_CC_LKP_Account__c) : null;
                String institutionName = card.AXF_CC_LKP_BankInstitution__c != null ? bankInstIdToNameMap.get(card.AXF_CC_LKP_BankInstitution__c) : null;
                card.Name = buildStandardizedName(holderName, institutionName, card.Name, System.Label.AXF_LBL_DefaultCreditCardName);
            }
            Database.upsert(result.creditCards, AXF_OBJ_CreditCard__c.AXF_CC_EXI_PluggyCreditCardId__c, false);
        }
    }

    private static void parseAccounts(String responseBody, Id connectionId, AccountSyncResult result) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> results = (List<Object>) body.get('results');
        if (results == null) {
            return;
        }

        // Mapeamentos para vincular Account (Titular por CPF) e BankInstitution (por Número do Banco e Conexão)
        Map<String, Id> cpfToAccountIdMap = buildCpfToAccountMap();
        Map<Id, String> accountIdToNameMap = buildAccountIdToNameMap();
        Map<String, Id> bankNumberToInstIdMap = buildBankNumberToInstMap();
        Map<Id, String> bankInstIdToNameMap = buildBankInstIdToNameMap();
        Map<Id, Id> connectionIdToBankInstMap = buildConnectionIdToBankInstMap();
        Map<Id, Id> connectionIdToAccountMap = buildConnectionIdToAccountMap();

        for (Object item : results) {
            Map<String, Object> data = (Map<String, Object>) item;
            String type = (String) data.get('type');
            String subtype = (String) data.get('subtype');

            if (type == TYPE_BANK) {
                result.bankAccounts.add(mapBankAccount(data, connectionId, cpfToAccountIdMap, accountIdToNameMap, bankNumberToInstIdMap, bankInstIdToNameMap, connectionIdToBankInstMap));
            } else if (type == TYPE_CREDIT && subtype == SUBTYPE_CREDIT_CARD) {
                result.creditCards.add(mapCreditCard(data, connectionId, cpfToAccountIdMap, accountIdToNameMap, bankNumberToInstIdMap, bankInstIdToNameMap, connectionIdToBankInstMap, connectionIdToAccountMap));
            }
        }
    }

    private static AXF_OBJ_BankAccount__c mapBankAccount(
        Map<String, Object> data,
        Id connectionId,
        Map<String, Id> cpfToAccountIdMap,
        Map<Id, String> accountIdToNameMap,
        Map<String, Id> bankNumberToInstIdMap,
        Map<Id, String> bankInstIdToNameMap,
        Map<Id, Id> connectionIdToBankInstMap
    ) {
        AXF_OBJ_BankAccount__c account = new AXF_OBJ_BankAccount__c();
        account.AXF_BA_EXI_PluggyAccountId__c = (String) data.get('id');
        account.AXF_BA_LKP_PluggyConnection__c = connectionId;

        account.AXF_BA_TXT_AccountNumber__c = (String) data.get('number');
        account.AXF_BA_CUR_Balance__c = data.get('balance') != null ? (Decimal) data.get('balance') : null;
        account.AXF_BA_PKL_Currency__c = (String) data.get('currency');
        String subtypeVal = (String) data.get('subtype');
        String typeVal = (String) data.get('type');
        account.AXF_BA_PKL_Type__c = String.isNotBlank(subtypeVal) ? subtypeVal : typeVal;
        account.AXF_BA_DAT_LastSync__c = parseDatetime((String) data.get('updatedAt'));

        // Vínculo com a Account (Titular/CPF)
        String taxNumber = (String) data.get('taxNumber');
        if (String.isNotBlank(taxNumber)) {
            if (cpfToAccountIdMap.containsKey(taxNumber)) {
                account.AXF_BA_LKP_Account__c = cpfToAccountIdMap.get(taxNumber);
            } else {
                String digitsOnly = taxNumber.replaceAll('[^0-9]', '');
                if (cpfToAccountIdMap.containsKey(digitsOnly)) {
                    account.AXF_BA_LKP_Account__c = cpfToAccountIdMap.get(digitsOnly);
                }
            }
        }

        // Mapeamento e extração de dados bancários (Agência e BankInstitution)
        Map<String, Object> bankData = data.get('bankData') != null ? (Map<String, Object>) data.get('bankData') : null;
        String transferNumber = bankData != null ? (String) bankData.get('transferNumber') : null;

        if (bankData != null) {
            if (bankData.containsKey('agencyNumber') && bankData.get('agencyNumber') != null && String.isNotBlank(String.valueOf(bankData.get('agencyNumber')))) {
                account.AXF_BA_TXT_AgencyNumber__c = String.valueOf(bankData.get('agencyNumber'));
            } else if (String.isNotBlank(transferNumber) && transferNumber.contains('/')) {
                List<String> parts = transferNumber.split('/');
                if (parts.size() >= 3) {
                    account.AXF_BA_TXT_AgencyNumber__c = parts[1].trim();
                } else if (parts.size() == 2) {
                    account.AXF_BA_TXT_AgencyNumber__c = parts[0].trim();
                }
            }
        }

        if (String.isNotBlank(transferNumber)) {
            String bankNum = transferNumber.contains('/') ? transferNumber.split('/')[0].trim() : transferNumber.trim();
            if (bankNumberToInstIdMap.containsKey(bankNum)) {
                account.AXF_BA_LKP_BankInstitution__c = bankNumberToInstIdMap.get(bankNum);
            } else {
                String digitsOnly = bankNum.replaceAll('[^0-9]', '');
                if (bankNumberToInstIdMap.containsKey(digitsOnly)) {
                    account.AXF_BA_LKP_BankInstitution__c = bankNumberToInstIdMap.get(digitsOnly);
                } else if (String.isNotBlank(digitsOnly) && bankNumberToInstIdMap.containsKey(String.valueOf(Integer.valueOf(digitsOnly)))) {
                    account.AXF_BA_LKP_BankInstitution__c = bankNumberToInstIdMap.get(String.valueOf(Integer.valueOf(digitsOnly)));
                }
            }
        }

        // Fallback de Instituição Bancária via Conexão
        if (account.AXF_BA_LKP_BankInstitution__c == null && connectionIdToBankInstMap.containsKey(connectionId)) {
            account.AXF_BA_LKP_BankInstitution__c = connectionIdToBankInstMap.get(connectionId);
        }

        // Standardized name: {Account holder name} - {clean bank institution name}.
        String institutionName = account.AXF_BA_LKP_BankInstitution__c != null ? bankInstIdToNameMap.get(account.AXF_BA_LKP_BankInstitution__c) : null;
        String holderName = account.AXF_BA_LKP_Account__c != null ? accountIdToNameMap.get(account.AXF_BA_LKP_Account__c) : null;
        account.Name = buildStandardizedName(holderName, institutionName, null, System.Label.AXF_LBL_DefaultBankAccountName);

        return account;
    }

    private static AXF_OBJ_CreditCard__c mapCreditCard(
        Map<String, Object> data,
        Id connectionId,
        Map<String, Id> cpfToAccountIdMap,
        Map<Id, String> accountIdToNameMap,
        Map<String, Id> bankNumberToInstIdMap,
        Map<Id, String> bankInstIdToNameMap,
        Map<Id, Id> connectionIdToBankInstMap,
        Map<Id, Id> connectionIdToAccountMap
    ) {
        Map<String, Object> creditData = data.get('creditData') != null
            ? (Map<String, Object>) data.get('creditData')
            : new Map<String, Object>();

        AXF_OBJ_CreditCard__c card = new AXF_OBJ_CreditCard__c();
        card.AXF_CC_EXI_PluggyCreditCardId__c = (String) data.get('id');
        card.AXF_CC_LKP_PluggyConnection__c = connectionId;
        String fallbackName = data.get('name') != null ? String.valueOf(data.get('name')) : (String) data.get('id');
        card.AXF_CC_TXT_LastFourDigits__c = extractLastFourDigits((String) data.get('number'));
        card.AXF_CC_CUR_AvailableLimit__c = creditData.get('availableCreditLimit') != null
            ? (Decimal) creditData.get('availableCreditLimit')
            : null;
        card.AXF_CC_CUR_CreditLimit__c = creditData.get('creditLimit') != null
            ? (Decimal) creditData.get('creditLimit')
            : null;
        card.AXF_CC_TXT_Brand__c = (String) creditData.get('brand');
        card.AXF_CC_TXT_Level__c = (String) creditData.get('level');
        card.AXF_CC_NUM_ClosingDay__c = extractDayOfMonth((String) creditData.get('balanceCloseDate'));
        card.AXF_CC_NUM_DueDay__c = extractDayOfMonth((String) creditData.get('balanceDueDate'));
        card.AXF_CC_DAT_LastSync__c = parseDatetime((String) data.get('updatedAt'));

        // Vínculo com a Account (Titular/CPF)
        String taxNumber = (String) data.get('taxNumber');
        if (String.isNotBlank(taxNumber)) {
            if (cpfToAccountIdMap.containsKey(taxNumber)) {
                card.AXF_CC_LKP_Account__c = cpfToAccountIdMap.get(taxNumber);
            } else {
                String digitsOnly = taxNumber.replaceAll('[^0-9]', '');
                if (cpfToAccountIdMap.containsKey(digitsOnly)) {
                    card.AXF_CC_LKP_Account__c = cpfToAccountIdMap.get(digitsOnly);
                }
            }
        }

        // Fallback de Account via Conexão (se taxNumber for nulo no payload de cartões da Pluggy API)
        if (card.AXF_CC_LKP_Account__c == null && connectionIdToAccountMap.containsKey(connectionId)) {
            card.AXF_CC_LKP_Account__c = connectionIdToAccountMap.get(connectionId);
        }

        // Vínculo com a BankInstitution (número do banco ou conexão)
        Map<String, Object> bankData = data.get('bankData') != null ? (Map<String, Object>) data.get('bankData') : null;
        String transferNumber = bankData != null ? (String) bankData.get('transferNumber') : null;
        if (String.isNotBlank(transferNumber)) {
            String bankNum = transferNumber.contains('/') ? transferNumber.split('/')[0].trim() : transferNumber.trim();
            if (bankNumberToInstIdMap.containsKey(bankNum)) {
                card.AXF_CC_LKP_BankInstitution__c = bankNumberToInstIdMap.get(bankNum);
            } else {
                String digitsOnly = bankNum.replaceAll('[^0-9]', '');
                if (bankNumberToInstIdMap.containsKey(digitsOnly)) {
                    card.AXF_CC_LKP_BankInstitution__c = bankNumberToInstIdMap.get(digitsOnly);
                } else if (String.isNotBlank(digitsOnly) && bankNumberToInstIdMap.containsKey(String.valueOf(Integer.valueOf(digitsOnly)))) {
                    card.AXF_CC_LKP_BankInstitution__c = bankNumberToInstIdMap.get(String.valueOf(Integer.valueOf(digitsOnly)));
                }
            }
        }

        // Fallback de Instituição Bancária via Conexão
        if (card.AXF_CC_LKP_BankInstitution__c == null && connectionIdToBankInstMap.containsKey(connectionId)) {
            card.AXF_CC_LKP_BankInstitution__c = connectionIdToBankInstMap.get(connectionId);
        }

        String holderName = card.AXF_CC_LKP_Account__c != null ? accountIdToNameMap.get(card.AXF_CC_LKP_Account__c) : null;
        String institutionName = card.AXF_CC_LKP_BankInstitution__c != null ? bankInstIdToNameMap.get(card.AXF_CC_LKP_BankInstitution__c) : null;
        card.Name = buildStandardizedName(holderName, institutionName, fallbackName, System.Label.AXF_LBL_DefaultCreditCardName);

        return card;
    }

    private static Map<String, Id> buildCpfToAccountMap() {
        Map<String, Id> cpfMap = new Map<String, Id>();
        for (Account acc : [SELECT Id, AXF_ACC_EXI_CPF__c FROM Account WHERE AXF_ACC_EXI_CPF__c != null]) {
            cpfMap.put(acc.AXF_ACC_EXI_CPF__c, acc.Id);
            String digitsOnly = acc.AXF_ACC_EXI_CPF__c.replaceAll('[^0-9]', '');
            if (String.isNotBlank(digitsOnly)) {
                cpfMap.put(digitsOnly, acc.Id);
            }
        }
        return cpfMap;
    }

    private static Map<String, Id> buildBankNumberToInstMap() {
        Map<String, Id> bankMap = new Map<String, Id>();
        for (AXF_OBJ_BankInstitution__c inst : [SELECT Id, AXF_BI_EXI_Bank_Number__c FROM AXF_OBJ_BankInstitution__c WHERE AXF_BI_EXI_Bank_Number__c != null]) {
            bankMap.put(inst.AXF_BI_EXI_Bank_Number__c, inst.Id);
            String digitsOnly = inst.AXF_BI_EXI_Bank_Number__c.replaceAll('[^0-9]', '');
            if (String.isNotBlank(digitsOnly)) {
                bankMap.put(digitsOnly, inst.Id);
                try {
                    bankMap.put(String.valueOf(Integer.valueOf(digitsOnly)), inst.Id);
                } catch (Exception e) {}
            }
        }
        return bankMap;
    }

    private static Map<Id, String> buildAccountIdToNameMap() {
        Map<Id, String> accountNameMap = new Map<Id, String>();
        for (Account acc : [SELECT Id, Name FROM Account WHERE AXF_ACC_EXI_CPF__c != null]) {
            accountNameMap.put(acc.Id, acc.Name);
        }
        return accountNameMap;
    }

    private static Map<Id, String> buildAccountIdToNameMap(Set<Id> accountIds) {
        Map<Id, String> accountNameMap = new Map<Id, String>();
        if (accountIds.isEmpty()) {
            return accountNameMap;
        }
        for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE]) {
            accountNameMap.put(acc.Id, acc.Name);
        }
        return accountNameMap;
    }

    private static Map<Id, String> buildBankInstIdToNameMap() {
        Map<Id, String> instNameMap = new Map<Id, String>();
        for (AXF_OBJ_BankInstitution__c inst : [SELECT Id, Name FROM AXF_OBJ_BankInstitution__c]) {
            instNameMap.put(inst.Id, inst.Name);
        }
        return instNameMap;
    }

    private static Map<Id, String> buildBankInstIdToNameMap(Set<Id> bankInstitutionIds) {
        Map<Id, String> instNameMap = new Map<Id, String>();
        if (bankInstitutionIds.isEmpty()) {
            return instNameMap;
        }
        for (AXF_OBJ_BankInstitution__c inst : [
            SELECT Id, Name
            FROM AXF_OBJ_BankInstitution__c
            WHERE Id IN :bankInstitutionIds
            WITH USER_MODE
        ]) {
            instNameMap.put(inst.Id, inst.Name);
        }
        return instNameMap;
    }

    private static Map<Id, Id> buildConnectionIdToBankInstMap() {
        Map<Id, Id> connMap = new Map<Id, Id>();
        for (AXF_OBJ_PluggyConnection__c conn : [SELECT Id, AXF_CON_LKP_BankInstitution__c FROM AXF_OBJ_PluggyConnection__c WHERE AXF_CON_LKP_BankInstitution__c != null]) {
            connMap.put(conn.Id, conn.AXF_CON_LKP_BankInstitution__c);
        }
        return connMap;
    }

    private static Map<Id, Id> buildConnectionIdToAccountMap() {
        Map<Id, Id> connAccountMap = new Map<Id, Id>();
        for (AXF_OBJ_BankAccount__c ba : [
            SELECT AXF_BA_LKP_PluggyConnection__c, AXF_BA_LKP_Account__c
            FROM AXF_OBJ_BankAccount__c
            WHERE AXF_BA_LKP_PluggyConnection__c != null AND AXF_BA_LKP_Account__c != null
        ]) {
            connAccountMap.put(ba.AXF_BA_LKP_PluggyConnection__c, ba.AXF_BA_LKP_Account__c);
        }
        return connAccountMap;
    }

    public static String buildStandardizedName(
        String holderName,
        String institutionName,
        String fallbackName,
        String defaultName
    ) {
        String cleanHolderName = String.isNotBlank(holderName) ? holderName.trim() : null;
        String cleanInstitutionName = cleanInstitutionName(institutionName);
        String rawName;

        if (String.isNotBlank(cleanHolderName) && String.isNotBlank(cleanInstitutionName)) {
            rawName = cleanHolderName + ' - ' + cleanInstitutionName;
        } else if (String.isNotBlank(cleanHolderName)) {
            rawName = cleanHolderName;
        } else if (String.isNotBlank(cleanInstitutionName)) {
            rawName = cleanInstitutionName;
        } else if (String.isNotBlank(fallbackName)) {
            rawName = fallbackName.trim();
        } else {
            rawName = defaultName;
        }

        return normalizeRecordName(rawName);
    }

    private static String cleanInstitutionName(String institutionName) {
        if (String.isBlank(institutionName)) {
            return null;
        }
        String withoutCodes = institutionName.replaceAll('\\s*\\([^)]*\\)', '').trim();
        return removeDiacritics(withoutCodes);
    }

    private static String normalizeRecordName(String value) {
        return String.isNotBlank(value) ? value.trim().toUpperCase() : null;
    }

    private static String removeDiacritics(String value) {
        return value.toUpperCase()
            .replace('Á', 'A').replace('À', 'A').replace('Â', 'A').replace('Ã', 'A').replace('Ä', 'A')
            .replace('É', 'E').replace('È', 'E').replace('Ê', 'E').replace('Ë', 'E')
            .replace('Í', 'I').replace('Ì', 'I').replace('Î', 'I').replace('Ï', 'I')
            .replace('Ó', 'O').replace('Ò', 'O').replace('Ô', 'O').replace('Õ', 'O').replace('Ö', 'O')
            .replace('Ú', 'U').replace('Ù', 'U').replace('Û', 'U').replace('Ü', 'U')
            .replace('Ç', 'C');
    }

    private static String extractLastFourDigits(String cardNumber) {
        if (String.isBlank(cardNumber)) {
            return null;
        }
        String digitsOnly = cardNumber.replaceAll('[^0-9]', '');
        if (digitsOnly.length() <= 4) {
            return digitsOnly;
        }
        return digitsOnly.substring(digitsOnly.length() - 4);
    }

    private static Integer extractDayOfMonth(String isoDate) {
        Datetime parsed = parseDatetime(isoDate);
        return parsed != null ? parsed.dayGmt() : null;
    }

    private static Datetime parseDatetime(String isoDatetime) {
        if (String.isBlank(isoDatetime)) {
            return null;
        }
        return (Datetime) JSON.deserialize('"' + isoDatetime + '"', Datetime.class);
    }
}