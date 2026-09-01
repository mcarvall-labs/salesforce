<!-- PR: AXF-87: reconciled/base -->

- **Jira:** https://axon-personal-finances.atlassian.net/browse/AXF-87 (Epic AXF-81)
- **Branch:** `feature/AXF-87-personal-report-currency` (base `reconciled/base`).
- **Gates:** G1/G2/G5/G6 fase de definição fechada (30/08). **G8 NÃO é dependência** (é só
  condição da equivalência indicativa AXF-92). Predecessora: AXF-7 (Done).
- Decisões D-59 (moeda padrão) / D-55 (fonte de cotação — não afeta esta US).

> Só apresentação. Não converte, não move dinheiro, não altera `CurrencyIsoCode` de fato,
> saldo, histórico ou cotação contábil. Não autoriza deploy em UAT/PROD.

---

## O que entrega

| Área                                       | Componente                                                                                                                                                                                                                                                                |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Moedas habilitadas (sem multimoeda na org) | `AXF_ReportCurrency__mdt` — registros BRL (sugerida), USD, EUR, GBP, ARS; `Active` + `SuggestedDefault`                                                                                                                                                                   |
| Preferência pessoal persistida no servidor | `AXF_ReportCurrencyPref__c` — **Custom Setting hierárquico** (por usuário; a linha da org = default corporativo). `getInstance()` resolve usuário → profile → org. Um campo: `AXF_RCP_TXT_IsoCode__c`                                                                     |
| Serviço                                    | `AXF_CLS_ReportCurrencyService` — `activeCurrencies()` (sugerida primeiro), `suggestedDefault()`, `effectivePreference()`, `hasPersonalPreference()`, `setForCurrentUser(iso, overwrite)`, `setForUser(userId, iso, overwrite)` (admin, gated por `AXF_CanConfigure`)     |
| Controller / LWC                           | `AXF_CLS_CTRL_ReportCurrencyPref` + `aXF_LWC_reportCurrencyPreference` — combobox de moedas ativas, marca a sugerida, salva; diálogo de confirmação ao substituir uma preferência existente; estados loading/ready/error; WCAG (role=status/alert/alertdialog, aria-live) |
| Acesso                                     | `AXF_PS_ReportCurrency` (componente adicionado aos PSGs Gestor e Participante — qualquer usuário do Axon define a própria); admin path exige `AXF_CanConfigure`                                                                                                           |

## ACs → implementação

- **AC1** — `setForCurrentUser` grava no CS hierárquico do usuário; `effectivePreference()` retoma em nova sessão. BRL sugerida via `SuggestedDefault`; **não sobrescreve** preferência existente nem a moeda corporativa sem `overwrite=true` (LWC pede confirmação).
- **AC2** — `setForUser` sob `AXF_CanConfigure`, não substitui escolha existente sem confirmação. **Profile/idioma não são prova** — só `isoCode` é aceito.
- **AC3/AC5** — a preferência é um Custom Setting de apresentação. Nenhuma leitura/escrita de `CurrencyIsoCode`, saldo, fato, cotação. Trocar não movimenta dinheiro nem reconhece ganho/perda.
- **AC4** — a equivalência indicativa (AXF-92 / G8) é ortogonal; esta US funciona sem ela.
- **AC6** — moeda inativa → `AXF_CLS_ReportCurrencyException` ("não habilitada"), sem alterar nada nem declarar sucesso; admin sem autoridade → rejeitado; retomada sempre lê a preferência persistida.
- **AC7** — rótulos/formatação atualizam pela preferência; **totais convertidos dependem de política explícita fora desta US** — o serviço não produz totais.

## Fora de escopo

Provider/cotação (D-55/AXF-92), consolidação convertida, ativar multimoeda na org, taxa corporativa, câmbio real.

## Testes

| Classe                                    | Cobre                                                                                                                                                                                           |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AXF_CLS_ReportCurrencyServiceTest`       | ativas excluem inativa + sugerida primeiro; grava e retoma; inativa rejeitada; não substitui silenciosamente + confirma; mesmo valor = no-op; admin path gated + set inicial + usuário inválido |
| `AXF_CLS_CTRL_ReportCurrencyPrefTest`     | state expõe opções/sugestão; salva → confirma → confirmado; inativa rejeitada                                                                                                                   |
| `aXF_LWC_reportCurrencyPreference` (Jest) | lista ativas + marca sugerida + pré-seleciona; texto "só apresentação"; salva; diálogo de confirmação ao substituir; erro + retry                                                               |

11 Apex + 6 Jest, 100% verdes. Deploy `NoTestRun` em AXON_DEV.

## Smoke test pendente (org real)

Confirmar que um usuário **não-admin** consegue `upsert` a própria linha do Custom Setting
hierárquico `AXF_ReportCurrencyPref__c` via a tela (Apex). Custom Settings `Public` são
graváveis por Apex sem "Customize Application", mas vale validar com um usuário Participante.
