# AXF-11 — Configurar credenciais e controlar o consentimento Pluggy

- **Jira:** https://axon-personal-finances.atlassian.net/browse/AXF-11
- **Épico:** AXF-10 — Fontes financeiras confiáveis e recuperáveis
- **Branch:** `feature/AXF-11-pluggy-credentials-consent` (base: `reconciled/base`)
- **Gates:** G1/G2/G4/G6/G7 fase de definição fechada (30/08/2026). Contrato regente:
  `ARCHITECTURE-SPINE.md` §"Fechamento G4 — credenciais e integração";
  `AXF-11-G4-investigacao-2026-08-28.md`; decisão "pausa local, sem DELETE Pluggy" (28/08/2026).
- **Baseline:** greenfield (`reconciled/base`). O código Pluggy legado do `develop` antigo
  (`AXF_CLS_PluggyAuthService`, `AXF_NC_Pluggy_API`, `AXF_EXC_Pluggy`) foi **portado com
  regressão** — ver §"Regressão do legado".

> Esta definição não autoriza deploy em UAT/PROD, exclusão, nem acesso a produção.
> Nenhum segredo real foi usado; os testes usam mocks.

---

## Revisão 31/08/2026 (decisões do Michel)

- **Entrada de credencial in-app:** o wizard/tela é executado por um **SysAdmin** (org
  configurator), então `AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential` /
  `stageCandidateCredential` encaminham Client ID/Secret direto ao mecanismo nativo via
  `AXF_CLS_PluggyCredentialWriter` → `ConnectApi.NamedCredentials.updateCredential/createCredential`
  (trânsito em memória, nunca gravado/logado). Não é mais passo de Setup. O SysAdmin já tem
  "Manage Named Credentials" pelo profile; nenhum PSG do Axon ganha essa permissão.
  A chamada ConnectApi é pulada sob `Test.isRunningTest()` e **precisa de um smoke test em org real** antes do 1º uso.
- **Platform Cache removido:** `AXF_CLS_PluggyAuthService` agora mantém o `apiKey` só na
  transação Apex corrente (1 `POST /auth` por transação, recomendação da investigação G4).
  Sem partition, sem `AXF_PIC_NUM_ApiKeyCacheTtlSeconds__c`.
- **Segredo do webhook:** Custom Metadata **protegida** `AXF_PluggyWebhookConfig__mdt.AXF_PWC_TXT_Secret__c`
  (não `AXF_EXC_PluggyWebhook`; valores de EC não são legíveis em Apex para HMAC local — G4-3 permite CMT protegida).
- **`AXF_PS_GestorFinanceiro` perdeu o acesso ao principal das ECs.** "Saúde das fontes" para
  o Gestor = leitura + pausa local (DML, sem callout). Resume/reautorizar (que fazem callout)
  funcionam para quem tem `AXF_PS_PluggyIntegration` (o SysAdmin configurador).
- **Webhook fica no MVP, via platform event.** O Guest User do Site (licença sem `Edit` em
  objeto e sem uso de Credencial Externa) só valida o HMAC e **publica `AXF_PluggyWebhookEvent__e`**;
  `AXF_TRG_PluggyWebhookEvent` → `AXF_CLS_PluggyWebhookEventHandler` faz a revalidação como
  usuário Automated Process. `AXF_PS_PluggyWebhookGuest` foi reduzida (só `Create` no evento +
  4 classes). Setup manual: registrar/criar Site → `AXF_PS_PluggyWebhookGuest` no guest user →
  `AXF_PS_PluggyIntegration` no Automated Process → URL no Dashboard Pluggy → secret na CMT
  `AXF Pluggy Webhook Config / Default`. Ver §10.

---

## 1. Escopo entregue

