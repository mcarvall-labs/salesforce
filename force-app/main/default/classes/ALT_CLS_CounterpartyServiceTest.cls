/**
 * @description Testes unitários para ALT_CLS_CounterpartyService (AXF-51).
 * Cobre:
 * - Formatação segura e mascaramento de identificador fiscal (CPF, CNPJ, NIF, fallback).
 * - Geração de digests enquadrados e chaves determinísticas (AXF_CLS_IdentityFraming).
 * - Criação de Contraparte + Relação + Identificador Fiscal seguro.
 * - Isolamento estrito entre diferentes Entidades / Titulares (GF-32).
 * - Verificação de que documentos fiscais brutos nunca são persistidos (AD-30, GF-24).
 * - Validações de entrada e concorrência otimista.
 */
@IsTest
private class ALT_CLS_CounterpartyServiceTest {

  private static Account createTestAccount(String name) {
    Account acc = new Account(Name = name);
    Id bRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('AXF_Business')?.getRecordTypeId();
    if (bRtId != null) {
      acc.RecordTypeId = bRtId;
    }
    insert acc;
    return acc;
  }

  @IsTest
  static void testFormatMaskedTaxId() {
    // CPF
    Assert.areEqual('•••.•••.789-01', ALT_CLS_CounterpartyService.formatMaskedTaxId('12345678901', 'CPF'), 'CPF sem pontuação');
    Assert.areEqual('•••.•••.789-01', ALT_CLS_CounterpartyService.formatMaskedTaxId('123.456.789-01', 'CPF'), 'CPF com pontuação');
    Assert.areEqual('•••.•••.123', ALT_CLS_CounterpartyService.formatMaskedTaxId('123', 'CPF'), 'CPF curto');

    // CNPJ
    Assert.areEqual('••.•••.•••/0001-90', ALT_CLS_CounterpartyService.formatMaskedTaxId('12345678000190', 'CNPJ'), 'CNPJ sem pontuação');
    Assert.areEqual('••.•••.•••/0001-90', ALT_CLS_CounterpartyService.formatMaskedTaxId('12.345.678/0001-90', 'CNPJ'), 'CNPJ com pontuação');

    // NIF
    Assert.areEqual('NIF •••••6789', ALT_CLS_CounterpartyService.formatMaskedTaxId('123456789', 'NIF'), 'NIF 9 dígitos');

    // Outros / Genérico
    Assert.areEqual('••••••••5678', ALT_CLS_CounterpartyService.formatMaskedTaxId('12345678', 'OTHER'), 'Outro esquema');
    Assert.areEqual('••••12', ALT_CLS_CounterpartyService.formatMaskedTaxId('12', 'OTHER'), 'Esquema curto');

    // Casos vazios
    Assert.areEqual('', ALT_CLS_CounterpartyService.formatMaskedTaxId('', 'CPF'), 'Vazio');
    Assert.areEqual('', ALT_CLS_CounterpartyService.formatMaskedTaxId(null, 'CPF'), 'Nulo');
    Assert.areEqual('••••••••', ALT_CLS_CounterpartyService.formatMaskedTaxId('---', 'CPF'), 'Apenas caracteres especiais');
  }

  @IsTest
  static void testTaxDigestAndFramingKeys() {
    Account acc = createTestAccount('Empresa Teste Framing');

    String digest = ALT_CLS_CounterpartyService.computeTaxDigest('123.456.789-01', 'CPF', 'BR');
    Assert.isNotNull(digest, 'Digest gerado');

    String cptyKey = ALT_CLS_CounterpartyService.computeCounterpartyKey('Fornecedor Beta LTDA', 'BR');
    Assert.isNotNull(cptyKey, 'CounterpartyKey gerada');

    // Criação manual temporária para obter Id
    AXF_OBJ_Counterparty__c cpty = new AXF_OBJ_Counterparty__c(
      Name = 'Fornecedor Beta',
      AXF_CPTY_TXT_DisplayName__c = 'Fornecedor Beta',
      AXF_CPTY_TXT_LegalName__c = 'Fornecedor Beta LTDA',
      AXF_CPTY_TXT_Country__c = 'BR',
      AXF_CPTY_PKL_Kind__c = 'ORGANIZATION',
      AXF_CPTY_PKL_Status__c = 'ACTIVE',
      AXF_CPTY_EXI_CounterpartyKey__c = cptyKey,
      AXF_CPTY_NUM_Version__c = 1
    );
    insert cpty;

    String relKey = ALT_CLS_CounterpartyService.computeRelationshipKey(cpty.Id, acc.Id, 'SUPPLIER');
    Assert.isNotNull(relKey, 'RelationshipKey gerada');

    String taxKey = ALT_CLS_CounterpartyService.computeTaxIdentifierKey(cpty.Id, 'CPF', 'BR', digest);
    Assert.isNotNull(taxKey, 'TaxIdentifierKey gerada');

    // Validações de obrigatoriedade das chaves
    try {
      ALT_CLS_CounterpartyService.computeCounterpartyKey('', 'BR');
      Assert.fail('Deveria falhar sem legalName');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('obrigatórios'), 'Exceção esperada');
    }

