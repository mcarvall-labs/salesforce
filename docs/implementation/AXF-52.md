# AXF-52 — Criar um Contrato em rascunho

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-52
- Parent: AXF-50 (Contratos, termos e agenda auditável)
- Branch: `feature/AXF-52-draft-contract`
- Base: `reconciled/base`
- Predecessora: AXF-51 (Cadastrar contraparte e relação por titular)

> Sem deploy em UAT/PROD. Testes executados e validados contra a org de desenvolvimento `AXON_DEV`.

## Princípios e Contratos de Domínio

1. **Root Canônico Privado Vinculado a Entidade e Relação (AC 1, G1, AD-14, AD-30):**
   - O contrato (`AXF_OBJ_Contract__c`, prefixo CTR) é um aggregate root com modelo de compartilhamento `Private`.
   - Referencia estritamente a Entidade titular (`Account`, required `AXF_CTR_LKP_Account__c`), a Contraparte (`AXF_OBJ_Counterparty__c`, required `AXF_CTR_LKP_Counterparty__c`) e a Relação contextual com a contraparte (`AXF_OBJ_CounterpartyEntityRelationship__c`, required `AXF_CTR_LKP_Relationship__c`).
   - Rejeição estrita de relações contratuais pertencentes a outra entidade ou que não estejam no estado `ACTIVE`.

2. **Chave Canônica Determinística e Identidade Imutável (AC 1, AC 3, G6):**
   - Chave determinística única por Entidade e Código calculada via `AXF_CLS_IdentityFraming`:
     `sha256Hex(frame('CONTRACT', accountId, contractCode))`.
   - Armazenada em `AXF_CTR_EXI_ContractKey__c` (Unique External ID), impedindo colisão ou duplicidade de códigos no mesmo titular.
   - Entidade titular e código do contrato tornam-se estritamente imutáveis após a criação.

3. **Ciclo de Vida Canônico e Edição de Rascunho (AC 1, AC 2, AD-14):**
   - Todo contrato inicia obrigatoriamente no estado `DRAFT`.
   - Apenas contratos em `DRAFT` permitem edição de dados não efetivos (Título, Tipo de Contrato, Moeda, Vigência Prevista e Descrição/Objeto).
   - Controle de concorrência otimista com `expectedVersion` via `AXF_CTR_NUM_Version__c`. Em caso de versão defasada, a operação é rejeitada com conflito.
   - Suporte a idempotência via `AXF_CTR_EXI_ClientRequestId__c` com repetição segura (replay idempotente) e rejeição em caso de payload divergente.

4. **Invariante Financeira e Ausência de Efeitos Colaterais Implícitos (AC 2):**
   - NENHUM lançamento financeiro (`AXF_OBJ_FinancialTransaction__c`), CashFlow, documento fiscal/faturamento ou cronograma é gerado implicitamente durante o cadastro ou edição de rascunhos de contratos.

5. **Bloqueio de Operações de Término, Cancelamento e Substituição (AC 3):**
   - Tentativas de transição de ciclo de vida para `CANCELLED`, `ENDED`, `TERMINATED`, `REPLACED` ou `ACTIVE` são bloqueadas canonicamente, pois as operações autoritativas correspondentes pertencem a histórias posteriores da esteira (AXF-53, AXF-54, AXF-55).

6. **Apex Managed Sharing (G2):**
   - Implementado via Apex Sharing Reason `AXF_ContractAccess__c` em `AXF_OBJ_Contract__c`, concedendo acesso de edição ao proprietário da entidade titular (`Account.OwnerId`).

## Escopo Entregue

| Área | Componente |
| --- | --- |
| Schema | Objeto customizado `AXF_OBJ_Contract__c`, campos relacionais, chaves canônicas e Apex Sharing Reason `AXF_ContractAccess__c`. Aba customizada `AXF_Contracts`. |
| Domínio / Serviço | `ALT_CLS_ContractService` — Validação estrita de titular e relação ativa, enquadramento de chave canônica (`AXF_CLS_IdentityFraming`), criação em `DRAFT`, edição com controle de concorrência otimista (`Version`), replay idempotente (`ClientRequestId`), bloqueio de operações prematuras de lifecycle e concessão de Apex Sharing. |
| Exceções | `AXF_CLS_ContractException` — Exceção tipada de domínio contratual. |
| Controller | `AXF_CLS_CTRL_ContractManagement` — Controller fino @AuraEnabled com sanitização de exceções e mapeamento com contextos autorizados. |
| UI | LWC `aXF_LWC_contractManagement` — Interface completa em conformidade com SLDS para gestão de contratos por entidade titular, tabela com busca/status, visualização detalhada e modal de criação/edição com foco acessível. |
| Segurança | Atualização de Permission Sets `AXF_PS_GestorFinanceiro` (CRUD completo exceto Delete) e `AXF_PS_Participante` (Read-only), com acesso restrito a campos e classes. |
| Testes Unitários | `ALT_CLS_ContractServiceTest` e `AXF_CLS_CTRL_ContractManagementTest` cobrindo 15 cenários de negócio, concorrência, idempotência, isolamento cross-entity e invariantes financeiras. |

## Validação

- Deploy em `AXON_DEV`: **100% de sucesso (Job concluído)**.
- Apex Tests em `AXON_DEV`: **15/15 testes passando (100% de sucesso)**.
  - `ALT_CLS_ContractService`: **90% de cobertura de código**.
  - `AXF_CLS_CTRL_ContractManagement`: **75% de cobertura de código**.
- LWC Jest Tests: **18/18 suítes passando (101/101 testes)**.
- ESLint: **0 erros e 0 warnings**.