| Entrega                                                                                        | Componente                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Configuração inicial segura de credenciais (Client ID / Secret) pelo mecanismo nativo          | `AXF_EXC_Pluggy` + `AXF_NC_Pluggy_API`; `AXF_CLS_CTRL_PluggyIntegrationConfig.setPrincipalCredential` (trânsito transitório → `ConnectApi.NamedCredentials`, sem persistência/log)                                                                                                                                                               |
| Obtenção server-side do `apiKey`                                                               | `AXF_CLS_PluggyAuthService` (`apiKey` só em memória, um `POST /auth` por transação; sem Platform Cache — ver Revisão 31/08)                                                                                                                                                                                                                      |
| Rotação: testar candidata antes de promover, preservar a ativa em falha                        | `AXF_EXC_Pluggy_Candidate` + `AXF_NC_Pluggy_API_Candidate`; `AXF_CLS_PluggyCredentialRotationService` (`CANDIDATE→TESTING→PROMOTED`/`ROLLED_BACK`)                                                                                                                                                                                               |
| Consentimento: instituição, contas, escopo, finalidade, início, expiração, versão              | `AXF_OBJ_PluggyConnection__c` (campos `AXF_CON_*`); `AXF_CLS_PluggyConsentService`                                                                                                                                                                                                                                                               |
| Bloqueio antes da unidade material quando consentimento ausente/expirado/revogado/incompatível | `AXF_CLS_PluggyCollectionControlService.assertCollectionAllowed` + `AXF_CON_PKL_ConsentState__c`                                                                                                                                                                                                                                                 |
| Pausa/retomada local autorizada; revogação externa detectada                                   | `AXF_CLS_PluggyCollectionControlService` (por conexão e global); `AXF_PluggyIntegrationConfig__c.CollectionGloballyPaused__c`                                                                                                                                                                                                                    |
| Idempotência / resultado externo incerto                                                       | `AXF_CLS_PluggyHttpClient` (correlationId, sem retry cego); rotação e pausa por estado confirmado                                                                                                                                                                                                                                                |
| "Saúde das fontes" (desktop/mobile, WCAG 2.2 AA)                                               | `aXF_LWC_sourceHealth` + `AXF_CLS_CTRL_SourceHealth`; tab `AXF_SourceHealth`                                                                                                                                                                                                                                                                     |
| Webhook com validação de assinatura antes de aceitar                                           | `AXF_CLS_PluggyWebhookResource` (`/services/apexrest/pluggy/webhook`) + `AXF_CLS_PluggyWebhookSignature` (HMAC-SHA256 constant-time); segredo em `AXF_PluggyWebhookConfig__mdt` (CMT protegida). Válido → publica `AXF_PluggyWebhookEvent__e`; `AXF_TRG_PluggyWebhookEvent`/`AXF_CLS_PluggyWebhookEventHandler` revalidam fora do contexto guest |
| Sem vazamento de segredo em logs/respostas                                                     | Regressão de `AXF_CLS_PluggyAuthService` (removidos `System.debug` de request/response); sanitização central em `AXF_CLS_PluggyHttpClient`                                                                                                                                                                                                       |
| Acesso restrito ao NC / principal                                                              | `AXF_PS_PluggyIntegration` (só usuário de serviço); `AXF_CanConfigure` no servidor para configurar/rotacionar/pausar                                                                                                                                                                                                                             |

### Fora de escopo (recortes próprios)

- Descoberta de contas/cartões — **AXF-84**.
- Sincronização, `IntegrationRun`, cursores, lotes — **AXF-12**.
- Unicidade / identidade externa em reprocessamento — **AXF-13**.
- Guia ilustrado — **AXF-89** (já em `reconciled/base`).
- `DELETE /items` (revogação remota automática) — adiado (decisão 28/08/2026).
- Exposição pública do endpoint de webhook (Site / guest user) + `PermissionSetAssignment` no Automated Process — passos manuais de instalação (§10 / AXF-77).

---

## 2. Modelo de dados — `AXF_OBJ_PluggyConnection__c` / `CON`

OWD **Private** (custódia do Gestor; acesso efetivo é G2/AXF-12). Criado por esta US com os
campos que ela usa; AXF-12/AXF-84 acrescentam os seus (`SyncStatus`, `ExecutionStatus`, `IntegrationRun`).

