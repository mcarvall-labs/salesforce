# Triagem BUG-020/021/022 e US-097..105 — evidência de código (2026-09-06)

> Branch analisada: `develop` @ 44f6475 (sincronizada com origin/develop). Análise 100% local/read-only.

## Fato arquitetural central

O modelo antigo de fluxo de caixa foi **removido do source** na reconciliação/consolidação e
substituído por um novo modelo:

- `AXF_OBJ_CashFlow__c` e `AXF_OBJ_InstallmentGroup__c` **não existem mais** em `force-app`.
- `AXF_CF_PKL_PaymentMode__c` **não existe mais**; `FINANCIAMENTO_SAC` tem **0 referências** no source.
- Novo modelo: `AXF_OBJ_FinancialTransaction__c` + engine de cronograma
  (`AXF_CLS_ScheduleService`, `ALT_CLS_AmortizationSchedule`, `AXF_CLS_CTRL_ScheduleWizard`) —
  picklist de modalidade do cronograma `AXF_FTX_PKL_Modality__c` = `RECURRING | INSTALLMENT | PRICE | SAC`
  (descrição: "Modalidade da AMORTIZATION-POLICY.md v1.0.0 … (AXF-20)").
- Novas UIs (source): `aXF_LWC_entryWizard` (lançamento simples, AXF-19) e
  `aXF_LWC_scheduleWizard` (planos PRICE/SAC/INSTALLMENT/RECURRING, AXF-20). Sem CONSORCIO:
  `ALT_CLS_AmortizationScheduleTest.consorcioIsBlockedNotInvented` e outcome `BLOCKED`
  ("Modalidade sem policy canônica"). Nenhuma das duas UIs está montada em flexipage/app **no source**
  (provavelmente montadas no org DEV — drift repo↔org).

## BUG-020 (#11) — superfície-alvo removida

Critérios citam o formulário "one-time" do modelo antigo (US-099): campos "Quantidade de Parcelas /
1º Vencimento / Valor da Parcela / Tipo de Valor", seletor com busca, rótulo "Conta Corrente",
formatação de moeda ao digitar.

Estado atual:
- `entryWizard` **não exibe** nenhum desses campos de parcelamento (nunca os mostra — critério 1
  satisfeito por ausência; parcelamento foi movido para `scheduleWizard`).
- `scheduleWizard` mostra campos **condicionais por modalidade** (`showRate` p/ PRICE/SAC,
  `showFixedValue` p/ RECURRING, `showPrincipal` p/ não-recorrente) — o "só quando aplicável" foi
  re-implementado de forma mais limpa.
- Valor monetário: `lightning-input type="number" formatter="currency"` (formatação de moeda nativa).
- Busca textual (typeahead): usa `lightning-combobox` (sem typeahead) — para poucas contas é dropdown.
- Rótulos: `labels.js` usa "Conta bancária"/"Cartão de crédito"/"Dinheiro"; o objeto de origem é
  `AXF_OBJ_BankAccount__c`, cujo label no source é "Conta Bancária" (a issue espera "Conta Corrente";
  o org DEV parece exibir "Current Accounts" — drift de rótulo repo vs org).

Veredito: **defeitos reportados pertencem à UI do modelo antigo, removida do source**. A nova UI não
reproduz os defeitos de campos-por-modalidade nem expõe `FINANCIAMENTO_SAC`. Requer decisão: fechar
como supersedido pela re-arquitetura (AXF-19/AXF-20) ou validar a nova UI no DEV contra os critérios
(especialmente typeahead e rótulo "Conta Corrente").

## BUG-022 (#12) — resolvido pela re-arquitetura (evidência forte)

- `FINANCIAMENTO_SAC` como modalidade: **inexistente** no source.
- `AXF_CF_PKL_PaymentMode__c`: **inexistente**.
- Modalidades de cronograma atuais (`AXF_FTX_PKL_Modality__c`) não misturam modalidade de pagamento
  com tipo de financiamento da forma relatada: PRICE/SAC são modalidades do cronograma de
  amortização (papel correto deles) e `PARCELADO` = `INSTALLMENT` existe como valor canônico.

Veredito: **não há código a corrigir** — o defeito descrito não é reproduzível no modelo atual.
Decisão: fechar como resolvido/supersedido (recomendado) com comentário de evidência.

## BUG-021 (#29) — drift de org; nada no source

- Botão "Sync Accounts" na List View "View All" do objeto de contas correntes **não existe no source**:
  0 referências a `SyncAll`, `AXF_SyncAllAccounts`, páginas VFP (`pages/` não existe), quick actions,
  flows ou botões de sync no repo.
- Historicamente existia (linhagem antiga): `pages/AXF_BA_VFP_SyncAllAccounts.page` montava
  `c:aXF_LWC_syncAllAccounts` via LightningOut, com controllers `AXF_CLS_CTRL_SyncAllAccounts` /
  `AXF_CLS_PluggyBankAccountSyncQueueable` etc. — tudo removido na reconciliação.
- O sync hoje é coberto por: webhook Pluggy (`AXF_CLS_PluggyWebhookEventHandler`), controle de
  coleta (`AXF_CLS_PluggyCollectionControlService`) e o novo **AXF-12 (1/N)** — schema CCT +
  `AXF_PluggySyncPolicy__mdt` + IntegrationRun; a orquestração/execução em massa (fatia 2/N) **ainda
  não existe**.