    try {
      ALT_CLS_CounterpartyService.computeRelationshipKey(null, acc.Id, 'SUPPLIER');
      Assert.fail('Deveria falhar sem counterpartyId');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('obrigatórios'), 'Exceção esperada');
    }

    try {
      ALT_CLS_CounterpartyService.computeTaxIdentifierKey(cpty.Id, '', 'BR', digest);
      Assert.fail('Deveria falhar sem scheme');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('obrigatórios'), 'Exceção esperada');
    }
  }

  @IsTest
  static void testCreateCounterpartyAndRelationshipWithProtectedTaxId() {
    Account acc = createTestAccount('Titular Primário');
    ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();

    ALT_CLS_CounterpartyService.CounterpartyInputDTO input = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    input.accountId = acc.Id;
    input.legalName = 'Alpha Serviços de Logística LTDA';
    input.displayName = 'Alpha Logística';
    input.kind = 'ORGANIZATION';
    input.country = 'BR';
    input.status = 'ACTIVE';
    input.role = 'SUPPLIER';
    input.relationshipStatus = 'ACTIVE';
    input.entitySpecificDisplay = 'Alpha Transporte - Contrato 102';
    input.validFrom = Date.today();
    input.validTo = Date.today().addYears(1);
    input.addressSnapshot = 'Av. Brigadeiro Faria Lima, 3000, SP';
    input.email = 'contato@alphalog.com';
    input.phone = '+5511988887777';
    input.contactName = 'Roberto Silveira';
    input.taxScheme = 'CNPJ';
    input.taxCountry = 'BR';
    input.taxRawDocument = '12.345.678/0001-90';

    Test.startTest();
    ALT_CLS_CounterpartyService.OperationResultDTO result = service.createOrUpdateCounterpartyAndRelationship(input);
    Test.stopTest();

    Assert.isTrue(result.success, 'Operação executada com sucesso');
    Assert.isNotNull(result.counterpartyId, 'Id da contraparte gerado');
    Assert.isNotNull(result.relationshipId, 'Id da relação gerado');

    // 1. Valida Contraparte canônica mínima (G1, AD-30)
    AXF_OBJ_Counterparty__c cpty = [
      SELECT Id, Name, AXF_CPTY_TXT_LegalName__c, AXF_CPTY_TXT_DisplayName__c,
             AXF_CPTY_PKL_Kind__c, AXF_CPTY_TXT_Country__c, AXF_CPTY_PKL_Status__c,
             AXF_CPTY_EXI_CounterpartyKey__c, AXF_CPTY_NUM_Version__c
      FROM AXF_OBJ_Counterparty__c
      WHERE Id = :result.counterpartyId
    ];
    Assert.areEqual('Alpha Logística', cpty.Name);
    Assert.areEqual('Alpha Logística', cpty.AXF_CPTY_TXT_DisplayName__c);
    Assert.areEqual('Alpha Serviços de Logística LTDA', cpty.AXF_CPTY_TXT_LegalName__c);
    Assert.areEqual('BR', cpty.AXF_CPTY_TXT_Country__c);
    Assert.areEqual('ORGANIZATION', cpty.AXF_CPTY_PKL_Kind__c);
    Assert.areEqual('ACTIVE', cpty.AXF_CPTY_PKL_Status__c);
    Assert.areEqual(1, cpty.AXF_CPTY_NUM_Version__c);

    // 2. Valida Identificador Fiscal protegido (AD-30, GF-24)
    List<AXF_OBJ_CounterpartyTaxIdentifier__c> taxList = [
      SELECT Id, AXF_CTID_PKL_Scheme__c, AXF_CTID_TXT_IssuingCountry__c,
             AXF_CTID_TXT_MaskedIdentifier__c, AXF_CTID_TXT_SearchDigest__c,
             AXF_CTID_NUM_KeyVersion__c, AXF_CTID_PKL_Status__c
      FROM AXF_OBJ_CounterpartyTaxIdentifier__c
      WHERE AXF_CTID_LKP_Counterparty__c = :result.counterpartyId
    ];
    Assert.areEqual(1, taxList.size(), 'Um registro de identificador fiscal');
    AXF_OBJ_CounterpartyTaxIdentifier__c taxRec = taxList[0];
    Assert.areEqual('CNPJ', taxRec.AXF_CTID_PKL_Scheme__c);
    Assert.areEqual('BR', taxRec.AXF_CTID_TXT_IssuingCountry__c);
    Assert.areEqual('••.•••.•••/0001-90', taxRec.AXF_CTID_TXT_MaskedIdentifier__c, 'Deve armazenar apenas a máscara');
    Assert.isNotNull(taxRec.AXF_CTID_TXT_SearchDigest__c, 'Digest SHA-256 enquadrado');
    Assert.areNotEqual('12.345.678/0001-90', taxRec.AXF_CTID_TXT_MaskedIdentifier__c, 'Nunca deve armazenar o valor bruto');
    Assert.areNotEqual('12345678000190', taxRec.AXF_CTID_TXT_MaskedIdentifier__c, 'Nunca deve armazenar o valor bruto sem pontuação');

    // 3. Valida Relação estritamente contextualizada (G2, GF-32)
    AXF_OBJ_CounterpartyEntityRelationship__c rel = [
      SELECT Id, AXF_CER_LKP_Counterparty__c, AXF_CER_LKP_Account__c,
             AXF_CER_PKL_Role__c, AXF_CER_PKL_Status__c, AXF_CER_TXT_EntitySpecificDisplay__c,
             AXF_CER_DAT_ValidFrom__c, AXF_CER_DAT_ValidTo__c, AXF_CER_TAL_AddressSnapshot__c,
             AXF_CER_EML_Email__c, AXF_CER_PHN_Phone__c, AXF_CER_TXT_ContactName__c,
             AXF_CER_NUM_Version__c
      FROM AXF_OBJ_CounterpartyEntityRelationship__c
      WHERE Id = :result.relationshipId
    ];
    Assert.areEqual(cpty.Id, rel.AXF_CER_LKP_Counterparty__c);
    Assert.areEqual(acc.Id, rel.AXF_CER_LKP_Account__c);
    Assert.areEqual('SUPPLIER', rel.AXF_CER_PKL_Role__c);
    Assert.areEqual('Alpha Transporte - Contrato 102', rel.AXF_CER_TXT_EntitySpecificDisplay__c);
    Assert.areEqual('Av. Brigadeiro Faria Lima, 3000, SP', rel.AXF_CER_TAL_AddressSnapshot__c);
    Assert.areEqual('contato@alphalog.com', rel.AXF_CER_EML_Email__c);
    Assert.areEqual(1, rel.AXF_CER_NUM_Version__c);
  }

  @IsTest
  static void testCrossEntityQueryIsolationGF32() {
    Account entityA = createTestAccount('Entidade Alpha SA');
    Account entityB = createTestAccount('Entidade Beta LTDA');

    ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();

    // 1. Cadastra Contraparte e Relação para Entidade A (como SUPPLIER)
    ALT_CLS_CounterpartyService.CounterpartyInputDTO inputA = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    inputA.accountId = entityA.Id;
    inputA.legalName = 'Consultoria Delta Global S.A.';
    inputA.displayName = 'Delta Global';
    inputA.kind = 'ORGANIZATION';
    inputA.country = 'BR';
    inputA.role = 'SUPPLIER';
    inputA.entitySpecificDisplay = 'Delta - Prestador TI Alpha';
    inputA.addressSnapshot = 'Rua A, 100';
    inputA.email = 'suporte@deltaglobal.com';

    ALT_CLS_CounterpartyService.OperationResultDTO resultA = service.createOrUpdateCounterpartyAndRelationship(inputA);
    Id cptyId = resultA.counterpartyId;

    // 2. Vincula a mesma contraparte na Entidade B (como CUSTOMER), com dados contextuais diferentes
    ALT_CLS_CounterpartyService.CounterpartyInputDTO inputB = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    inputB.counterpartyId = cptyId;
    inputB.accountId = entityB.Id;
    inputB.legalName = 'Consultoria Delta Global S.A.';
    inputB.displayName = 'Delta Global';
    inputB.kind = 'ORGANIZATION';
    inputB.country = 'BR';
    inputB.role = 'CLIENT';
    inputB.entitySpecificDisplay = 'Delta - Cliente Estratégico Beta';
    inputB.addressSnapshot = 'Av. B, 500';
    inputB.email = 'comercial@deltaglobal.com';

    ALT_CLS_CounterpartyService.OperationResultDTO resultB = service.createOrUpdateCounterpartyAndRelationship(inputB);
    Assert.areEqual(cptyId, resultB.counterpartyId, 'Reutiliza a mesma identidade de contraparte');
    Assert.areNotEqual(resultA.relationshipId, resultB.relationshipId, 'Gera relação distinta para a Entidade B');

    // 3. Consulta no contexto da Entidade A (GF-32)
    List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> listA = service.getCounterpartiesForEntity(entityA.Id, null);
    Assert.areEqual(1, listA.size(), 'Entidade A visualiza 1 contraparte');
    Assert.areEqual('SUPPLIER', listA[0].relationshipRole, 'Papel no escopo da Entidade A');
    Assert.areEqual(resultA.relationshipId, listA[0].relationshipId, 'Relação da Entidade A');

    ALT_CLS_CounterpartyService.CounterpartyDetailDTO detailA = service.getCounterpartyDetail(cptyId, entityA.Id);
    Assert.areEqual(entityA.Id, detailA.accountId, 'Contexto retornado pertence a Entidade A');
    Assert.areEqual('SUPPLIER', detailA.role);
    Assert.areEqual('Delta - Prestador TI Alpha', detailA.entitySpecificDisplay);
    Assert.areEqual('Rua A, 100', detailA.addressSnapshot);
    Assert.areEqual('suporte@deltaglobal.com', detailA.email);

    // 4. Consulta no contexto da Entidade B (GF-32)
    List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> listB = service.getCounterpartiesForEntity(entityB.Id, null);
    Assert.areEqual(1, listB.size(), 'Entidade B visualiza 1 contraparte');
    Assert.areEqual('CLIENT', listB[0].relationshipRole, 'Papel no escopo da Entidade B');
    Assert.areEqual(resultB.relationshipId, listB[0].relationshipId, 'Relação da Entidade B');

    ALT_CLS_CounterpartyService.CounterpartyDetailDTO detailB = service.getCounterpartyDetail(cptyId, entityB.Id);
    Assert.areEqual(entityB.Id, detailB.accountId, 'Contexto retornado pertence a Entidade B');
    Assert.areEqual('CLIENT', detailB.role);
    Assert.areEqual('Delta - Cliente Estratégico Beta', detailB.entitySpecificDisplay);
    Assert.areEqual('Av. B, 500', detailB.addressSnapshot);
    Assert.areEqual('comercial@deltaglobal.com', detailB.email);
  }

  @IsTest
  static void testSearchFilterInCounterpartyListing() {
    Account acc = createTestAccount('Entidade Filtro');
    ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();

    ALT_CLS_CounterpartyService.CounterpartyInputDTO in1 = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    in1.accountId = acc.Id;
    in1.legalName = 'XPTO Seguros SA';
    in1.displayName = 'XPTO Seguros';
    in1.country = 'BR';
    in1.role = 'SERVICE_PROVIDER';
    service.createOrUpdateCounterpartyAndRelationship(in1);

    ALT_CLS_CounterpartyService.CounterpartyInputDTO in2 = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    in2.accountId = acc.Id;
    in2.legalName = 'Zeta Tecnologia LTDA';
    in2.displayName = 'Zeta Tech';
    in2.country = 'BR';
    in2.role = 'SUPPLIER';
    service.createOrUpdateCounterpartyAndRelationship(in2);

    List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> searchXPTO = service.getCounterpartiesForEntity(acc.Id, 'XPTO');
    Assert.areEqual(1, searchXPTO.size());
    Assert.areEqual('XPTO Seguros', searchXPTO[0].displayName);

    List<ALT_CLS_CounterpartyService.CounterpartySummaryDTO> searchNone = service.getCounterpartiesForEntity(acc.Id, 'NenhumExiste');
    Assert.areEqual(0, searchNone.size());
  }

  @IsTest
  static void testUpdateAndOptimisticConcurrency() {
    Account acc = createTestAccount('Entidade Concorrência');
    ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();

    ALT_CLS_CounterpartyService.CounterpartyInputDTO input = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    input.accountId = acc.Id;
    input.legalName = 'Concorrência Testes S/A';
    input.displayName = 'Concorrência Testes';
    input.country = 'BR';
    input.role = 'PARTNER';

    ALT_CLS_CounterpartyService.OperationResultDTO r1 = service.createOrUpdateCounterpartyAndRelationship(input);

    // Atualização com versão correta
    input.counterpartyId = r1.counterpartyId;
    input.relationshipId = r1.relationshipId;
    input.version = 1;
    input.relationshipVersion = 1;
    input.displayName = 'Concorrência Testes Atualizado';
    input.entitySpecificDisplay = 'Parceiro Nível Ouro';

    ALT_CLS_CounterpartyService.OperationResultDTO r2 = service.createOrUpdateCounterpartyAndRelationship(input);
    Assert.isTrue(r2.success);

    AXF_OBJ_Counterparty__c cpty = [
      SELECT AXF_CPTY_NUM_Version__c
      FROM AXF_OBJ_Counterparty__c
      WHERE Id = :r1.counterpartyId
    ];
    Assert.areEqual(2, cpty.AXF_CPTY_NUM_Version__c, 'Versão da contraparte incrementada para 2');

    // Tentativa de salvar contraparte com versão desatualizada (1 em vez de 2)
    input.version = 1;
    input.relationshipVersion = 2;
    try {
      service.createOrUpdateCounterpartyAndRelationship(input);
      Assert.fail('Deveria lançar erro de conflito de concorrência na contraparte');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('Conflito de concorrência'), 'Mensagem esperada');
    }

    // Tentativa de salvar relação com versão desatualizada (1 em vez de 2)
    input.version = 2;
    input.relationshipVersion = 1;
    try {
      service.createOrUpdateCounterpartyAndRelationship(input);
      Assert.fail('Deveria lançar erro de conflito de concorrência na relação');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('Conflito de concorrência'), 'Mensagem esperada');
    }
  }

  @IsTest
  static void testValidationExceptions() {
    ALT_CLS_CounterpartyService service = new ALT_CLS_CounterpartyService();

    // Payload nulo
    try {
      service.createOrUpdateCounterpartyAndRelationship(null);
      Assert.fail('Deveria falhar com payload nulo');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('Payload'), 'Exceção esperada');
    }

    // Account nula
    ALT_CLS_CounterpartyService.CounterpartyInputDTO inDTO = new ALT_CLS_CounterpartyService.CounterpartyInputDTO();
    try {
      service.createOrUpdateCounterpartyAndRelationship(inDTO);
      Assert.fail('Deveria falhar sem accountId');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('Entidade titular'), 'Exceção esperada');
    }

    // País inválido
    Account acc = createTestAccount('Entidade Validações');
    inDTO.accountId = acc.Id;
    inDTO.legalName = 'Nome Legal';
    inDTO.displayName = 'Nome Exibição';
    inDTO.country = 'BRA'; // > 2 caracteres
    inDTO.role = 'SUPPLIER';

    try {
      service.createOrUpdateCounterpartyAndRelationship(inDTO);
      Assert.fail('Deveria falhar com país com mais de 2 letras');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('2 letras'), 'Exceção esperada');
    }

    // Datas inválidas: validTo < validFrom
    inDTO.country = 'BR';
    inDTO.validFrom = Date.today();
    inDTO.validTo = Date.today().addDays(-5);
    try {
      service.createOrUpdateCounterpartyAndRelationship(inDTO);
      Assert.fail('Deveria falhar com data final anterior à inicial');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('Válido Até'), 'Exceção esperada');
    }

    // Consulta com accountId nulo
    try {
      service.getCounterpartiesForEntity(null, null);
      Assert.fail('Deveria falhar com accountId nulo');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('obrigatório'), 'Exceção esperada');
    }

    // Detalhe com IDs nulos
    try {
      service.getCounterpartyDetail(null, acc.Id);
      Assert.fail('Deveria falhar com counterpartyId nulo');
    } catch (AXF_CLS_CounterpartyException e) {
      Assert.isTrue(e.getMessage().contains('obrigatórios'), 'Exceção esperada');
    }
  }
}