| Campo                                                | Tipo / regra                                                                                                          | Origem             |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------ |
| `AXF_CON_EXI_PluggyItemId__c`                        | Text(64), ExternalId, **Unique**, caseSensitive, obrigatório — **chave de operação** (Item ID da aplicação/Dashboard) | G4-4 / D-85        |
| `AXF_CON_TXT_ObservedItemId__c`                      | Text(64) — Item ID observado na resposta da API; **nunca vira chave**                                                 | G4-4               |
| `AXF_CON_PKL_ConsentState__c`                        | Picklist restrita `ACTIVE\|STALE\|REVOKED`, default `ACTIVE`                                                          | G4-5 / dicionário  |
| `AXF_CON_PKL_CollectionState__c`                     | Picklist restrita `ACTIVE\|PAUSED`, default `ACTIVE` — pausa local por conexão                                        | Decisão 28/08      |
| `AXF_CON_TXT_InstitutionName__c`                     | Text(255) — instituição/conector                                                                                      | AC3, AC7           |
| `AXF_CON_TXT_ConnectorId__c`                         | Text(40)                                                                                                              | AC3                |
| `AXF_CON_TXT_ConsentId__c`                           | Text(64) — id do consentimento (`GET /consents`)                                                                      | AC3                |
| `AXF_CON_TXT_ConsentObservedItemId__c`               | Text(64) — `Consent.itemId` (pode diferir do consultado — D-85)                                                       | Investigação 28/08 |
| `AXF_CON_TAL_ConsentScope__c`                        | LongTextArea(4096) — produtos/permissões concedidos (texto, sem segredo)                                              | AC3                |
| `AXF_CON_TXT_ConsentPurpose__c`                      | Text(255) — finalidade apresentada pelo Axon                                                                          | AC3                |
| `AXF_CON_DT_ConsentGivenAt__c`                       | DateTime — início                                                                                                     | AC3                |
| `AXF_CON_DT_ConsentExpiresAt__c`                     | DateTime, nulo permitido (nulo = sem expiração definida, **não** eterno)                                              | AC3 / investigação |
| `AXF_CON_TXT_ConsentVersion__c`                      | Text(40)                                                                                                              | AC3                |
| `AXF_CON_DT_ConsentCheckedAt__c`                     | DateTime — última revalidação                                                                                         | AC4                |
| `AXF_CON_DT_PausedAt__c` / `AXF_CON_LKP_PausedBy__c` | DateTime / Lookup(User) SetNull                                                                                       | AC5, AC7           |
| `AXF_CON_DT_LastSuccessAt__c`                        | DateTime — último sucesso de coleta (preenchido por AXF-12; exibido na Saúde)                                         | AC7                |
| `AXF_CON_TXT_LastStatusCode__c`                      | Text(40) — código sanitizado (`OUTDATED`, `LOGIN_ERROR`, …)                                                           | AC7                |
| `AXF_CON_TXT_LastStatusDetail__c`                    | Text(255) — detalhe sanitizado, sem segredo/PII                                                                       | AC7, AC8           |
| Name                                                 | AutoNumber `CON-{00000}`                                                                                              | —                  |

Segredos (`clientId`, `clientSecret`, `apiKey`, webhook secret) **nunca** entram neste objeto,
em Custom Metadata desprotegida, em logs, em URLs ou em evidências.

---

## 3. Credenciais e principal (G4-1)

- **Protocolo:** API-key da Pluggy (`POST /auth` → `apiKey`, header `X-API-KEY`, TTL ~2h). **Não é OAuth.**
- `AXF_EXC_Pluggy`: `authenticationProtocol = Custom`, `NamedPrincipal` com `clientId` / `clientSecret`.
- `AXF_NC_Pluggy_API`: `SecuredEndpoint`, `https://api.pluggy.ai`, merge fields **só no body**.
- `apiKey` obtido **server-side** por `AXF_CLS_PluggyAuthService` e mantido **só em memória**
  pela duração da transação Apex (um `POST /auth` por transação; sem Platform Cache — Revisão 31/08).
