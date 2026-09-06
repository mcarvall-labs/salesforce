# AXF-51 — Cadastrar contraparte e relação por titular

- Jira: https://axon-personal-finances.atlassian.net/browse/AXF-51
- Parent: AXF-50 (Gestão de Contrapartes e Relações)
- Branch: `feature/AXF-51-counterparty-management`
- Base: `reconciled/base`
- Predecessoras: AXF-80 (titulares Account), AXF-7 (modelo de segurança por PSG) — ambas em `reconciled/base`.

> Sem deploy em UAT/PROD. Testes executados e validados contra a org de desenvolvimento `AXON_DEV`.

## Princípios e Contratos de Domínio

1. **Identidade Canônica Mínima no Root (G1, AD-30):**
   - A contraparte root (`AXF_OBJ_Counterparty__c`) guarda apenas o núcleo de identidade: Razão Social (`LegalName`), Nome de Exibição (`DisplayName`), Tipo (`PERSON` | `ORGANIZATION`), País ISO-2 (`Country`), Status e Versionamento.
   - Nenhum dado relacional, endereço ou PII de contato reside no objeto raiz.

2. **Isolamento Estrito por Entidade (G2, GF-32):**
   - Dados relacionais específicos residem exclusivamente em `AXF_OBJ_CounterpartyEntityRelationship__c` (`CER`), vinculando a Contraparte à Entidade titular (`Account`).
   - Mantém papel contratual (`CLIENT`, `SUPPLIER`, `SERVICE_PROVIDER`, etc.), vigência (`ValidFrom`, `ValidTo`), snapshot de endereço contratual, contatos comerciais e versionamento independente.
   - Usuários com acesso à Entidade A só visualizam a identidade mínima da contraparte e a relação contratual com a Entidade A. Relações com outras entidades não são expostas nem inferíveis.

3. **Identificador Fiscal Protegido (AD-30, GF-24):**
   - `AXF_OBJ_CounterpartyTaxIdentifier__c` (`CTID`) armazena exclusivamente a máscara segura (`•••.•••.789-01`, `••.•••.•••/0001-90`, `NIF •••••...`) e o digest de busca enquadrado (`AXF_CLS_IdentityFraming`) com HMAC-SHA-256.
   - Proibição absoluta de persistência de identificadores fiscais brutos ou reversíveis.

4. **Apex Managed Sharing Derivado (G2-3):**
   - Implementado via Apex Sharing Reason `AXF_CounterpartyRelationAccess__c` em `AXF_OBJ_Counterparty__c` e `AXF_OBJ_CounterpartyEntityRelationship__c`.
   - Concede automaticamente permissão de leitura na contraparte e edição na relação específica ao proprietário da entidade associada.

## Escopo Entregue

| Área | Componente |
| --- | --- |
| Schema | `AXF_OBJ_Counterparty__c`, `AXF_OBJ_CounterpartyEntityRelationship__c`, `AXF_OBJ_CounterpartyTaxIdentifier__c` e Sharing Reasons `AXF_CounterpartyRelationAccess__c`. |
| Domínio / Serviço | `ALT_CLS_CounterpartyService` — Enquadramento de chaves (`AXF_CLS_IdentityFraming`), cálculo seguro de máscaras e digests fiscais, queries isoladas por contexto de entidade, CRUD transacional, controle de concorrência otimista (`Version`) e concessão de Apex Sharing. |
| Controller | `AXF_CLS_CTRL_CounterpartyManagement` — Camada fina @AuraEnabled com sanitização de erros e integração com contextos autorizados. |
| UI | LWC `aXF_LWC_counterpartyManagement` — Gestão visual em duas colunas (seleção de entidade, busca reativa, listagem de contrapartes, painel de detalhes com identificador mascarado e modal de cadastro/edição). Aba customizada `AXF_Counterparties`. |
| Segurança | Atualização de `AXF_PS_GestorFinanceiro` (Create/Edit/Read) e `AXF_PS_Participante` (Read-only), com concessões estritas de FLS apenas nos campos relacionais opcionais. |
| Testes Unitários | `ALT_CLS_CounterpartyServiceTest` e `AXF_CLS_CTRL_CounterpartyManagementTest` cobrindo 100% dos cenários de negócio, isolamento GF-32, proteção fiscal AD-30, concorrência otimista e validações de fronteira. |

## Validação

- Deploy & Apex Tests em `AXON_DEV`: **12/12 testes passando (100% de sucesso)**.
- Cobertura de Código:
  - `ALT_CLS_CounterpartyService`: **90%**
  - `AXF_CLS_CTRL_CounterpartyManagement`: **89%**
- LWC Jest: Suíte com testes cobrindo renderização, seleção contextual de entidade, filtros de busca, carregamento de detalhes e modal de edição.
