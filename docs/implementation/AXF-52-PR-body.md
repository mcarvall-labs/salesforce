## Summary

Implementação da história **AXF-52: Criar um Contrato em rascunho** (Epic AXF-50).

Esta entrega estabelece o aggregate root privado de Contratos (`AXF_OBJ_Contract__c`), vinculando-o canonicamente a uma Entidade titular (`Account`) e a uma relação contextual ativa com contraparte (`AXF_OBJ_CounterpartyEntityRelationship__c`).

### Principais Entregas
- **Schema & Modelo de Dados:**
  - `AXF_OBJ_Contract__c` (CTR): Aggregate root privado com lookups restritos a `Account`, `AXF_OBJ_Counterparty__c` e `AXF_OBJ_CounterpartyEntityRelationship__c`.
  - Chave canônica determinística única: `AXF_CTR_EXI_ContractKey__c` calculada via `AXF_CLS_IdentityFraming` como `sha256Hex(frame('CONTRACT', accountId, contractCode))`.
  - Apex Managed Sharing: RowCause `AXF_ContractAccess__c` concedendo acesso ao proprietário da Entidade titular.
  - Aba customizada `AXF_Contracts`.
- **Serviço de Domínio (`ALT_CLS_ContractService`):**
  - Validação estrita de compatibilidade entre a Entidade titular e a relação com a contraparte (rejeição de relações de outros titulares ou inativas).
  - Criação inicial garantida em ciclo de vida canônico `DRAFT`.
  - Edição de campos não efetivos do rascunho com controle de concorrência otimista (`expectedVersion` via `AXF_CTR_NUM_Version__c`).
  - Suporte a idempotência via `AXF_CTR_EXI_ClientRequestId__c` (detecção de replay idêntico vs conflito divergente).
  - Invariante financeira estrita: nenhum `FinancialTransaction` ou documento é gerado no rascunho.
  - Bloqueio canônico de transições de ciclo de vida prematuras (término, cancelamento ou substituição bloqueados até as histórias autoritativas AXF-53+).
- **Camada Controller & UI:**
  - `AXF_CLS_CTRL_ContractManagement`: Controller fino `@AuraEnabled` com sanitização e mapeamento para contextos autorizados.
  - LWC `aXF_LWC_contractManagement`: Interface mestre-detalhe SLDS acessível com seleção de entidade, tabela de contratos, visualização de detalhes e modal de criação/edição.
- **Segurança e Permissões:**
  - Atualização dos Permission Sets `AXF_PS_GestorFinanceiro` (CRUD exceto Delete) e `AXF_PS_Participante` (Read-only).
- **Qualidade & Testes:**
  - Testes Apex unitários: `ALT_CLS_ContractServiceTest` e `AXF_CLS_CTRL_ContractManagementTest` (15/15 passando, 90% de cobertura do serviço).
  - Testes Jest LWC: 18/18 suítes passando (101/101 testes).
  - Deploy efetuado e validado na org `AXON_DEV`.