- Acesso ao NC/principal via `AXF_PS_PluggyIntegration`, atribuído **apenas** ao usuário de
  serviço (G3, `AXF_PS_Provisioning`). Ownership de integração não concede acesso financeiro (G2).
- **Configuração inicial (AC1):** `setPrincipalCredential(clientId, clientSecret)` no controller
  valida `AXF_CanConfigure` + `ManageNamedCredentials` no servidor, encaminha os valores
  **em memória** para `ConnectApi.NamedCredentials.createCredential/updateCredential` e descarta.
  Não grava em objeto, resposta, log ou storage do navegador. O caminho alternativo aprovado é
  a UI de Setup de External Credentials.

## 4. Rotação sem destruir a ativa (G4-2)

Dois conjuntos NC/EC pré-instalados: **ativo** (`AXF_EXC_Pluggy`) e **candidato**
(`AXF_EXC_Pluggy_Candidate`). A configuração guarda apenas `RotationState__c` + timestamp.

1. `stageCandidate(clientId, clientSecret)` → grava só no principal do **candidato**; estado `CANDIDATE`.
2. `testCandidate()` → estado `TESTING`: `POST /auth` no candidato **e** `GET /connectors` (leitura leve)
   **e** verificação de que cada `AXF_OBJ_PluggyConnection__c` ativa continua acessível
   (`GET /items/<id>` retornando 200 com consent válido). Falha → `ROLLED_BACK`, ativa preservada,
   erro sanitizado.
3. `promote()` → só se **todas** as verificações passaram: copia os valores do candidato para o
   principal ativo via `ConnectApi`, limpa o candidato, estado `PROMOTED`. Cache de `apiKey` invalidado.
4. Concorrência: `RotationState__c` funciona como token; segunda tentativa em `TESTING` recebe `CONFLICT`.
5. `RESULT_UNKNOWN` (timeout na promoção) bloqueia repetição; reconciliação manual pelo estado.

Nunca apagar a credencial ativa para descobrir se a candidata funciona.

## 5. Consentimento (G4-5, AC3/AC4)

`AXF_CLS_PluggyConsentService.refresh(connectionId)`:

- `GET /items/<PluggyItemId>` → conector, status, `AXF_CON_TXT_ObservedItemId__c`.
- `GET /consents?itemId=<PluggyItemId>` → `id`, `itemId` (preservado à parte — pode ser o item de
  origem, D-85), `products`, `createdAt`, `expiresAt`, `revokedAt`.
- Mapeia para os campos `AXF_CON_*`. `expiresAt` nulo é gravado como nulo e **não** tratado como erro
  nem como "eterno"; ausência de consentimento / erro de consulta ≠ "sem expiração".
- Transição de `AXF_CON_PKL_ConsentState__c`:
  - consent válido, não expirado, não revogado → `ACTIVE`.
  - `revokedAt` presente **ou** item com erro de login/consent → `REVOKED`.
  - `expiresAt` no passado **ou** status de item desatualizado → `STALE`.
- `STALE`/`REVOKED`: dados coletados permanecem visíveis marcados como **desatualizados**; nova
  coleta bloqueada até reautorização. Token/segredo remanescente descartado.
- **Não** inventa finalidade/versão/lista de contas ausente; não assume que login no MeuPluggy
  autoriza a aplicação do Dashboard.

## 6. Bloqueio da coleta (AC4, AC5)

`AXF_CLS_PluggyCollectionControlService.assertCollectionAllowed(connectionId)` — chamada **antes**
de enfileirar job, executar callout ou publicar dados (usada por AXF-12). Lança
`AXF_CLS_PluggyCollectionBlockedException` (com motivo sanitizado) quando:

- `CollectionGloballyPaused__c = true` (pausa global), ou
- `AXF_CON_PKL_CollectionState__c = PAUSED` (pausa local da conexão), ou
- `AXF_CON_PKL_ConsentState__c ∈ {STALE, REVOKED}`.