Veredito: botão é resíduo **no org DEV** apontando para página/componente inexistente no source.
Opções: (a) remover o botão órfão no org (destrutivo, requer aprovação + acesso ao org),
(b) reconstruir "Sync Accounts" sobre a orquestração AXF-12 (2/N) quando existir, (c) só documentar
agora e manter a issue aberta dependente do AXF-12. Nenhuma mudança de source é correta hoje.

## US-097..105 (EPIC-007, issues #2..#10) — todas escritas contra o modelo removido

Os corpos citam campos/objetos que não existem mais: `AXF_CF_CUR_Value__c`, `AXF_CF_CHK_IsEstimated__c`,
`AXF_OBJ_InstallmentGroup__c`, status `PAGA/PAGA_EM_ATRASO/VENCIDA`, `AXF_BAT_PKL_ReconciliationStatus__c`,
`AXF_CF_PKL_ReconciliationStatus__c` etc. Mapa preliminar:

| US | Assunto | Estado no modelo atual |
|----|---------|------------------------|
| US-099 (#4) | one-time com estado pago/data retroativa | lançamento simples existe (`entryWizard`), mas sem toggle pago/vencida no source → NÃO integralmente coberta |
| US-100 (#5) | série finita de parcelas | `INSTALLMENT` existe no engine (AXF-20); objeto grupo mudou → cobertura parcial/diferente |
| US-101 (#6) | recorrente fixo/variável + horizonte 6m | `RECURRING` existe; estratégias MEDIA_MOVEL/etc. e janela 6m a confirmar no engine → parcial |
| US-102 (#7) | PRICE com janela rolante 6m | `PRICE` existe (AXF-20); janela/cap a confirmar → parcial |
| US-103 (#8) | SAC com recálculo | `SAC` existe (AXF-20); recálculo a confirmar → parcial |
| US-104 (#9) | consórcio + ajuste aniversário | **BLOQUEADO** (sem policy canônica; teste `consorcioIsBlockedNotInvented`) |
| US-097 (#2) | quitar recorrente + forecast 6m | pertence ao novo roadmap (AXF-25 "registrar realização") → não entregue |
| US-098 (#3) | conciliação 1:1 ao quitar | pertence ao novo roadmap (epic AXF-26, AXF-29..33) → não entregue |
| US-105 (#10) | auditoria de campos p/ destructive | objetos-alvo **já removidos do source**; auditoria precisa ser re-escopada/retrospectiva |

Conclusão: **fechar mecanicamente não é seguro**. As US precisam de decisão de produto: re-mapear para
os epics AXF novos (AXF-18/19/20; AXF-25; AXF-26..33), re-escrever critérios para o modelo atual, ou
fechar as que foram absorvidas (com comentário de evidência em cada issue e no EPIC-007 #1).

## Resultados aplicados (2026-09-06, com decisão do dono do produto)

| Item | Decisão | Ação executada | Evidência |
|------|---------|----------------|-----------|
| BUG-022 (#12) | resolvido pela re-arquitetura | comentário de evidência + fechada (`completed`) | comment 5560746399 |
| BUG-020 (#11) | supersedido pela re-arquitetura | comentário de evidência + fechada (`completed`) | comment 5560876644 |
| BUG-021 (#29) | remover botão órfão no org | removidos em **UAT** e **PROD**: webLinks `AXF_BA_BTN_SyncAllAccounts`/`AXF_CC_BTN_SyncAllCards`, `<listViewButtons>` de searchLayouts (deploy dos object-meta sem a linha) e páginas VF `AXF_BA_VFP_SyncAllAccounts`/`AXF_CC_VFP_SyncAllCards`. DEV não tinha resíduo. Verificado pós-deploy (0 páginas/`listViewButtons` com Sync). Issue comentada + fechada | deploy ids na issue #29 (comment 5560935109) |
| US-099..103 (#4..#8) | re-mapear e fechar absorvidas | comentários de evidência por issue + fechadas (`completed`) | comments 5560876892..5560877865 |
| US-097, US-098, US-104, US-105 (#2,#3,#9,#10) | re-escopo no modelo novo/Jira | comentários de re-mapeamento publicados; issues permanecem **abertas** | comments 5560878102/…/5560878346 |
| EPIC-007 (#1) | triagem documentada | comentário de rastreabilidade publicado; epic permanece aberto (depende do re-mapeamento no Jira) | comment 5560746620 |
| EPIC-008 (#30) + US-106 (#31) | backlog de engenharia | sem mudança (meta-trabalho de automação; fora do escopo aprovado) | — |

Observações:
- A remoção nos orgs foi **destrutiva em UAT/PROD** e executada fora do pipeline git (não há delta de source: o repo nunca teve esses artefatos). Registrar na auditoria da US-105/relase notes de promoção.
- Próximo backlog de produto (GitHub): US-097, US-098, US-104, US-105, EPIC-007 (re-mapear), EPIC-008/US-106 (automação/rastreabilidade).

## Restrições operacionais desta sessão

- Jira (projeto AXF) **não acessível** (sem MCP/config na sessão) → prioridade real só confirmável pelo dono do produto.
- `git push`/fetch de rede falham no sandbox (helpers de credencial não podem criar subprocessos com pipes; GCM falha com schannel). FF local feito via ref local. Push exige execução escalada (`danger-full-access`) com aprovação.
- `sf` falha no sandbox (não consegue abrir log em `C:\Users\Michel\.sf\`) → acesso ao org exige escalada + aprovação (executado com acesso amplo nesta sessão).
