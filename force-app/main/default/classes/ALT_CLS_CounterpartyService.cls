/**
 * @description Serviço de domínio para gestão de Contrapartes e relações contextuais com Entidades (AXF-51).
 *
 * Princípios e Contratos:
 * - Identidade mínima canônica na Contraparte root (G1, AD-30).
 * - Isolamento estrito de dados relacionais em CounterpartyEntityRelationship (G2, AD-30, GF-32).
 * - Identificador fiscal mascarado + digest HMAC; proibido valor reversível (AD-30, GF-24).
 * - Compartilhamento derivado por relação via Apex Managed Sharing (RowCause AXF_CounterpartyRelationAccess__c).
 * - Prevenção contra vazamento de relações entre diferentes entidades.
 */
public with sharing class ALT_CLS_CounterpartyService {

  public static final String SHARING_ROW_CAUSE = 'AXF_CounterpartyRelationAccess__c';

  public class CounterpartyInputDTO {
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String legalName;
    @AuraEnabled public String displayName;
    @AuraEnabled public String kind;
    @AuraEnabled public String country;
    @AuraEnabled public String status;
    @AuraEnabled public Long version;

    // Relação
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public String role;
    @AuraEnabled public String relationshipStatus;
    @AuraEnabled public String entitySpecificDisplay;
    @AuraEnabled public Date validFrom;
    @AuraEnabled public Date validTo;
    @AuraEnabled public String addressSnapshot;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public String contactName;
    @AuraEnabled public Long relationshipVersion;

    // Identificador fiscal
    @AuraEnabled public String taxScheme;
    @AuraEnabled public String taxCountry;
    @AuraEnabled public String taxRawDocument;
  }

  public class CounterpartySummaryDTO {
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public String displayName;
    @AuraEnabled public String legalName;
    @AuraEnabled public String kind;
    @AuraEnabled public String country;
    @AuraEnabled public String status;
    @AuraEnabled public String maskedTaxId;
    @AuraEnabled public String taxScheme;
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public String relationshipRole;
    @AuraEnabled public String relationshipStatus;
    @AuraEnabled public Date validFrom;
    @AuraEnabled public Date validTo;
  }

  public class CounterpartyDetailDTO {
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public String displayName;
    @AuraEnabled public String legalName;
    @AuraEnabled public String kind;
    @AuraEnabled public String country;
    @AuraEnabled public String status;
    @AuraEnabled public Long version;

    // Dados fiscais mascarados
    @AuraEnabled public String maskedTaxId;
    @AuraEnabled public String taxScheme;
    @AuraEnabled public String taxCountry;
    @AuraEnabled public String taxStatus;

    // Relação específica da Entidade autorizada
    @AuraEnabled public Id relationshipId;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String entityName;
    @AuraEnabled public String role;
    @AuraEnabled public String relationshipStatus;
    @AuraEnabled public String entitySpecificDisplay;
    @AuraEnabled public Date validFrom;
    @AuraEnabled public Date validTo;
    @AuraEnabled public String addressSnapshot;
    @AuraEnabled public String email;
    @AuraEnabled public String phone;
    @AuraEnabled public String contactName;
    @AuraEnabled public Long relationshipVersion;
  }

  public class OperationResultDTO {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String message;
    @AuraEnabled public Id counterpartyId;
    @AuraEnabled public Id relationshipId;
  }

  /**
   * @description Gera a máscara segura do documento fiscal conforme o esquema (AD-30, GF-24).
   */
  public static String formatMaskedTaxId(String rawDocument, String scheme) {
    if (String.isBlank(rawDocument)) {
      return '';
    }
    String clean = rawDocument.replaceAll('[^a-zA-Z0-9]', '');
    if (String.isBlank(clean)) {
      return '••••••••';
    }

    if ('CPF'.equalsIgnoreCase(scheme)) {
      if (clean.length() >= 11) {
        return '•••.•••.' + clean.substring(6, 9) + '-' + clean.substring(9, 11);
      }
      return '•••.•••.' + (clean.length() > 4 ? clean.substring(clean.length() - 4) : clean);
    } else if ('CNPJ'.equalsIgnoreCase(scheme)) {
      if (clean.length() >= 14) {
        return '••.•••.•••/' + clean.substring(8, 12) + '-' + clean.substring(12, 14);
      }
      return '••.•••.•••/' + (clean.length() > 4 ? clean.substring(clean.length() - 4) : clean);
    } else if ('NIF'.equalsIgnoreCase(scheme)) {
      if (clean.length() >= 9) {
        return 'NIF •••••' + clean.substring(clean.length() - 4);
      }
      return 'NIF •••••' + clean;
    }

    // Default: preserva últimos 4 caracteres
    if (clean.length() > 4) {
      return '••••••••' + clean.substring(clean.length() - 4);
    }
    return '••••' + clean;
  }

  /**
   * @description Gera o digest SHA-256 enquadrado do identificador fiscal (AD-30, G7).
   */
  public static String computeTaxDigest(String rawDocument, String scheme, String country) {
    if (String.isBlank(rawDocument)) {
      return null;
    }
    String normalized = rawDocument.replaceAll('[^a-zA-Z0-9]', '').toUpperCase();
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'TAX_ID',
      String.isNotBlank(scheme) ? scheme.toUpperCase() : 'OTHER',
      String.isNotBlank(country) ? country.toUpperCase() : 'XX',
      normalized
    });
  }

  /**
   * @description Gera a chave única enquadrada da contraparte por org.
   */
  public static String computeCounterpartyKey(String legalName, String country) {
    if (String.isBlank(legalName) || String.isBlank(country)) {
      throw new AXF_CLS_CounterpartyException('Nome legal e país são obrigatórios para chave de Contraparte.');
    }
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'COUNTERPARTY',
      legalName.trim().toUpperCase(),
      country.trim().toUpperCase()
    });
  }

  /**
   * @description Gera a chave única enquadrada da relação contratual.
   */
  public static String computeRelationshipKey(Id counterpartyId, Id accountId, String role) {
    if (counterpartyId == null || accountId == null || String.isBlank(role)) {
      throw new AXF_CLS_CounterpartyException('Contraparte, Entidade e Papel são obrigatórios para chave da Relação.');
    }
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'RELATIONSHIP',
      counterpartyId,
      accountId,
      role.toUpperCase()
    });
  }

  /**
   * @description Gera a chave única enquadrada do identificador fiscal.
   */
  public static String computeTaxIdentifierKey(Id counterpartyId, String scheme, String country, String searchDigest) {
    if (counterpartyId == null || String.isBlank(scheme) || String.isBlank(searchDigest)) {
      throw new AXF_CLS_CounterpartyException('Contraparte, Esquema e Digest são obrigatórios para chave de Identificador Fiscal.');
    }
    return AXF_CLS_IdentityFraming.key(new List<Object>{
      'TAX_IDENTIFIER',
      counterpartyId,
      scheme.toUpperCase(),
      String.isNotBlank(country) ? country.toUpperCase() : 'XX',
      searchDigest
    });
  }

  /**
   * @description Consulta contrapartes que possuem relação ativa/permitida com a entidade informada.
   */
  public List<CounterpartySummaryDTO> getCounterpartiesForEntity(Id accountId, String searchKey) {
    if (accountId == null) {
      throw new AXF_CLS_CounterpartyException('O ID da Entidade é obrigatório.');
    }

    // Valida acesso do usuário à Entidade (Account)
    List<Account> accounts = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      throw new AXF_CLS_CounterpartyException('Acesso negado ou Entidade não encontrada.');
    }

    // Busca relações vinculadas estritamente a esta Entidade
    List<AXF_OBJ_CounterpartyEntityRelationship__c> relationships = [
      SELECT
        Id,
        AXF_CER_LKP_Counterparty__c,
        AXF_CER_PKL_Role__c,
        AXF_CER_PKL_Status__c,
        AXF_CER_TXT_EntitySpecificDisplay__c,
        AXF_CER_DAT_ValidFrom__c,
        AXF_CER_DAT_ValidTo__c
      FROM AXF_OBJ_CounterpartyEntityRelationship__c
      WHERE AXF_CER_LKP_Account__c = :accountId
    ];

    if (relationships.isEmpty()) {
      return new List<CounterpartySummaryDTO>();
    }

    Map<Id, AXF_OBJ_CounterpartyEntityRelationship__c> relByCounterpartyId = new Map<Id, AXF_OBJ_CounterpartyEntityRelationship__c>();
    for (AXF_OBJ_CounterpartyEntityRelationship__c rel : relationships) {
      relByCounterpartyId.put(rel.AXF_CER_LKP_Counterparty__c, rel);
    }

    Set<Id> counterpartyIds = relByCounterpartyId.keySet();

    String searchFilter = '';
    if (String.isNotBlank(searchKey)) {
      searchFilter = '%' + searchKey.trim() + '%';
    }

    List<AXF_OBJ_Counterparty__c> counterparties;
    if (String.isNotBlank(searchFilter)) {
      counterparties = [
        SELECT
          Id,
          Name,
          AXF_CPTY_TXT_LegalName__c,
          AXF_CPTY_TXT_DisplayName__c,
          AXF_CPTY_PKL_Kind__c,
          AXF_CPTY_TXT_Country__c,
          AXF_CPTY_PKL_Status__c
        FROM AXF_OBJ_Counterparty__c
        WHERE Id IN :counterpartyIds
          AND (AXF_CPTY_TXT_DisplayName__c LIKE :searchFilter OR AXF_CPTY_TXT_LegalName__c LIKE :searchFilter)
        ORDER BY AXF_CPTY_TXT_DisplayName__c ASC
      ];
    } else {
      counterparties = [
        SELECT
          Id,
          Name,
          AXF_CPTY_TXT_LegalName__c,
          AXF_CPTY_TXT_DisplayName__c,
          AXF_CPTY_PKL_Kind__c,
          AXF_CPTY_TXT_Country__c,
          AXF_CPTY_PKL_Status__c
        FROM AXF_OBJ_Counterparty__c
        WHERE Id IN :counterpartyIds
        ORDER BY AXF_CPTY_TXT_DisplayName__c ASC
      ];
    }

    // Busca identificadores fiscais mascarados
    Map<Id, AXF_OBJ_CounterpartyTaxIdentifier__c> taxById = new Map<Id, AXF_OBJ_CounterpartyTaxIdentifier__c>();
    for (AXF_OBJ_CounterpartyTaxIdentifier__c tax : [
      SELECT Id, AXF_CTID_LKP_Counterparty__c, AXF_CTID_TXT_MaskedIdentifier__c, AXF_CTID_PKL_Scheme__c
      FROM AXF_OBJ_CounterpartyTaxIdentifier__c
      WHERE AXF_CTID_LKP_Counterparty__c IN :counterpartyIds
    ]) {
      taxById.put(tax.AXF_CTID_LKP_Counterparty__c, tax);
    }

    List<CounterpartySummaryDTO> summaries = new List<CounterpartySummaryDTO>();
    for (AXF_OBJ_Counterparty__c c : counterparties) {
      AXF_OBJ_CounterpartyEntityRelationship__c rel = relByCounterpartyId.get(c.Id);
      AXF_OBJ_CounterpartyTaxIdentifier__c tax = taxById.get(c.Id);

      CounterpartySummaryDTO dto = new CounterpartySummaryDTO();
      dto.counterpartyId = c.Id;
      dto.displayName = c.AXF_CPTY_TXT_DisplayName__c;
      dto.legalName = c.AXF_CPTY_TXT_LegalName__c;
      dto.kind = c.AXF_CPTY_PKL_Kind__c;
      dto.country = c.AXF_CPTY_TXT_Country__c;
      dto.status = c.AXF_CPTY_PKL_Status__c;
      dto.maskedTaxId = (tax != null) ? tax.AXF_CTID_TXT_MaskedIdentifier__c : '';
      dto.taxScheme = (tax != null) ? tax.AXF_CTID_PKL_Scheme__c : '';
      if (rel != null) {
        dto.relationshipId = rel.Id;
        dto.relationshipRole = rel.AXF_CER_PKL_Role__c;
        dto.relationshipStatus = rel.AXF_CER_PKL_Status__c;
        dto.validFrom = rel.AXF_CER_DAT_ValidFrom__c;
        dto.validTo = rel.AXF_CER_DAT_ValidTo__c;
      }
      summaries.add(dto);
    }

    return summaries;
  }

  /**
   * @description Consulta detalhada da Contraparte: retorna apenas a relação com a Entidade informada.
   * Relações com outras entidades NÃO são expostas (GF-32, AD-30).
   */
  public CounterpartyDetailDTO getCounterpartyDetail(Id counterpartyId, Id accountId) {
    if (counterpartyId == null || accountId == null) {
      throw new AXF_CLS_CounterpartyException('ID da Contraparte e ID da Entidade são obrigatórios.');
    }

    // Valida acesso à Entidade
    List<Account> accounts = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      throw new AXF_CLS_CounterpartyException('Acesso negado ou Entidade não encontrada.');
    }

    // Busca a Contraparte
    List<AXF_OBJ_Counterparty__c> counterparties = [
      SELECT
        Id,
        Name,
        AXF_CPTY_TXT_LegalName__c,
        AXF_CPTY_TXT_DisplayName__c,
        AXF_CPTY_PKL_Kind__c,
        AXF_CPTY_TXT_Country__c,
        AXF_CPTY_PKL_Status__c,
        AXF_CPTY_NUM_Version__c
      FROM AXF_OBJ_Counterparty__c
      WHERE Id = :counterpartyId
      LIMIT 1
    ];
    if (counterparties.isEmpty()) {
      throw new AXF_CLS_CounterpartyException('Contraparte não encontrada ou acesso negado.');
    }
    AXF_OBJ_Counterparty__c cpty = counterparties[0];

    // Busca ESTRITAMENTE a relação desta Contraparte com ESTA Entidade (Account)
    List<AXF_OBJ_CounterpartyEntityRelationship__c> relationships = [
      SELECT
        Id,
        AXF_CER_LKP_Account__c,
        AXF_CER_LKP_Account__r.Name,
        AXF_CER_PKL_Role__c,
        AXF_CER_PKL_Status__c,
        AXF_CER_TXT_EntitySpecificDisplay__c,
        AXF_CER_DAT_ValidFrom__c,
        AXF_CER_DAT_ValidTo__c,
        AXF_CER_TAL_AddressSnapshot__c,
        AXF_CER_EML_Email__c,
        AXF_CER_PHN_Phone__c,
        AXF_CER_TXT_ContactName__c,
        AXF_CER_NUM_Version__c
      FROM AXF_OBJ_CounterpartyEntityRelationship__c
      WHERE AXF_CER_LKP_Counterparty__c = :counterpartyId
        AND AXF_CER_LKP_Account__c = :accountId
      LIMIT 1
    ];

    // Busca identificador fiscal mascarado
    List<AXF_OBJ_CounterpartyTaxIdentifier__c> taxIdentifiers = [
      SELECT
        Id,
        AXF_CTID_PKL_Scheme__c,
        AXF_CTID_TXT_IssuingCountry__c,
        AXF_CTID_TXT_MaskedIdentifier__c,
        AXF_CTID_PKL_Status__c
      FROM AXF_OBJ_CounterpartyTaxIdentifier__c
      WHERE AXF_CTID_LKP_Counterparty__c = :counterpartyId
      LIMIT 1
    ];

    CounterpartyDetailDTO dto = new CounterpartyDetailDTO();
    dto.counterpartyId = cpty.Id;
    dto.displayName = cpty.AXF_CPTY_TXT_DisplayName__c;
    dto.legalName = cpty.AXF_CPTY_TXT_LegalName__c;
    dto.kind = cpty.AXF_CPTY_PKL_Kind__c;
    dto.country = cpty.AXF_CPTY_TXT_Country__c;
    dto.status = cpty.AXF_CPTY_PKL_Status__c;
    dto.version = (cpty.AXF_CPTY_NUM_Version__c != null) ? cpty.AXF_CPTY_NUM_Version__c.longValue() : 1;

    if (!taxIdentifiers.isEmpty()) {
      AXF_OBJ_CounterpartyTaxIdentifier__c tax = taxIdentifiers[0];
      dto.maskedTaxId = tax.AXF_CTID_TXT_MaskedIdentifier__c;
      dto.taxScheme = tax.AXF_CTID_PKL_Scheme__c;
      dto.taxCountry = tax.AXF_CTID_TXT_IssuingCountry__c;
      dto.taxStatus = tax.AXF_CTID_PKL_Status__c;
    }

    if (!relationships.isEmpty()) {
      AXF_OBJ_CounterpartyEntityRelationship__c rel = relationships[0];
      dto.relationshipId = rel.Id;
      dto.accountId = rel.AXF_CER_LKP_Account__c;
      dto.entityName = rel.AXF_CER_LKP_Account__r.Name;
      dto.role = rel.AXF_CER_PKL_Role__c;
      dto.relationshipStatus = rel.AXF_CER_PKL_Status__c;
      dto.entitySpecificDisplay = rel.AXF_CER_TXT_EntitySpecificDisplay__c;
      dto.validFrom = rel.AXF_CER_DAT_ValidFrom__c;
      dto.validTo = rel.AXF_CER_DAT_ValidTo__c;
      dto.addressSnapshot = rel.AXF_CER_TAL_AddressSnapshot__c;
      dto.email = rel.AXF_CER_EML_Email__c;
      dto.phone = rel.AXF_CER_PHN_Phone__c;
      dto.contactName = rel.AXF_CER_TXT_ContactName__c;
      dto.relationshipVersion = (rel.AXF_CER_NUM_Version__c != null) ? rel.AXF_CER_NUM_Version__c.longValue() : 1;
    }

    return dto;
  }

  /**
   * @description Cria ou atualiza uma Contraparte e sua Relação com a Entidade.
   */
  public OperationResultDTO createOrUpdateCounterpartyAndRelationship(CounterpartyInputDTO input) {
    if (input == null) {
      throw new AXF_CLS_CounterpartyException('Payload de entrada é obrigatório.');
    }
    if (input.accountId == null) {
      throw new AXF_CLS_CounterpartyException('A Entidade titular (Account) é obrigatória.');
    }
    if (String.isBlank(input.legalName)) {
      throw new AXF_CLS_CounterpartyException('O Nome Legal é obrigatório.');
    }
    if (String.isBlank(input.displayName)) {
      throw new AXF_CLS_CounterpartyException('O Nome de Exibição é obrigatório.');
    }
    if (String.isBlank(input.country) || input.country.trim().length() != 2) {
      throw new AXF_CLS_CounterpartyException('O País ISO de 2 letras é obrigatório.');
    }
    if (String.isBlank(input.role)) {
      throw new AXF_CLS_CounterpartyException('O Papel na relação contratual é obrigatório.');
    }
    if (input.validFrom != null && input.validTo != null && input.validTo < input.validFrom) {
      throw new AXF_CLS_CounterpartyException('A data de término (Válido Até) não pode ser anterior à data de início.');
    }

    // Valida autorização do usuário sobre a Entidade
    List<Account> accounts = [
      SELECT Id, Name, OwnerId
      FROM Account
      WHERE Id = :input.accountId
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      throw new AXF_CLS_CounterpartyException('Acesso negado ou Entidade não encontrada.');
    }
    Id entityOwnerId = accounts[0].OwnerId;

    String cptyKey = computeCounterpartyKey(input.legalName, input.country);

    // 1. Localiza ou instancia Contraparte
    AXF_OBJ_Counterparty__c cpty;
    if (input.counterpartyId != null) {
      List<AXF_OBJ_Counterparty__c> existing = [
        SELECT Id, AXF_CPTY_NUM_Version__c, AXF_CPTY_EXI_CounterpartyKey__c
        FROM AXF_OBJ_Counterparty__c
        WHERE Id = :input.counterpartyId
        LIMIT 1
      ];
      if (existing.isEmpty()) {
        throw new AXF_CLS_CounterpartyException('Contraparte informada não encontrada.');
      }
      cpty = existing[0];
      // Concorrência otimista
      if (input.version != null && cpty.AXF_CPTY_NUM_Version__c != null && cpty.AXF_CPTY_NUM_Version__c != input.version) {
        throw new AXF_CLS_CounterpartyException('Conflito de concorrência: a contraparte foi alterada por outro processo.');
      }
      cpty.AXF_CPTY_NUM_Version__c = (cpty.AXF_CPTY_NUM_Version__c != null ? cpty.AXF_CPTY_NUM_Version__c + 1 : 2);
    } else {
      // Verifica se já existe por chave enquadrada
      List<AXF_OBJ_Counterparty__c> existingByKey = [
        SELECT Id, AXF_CPTY_NUM_Version__c, AXF_CPTY_EXI_CounterpartyKey__c
        FROM AXF_OBJ_Counterparty__c
        WHERE AXF_CPTY_EXI_CounterpartyKey__c = :cptyKey
        LIMIT 1
      ];
      if (!existingByKey.isEmpty()) {
        cpty = existingByKey[0];
        cpty.AXF_CPTY_NUM_Version__c = (cpty.AXF_CPTY_NUM_Version__c != null ? cpty.AXF_CPTY_NUM_Version__c + 1 : 2);
      } else {
        cpty = new AXF_OBJ_Counterparty__c();
        cpty.AXF_CPTY_EXI_CounterpartyKey__c = cptyKey;
        cpty.AXF_CPTY_NUM_Version__c = 1;
      }
    }

    cpty.Name = input.displayName.trim();
    cpty.AXF_CPTY_TXT_DisplayName__c = input.displayName.trim();
    cpty.AXF_CPTY_TXT_LegalName__c = input.legalName.trim();
    cpty.AXF_CPTY_TXT_Country__c = input.country.trim().toUpperCase();
    cpty.AXF_CPTY_PKL_Kind__c = String.isNotBlank(input.kind) ? input.kind : 'ORGANIZATION';
    cpty.AXF_CPTY_PKL_Status__c = String.isNotBlank(input.status) ? input.status : 'ACTIVE';

    upsert cpty;

    // 2. Processa Identificador Fiscal (AD-30: apenas máscara e digest HMAC versionado)
    if (String.isNotBlank(input.taxRawDocument)) {
      String scheme = String.isNotBlank(input.taxScheme) ? input.taxScheme.toUpperCase() : 'OTHER';
      String issuingCountry = String.isNotBlank(input.taxCountry) ? input.taxCountry.toUpperCase() : input.country.toUpperCase();
      String masked = formatMaskedTaxId(input.taxRawDocument, scheme);
      String digest = computeTaxDigest(input.taxRawDocument, scheme, issuingCountry);
      String taxKey = computeTaxIdentifierKey(cpty.Id, scheme, issuingCountry, digest);

      List<AXF_OBJ_CounterpartyTaxIdentifier__c> existingTaxes = [
        SELECT Id, AXF_CTID_NUM_KeyVersion__c
        FROM AXF_OBJ_CounterpartyTaxIdentifier__c
        WHERE AXF_CTID_LKP_Counterparty__c = :cpty.Id
          AND AXF_CTID_PKL_Scheme__c = :scheme
        LIMIT 1
      ];

      AXF_OBJ_CounterpartyTaxIdentifier__c taxRec;
      if (!existingTaxes.isEmpty()) {
        taxRec = existingTaxes[0];
        taxRec.AXF_CTID_NUM_KeyVersion__c = (taxRec.AXF_CTID_NUM_KeyVersion__c != null ? taxRec.AXF_CTID_NUM_KeyVersion__c + 1 : 2);
      } else {
        taxRec = new AXF_OBJ_CounterpartyTaxIdentifier__c();
        taxRec.AXF_CTID_LKP_Counterparty__c = cpty.Id;
        taxRec.AXF_CTID_PKL_Scheme__c = scheme;
        taxRec.AXF_CTID_NUM_KeyVersion__c = 1;
      }
      taxRec.AXF_CTID_TXT_IssuingCountry__c = issuingCountry;
      taxRec.AXF_CTID_TXT_MaskedIdentifier__c = masked;
      taxRec.AXF_CTID_TXT_SearchDigest__c = digest;
      taxRec.AXF_CTID_PKL_Status__c = 'VERIFIED';
      taxRec.AXF_CTID_EXI_TaxIdentifierKey__c = taxKey;

      upsert taxRec;
    }

    // 3. Processa a Relação contextualizada com a Entidade (CounterpartyEntityRelationship)
    String relKey = computeRelationshipKey(cpty.Id, input.accountId, input.role);

    AXF_OBJ_CounterpartyEntityRelationship__c rel;
    if (input.relationshipId != null) {
      List<AXF_OBJ_CounterpartyEntityRelationship__c> existingRel = [
        SELECT Id, AXF_CER_NUM_Version__c
        FROM AXF_OBJ_CounterpartyEntityRelationship__c
        WHERE Id = :input.relationshipId
        LIMIT 1
      ];
      if (existingRel.isEmpty()) {
        throw new AXF_CLS_CounterpartyException('Relação informada não encontrada.');
      }
      rel = existingRel[0];
      if (input.relationshipVersion != null && rel.AXF_CER_NUM_Version__c != null && rel.AXF_CER_NUM_Version__c != input.relationshipVersion) {
        throw new AXF_CLS_CounterpartyException('Conflito de concorrência: a relação foi alterada por outro processo.');
      }
      rel.AXF_CER_NUM_Version__c = (rel.AXF_CER_NUM_Version__c != null ? rel.AXF_CER_NUM_Version__c + 1 : 2);
    } else {
      List<AXF_OBJ_CounterpartyEntityRelationship__c> existingByKey = [
        SELECT Id, AXF_CER_NUM_Version__c
        FROM AXF_OBJ_CounterpartyEntityRelationship__c
        WHERE AXF_CER_EXI_RelationshipKey__c = :relKey
        LIMIT 1
      ];
      if (!existingByKey.isEmpty()) {
        rel = existingByKey[0];
        rel.AXF_CER_NUM_Version__c = (rel.AXF_CER_NUM_Version__c != null ? rel.AXF_CER_NUM_Version__c + 1 : 2);
      } else {
        rel = new AXF_OBJ_CounterpartyEntityRelationship__c();
        rel.AXF_CER_LKP_Counterparty__c = cpty.Id;
        rel.AXF_CER_LKP_Account__c = input.accountId;
        rel.AXF_CER_EXI_RelationshipKey__c = relKey;
        rel.AXF_CER_NUM_Version__c = 1;
      }
    }

    rel.AXF_CER_PKL_Role__c = input.role;
    rel.AXF_CER_PKL_Status__c = String.isNotBlank(input.relationshipStatus) ? input.relationshipStatus : 'ACTIVE';
    rel.AXF_CER_TXT_EntitySpecificDisplay__c = input.entitySpecificDisplay;
    rel.AXF_CER_DAT_ValidFrom__c = input.validFrom;
    rel.AXF_CER_DAT_ValidTo__c = input.validTo;
    rel.AXF_CER_TAL_AddressSnapshot__c = input.addressSnapshot;
    rel.AXF_CER_EML_Email__c = input.email;
    rel.AXF_CER_PHN_Phone__c = input.phone;
    rel.AXF_CER_TXT_ContactName__c = input.contactName;

    upsert rel;

    // 4. Concessão de Compartilhamento Apex Managed Sharing (RowCause AXF_CounterpartyRelationAccess__c)
    grantSharingPrivileged(cpty.Id, rel.Id, entityOwnerId);

    OperationResultDTO result = new OperationResultDTO();
    result.success = true;
    result.message = 'Contraparte e relação salvas com sucesso.';
    result.counterpartyId = cpty.Id;
    result.relationshipId = rel.Id;
    return result;
  }

  /**
   * @description Concede compartilhamento gerenciado por Apex para o proprietário da Entidade (G2-3).
   * Executado em modo de sistema para gerenciar as tabelas de Share.
   */
  private static void grantSharingPrivileged(Id counterpartyId, Id relationshipId, Id entityOwnerId) {
    if (entityOwnerId == null) {
      return;
    }

    // Compartilhamento da Contraparte (Read)
    try {
      AXF_OBJ_Counterparty__Share cptyShare = new AXF_OBJ_Counterparty__Share();
      cptyShare.ParentId = counterpartyId;
      cptyShare.UserOrGroupId = entityOwnerId;
      cptyShare.AccessLevel = 'Read';
      cptyShare.RowCause = Schema.AXF_OBJ_Counterparty__Share.RowCause.AXF_CounterpartyRelationAccess__c;
      Database.insert(cptyShare, false);
    } catch (Exception e) {
      // Ignora se o usuário já possuir acesso direto ou superior
    }

    // Compartilhamento da Relação (Edit)
    try {
      AXF_OBJ_CounterpartyEntityRelationship__Share relShare = new AXF_OBJ_CounterpartyEntityRelationship__Share();
      relShare.ParentId = relationshipId;
      relShare.UserOrGroupId = entityOwnerId;
      relShare.AccessLevel = 'Edit';
      relShare.RowCause = Schema.AXF_OBJ_CounterpartyEntityRelationship__Share.RowCause.AXF_CounterpartyRelationAccess__c;
      Database.insert(relShare, false);
    } catch (Exception e) {
      // Ignora se o usuário já possuir acesso direto ou superior
    }
  }
}