`revalidatePending()` reavalia conexões e é o ponto onde jobs pendentes de AXF-12 devem checar o
estado antes de cada nova unidade. Pausa **não** revoga consentimento nem apaga histórico; retenção
e conexões/acessos independentes preservados. Retomada (`resume*`) exige `AXF_CanConfigure` e uma
revalidação de consentimento bem-sucedida.

Revogação externa: o Axon **detecta** indisponibilidade/`REVOKED` e orienta reautorização no
provedor; **não** afirma sucesso remoto e **não** chama `DELETE /items`.

## 7. Webhook (G4-3)

`AXF_CLS_PluggyWebhookResource` (`@RestResource urlMapping='/pluggy/webhook'`), executando
como o **Guest User** do Salesforce Site:

1. Lê o corpo cru e o header de assinatura.
2. `AXF_CLS_PluggyWebhookSignature.isValid(body, signature, secret)` — HMAC-SHA256 do corpo com o
   webhook secret (CMT protegida `AXF_PluggyWebhookConfig__mdt.AXF_PWC_TXT_Secret__c`), comparação
   **constant-time**. Inválida → HTTP 401, nada processado, nada logado além de status/correlationId.
3. Válida → **publica `AXF_PluggyWebhookEvent__e`** (o guest só pode `Create`; a licença de guest
   user proíbe escrever na Conexao e usar a Credencial Externa). O payload **nunca** é gravado como fato.
4. `AXF_TRG_PluggyWebhookEvent` → `AXF_CLS_PluggyWebhookEventHandler` roda **fora do contexto guest**
   (usuário Automated Process, portando `AXF_PS_PluggyIntegration`): revalida consentimento/estado via
   `AXF_CLS_PluggyConsentService.refreshByItemIds` (**bulk** — todos os callouts antes do único DML, um
   lote de eventos nunca cai em callout-after-DML). Idempotente — replay do evento é seguro.
   Resultado desconhecido/transitório → `EventBus.RetryableException` (o bus reentrega); resultado
   terminal → engolido. `publishBehavior = PublishImmediately`: uma notificação verificada dispara a
   revalidação mesmo que o resto do request falhe (perder o sinal é pior que uma revalidação duplicada,
   que é inócua).
5. Varredura periódica idempotente para eventos perdidos → **AXF-12** (aqui fica só o gancho).

> Tornar o endpoint público (Salesforce Site + guest user) e **atribuir `AXF_PS_PluggyIntegration`
> ao usuário Automated Process** são passos manuais de instalação — ver §10 / lista AXF-77. As
> classes, o platform event, o trigger, a validação e os testes são a entrega.

## 8. Regressão do legado

`AXF_CLS_PluggyAuthService` (portado de `develop`):

- **Removidos** todos os `System.debug` de endpoint, headers, corpo da requisição e corpo da
  resposta (vazavam o `apiKey` no log — AC8).
- TTL de cache deixa de ser fixo em 7200s; passa a `AXF_PluggyIntegrationConfig__c.ApiKeyCacheTtlSeconds__c`
  (default 5400s), sempre < expiração real com margem de renovação.
- Erros sanitizados: mensagem cita endpoint/status/correlationId, nunca credencial, token ou corpo cru.
- Suporte a NC alternativo (candidato) para o teste de rotação, sem tocar o cache da ativa.
- `AXF_EXC_Pluggy` / `AXF_NC_Pluggy_API` portados sem alteração estrutural (baseline ratificado em G4-1);
  `allowMergeFieldsInHeader=false`, `generateAuthorizationHeader` desligado (a auth é no body).

Componentes legados de **sincronização** (`AXF_CLS_PluggyTxSync_Service`, `*Queueable`, etc.) **não**
foram portados: pertencem a AXF-12 e serão avaliados/regredidos lá.

## 9. Testes

| Classe de teste                                                   | Cobre                                                                                                                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_CLS_PluggyAuthServiceTest`                                   | auth OK / 401 / 5xx / cache hit / apiKey ausente / TTL do Custom Setting; **assert de que nenhum debug/erro contém o apiKey**                                        |
| `AXF_CLS_PluggyWebhookSignatureTest`                              | assinatura válida / inválida / tamanho diferente / vazia; constant-time                                                                                              |
| `AXF_CLS_PluggyWebhookResourceTest`                               | 401 sem assinatura / com assinatura ruim; 200 + publica `AXF_PluggyWebhookEvent__e` + revalida com assinatura boa; 202 quando webhook desligado; corpo não vira fato |
| `AXF_CLS_PluggyWebhookEventHandlerTest`                           | evento publicado revalida a conexão; replay idempotente; itemId vazio ignorado; falha transitória → `EventBus.RetryableException`; falha terminal engolida           |
| `AXF_CLS_PluggyConsentServiceTest`                                | consent ACTIVE / expirado→STALE / revogado→REVOKED / `expiresAt` nulo / itemId divergente preservado / consulta 403                                                  |
| `AXF_CLS_PluggyCredentialRotationServiceTest`                     | candidata válida promove / candidata inválida → ROLLED_BACK preservando ativa / concorrência → CONFLICT / permissão negada                                           |
| `AXF_CLS_PluggyCollectionControlServiceTest`                      | pausa local / pausa global / STALE bloqueia / REVOKED bloqueia / retomada exige consent válido / pausa repetida idempotente / revalidação de pendentes               |
| `AXF_CLS_CTRL_PluggyIntegrationConfigTest`                        | `AXF_CanConfigure` negado → FORBIDDEN limpo; status; setPrincipalCredential encaminha e não persiste                                                                 |
| `AXF_CLS_CTRL_SourceHealthTest`                                   | lista instituição/contas/consentimento/último sucesso/impacto/ação; sem segredo no DTO                                                                               |
| `aXF_LWC_pluggyIntegrationConfig` / `aXF_LWC_sourceHealth` (Jest) | estados loading/forbidden/ready/error; sem cor/toast como único sinal; erro associado ao campo                                                                       |
| `AXF_CLS_PluggyHttpCalloutMock`                                   | utilitário de mock compartilhado                                                                                                                                     |

Deploy: `--target-org AXON_DEV` com `NoTestRun` (regra do projeto); suíte AXF-11 executada
localmente antes do PR.

## 10. Passos manuais de instalação (para AXF-77)

| Passo                                                                                                                  | Motivo                                                                                                                 |
| ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Preencher o principal de `AXF_EXC_Pluggy` (Client ID / Secret reais) no Setup ou pela tela de configuração             | segredo de org, nunca em metadata                                                                                      |
| Atribuir `AXF_PS_PluggyIntegration` ao usuário de serviço (`AXF_PS_Provisioning`)                                      | principal mínimo da integração                                                                                         |
| Registrar o domínio de Salesforce Sites e criar um Site ativo (home page = `UnderConstruction`)                        | expõe `/services/apexrest/pluggy/webhook` sem autenticação                                                             |
| Atribuir `AXF_PS_PluggyWebhookGuest` ao Guest User do Site + habilitar as classes no _Site Apex Class Access_          | guest valida HMAC e publica o platform event (só `Create`)                                                             |
| **Atribuir `AXF_PS_PluggyIntegration` ao usuário Automated Process** (via API/Data Loader — `PermissionSetAssignment`) | o trigger de `AXF_PluggyWebhookEvent__e` roda como Automated Process e precisa do principal da EC + escrita na Conexao |
| Cadastrar `https://<site>/services/apexrest/pluggy/webhook` no Dashboard Pluggy e gerar o _signing secret_             | inbound não autenticado; pareamento HMAC                                                                               |
| Gravar o secret em `AXF Pluggy Webhook Config / Default` (`AXF_PWC_TXT_Secret__c`, CMT protegida)                      | HMAC local; EC não é legível em Apex, CMT protegida sim (G4-3)                                                         |
