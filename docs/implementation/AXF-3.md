# AXF-3 — Selecionar e acessar somente pessoas e empresas autorizadas

- **Jira:** https://axon-personal-finances.atlassian.net/browse/AXF-3
- **Branch:** `feature/AXF-3-authorized-context` sobre `reconciled/base`
- **Predecessoras:** AXF-80, AXF-7 e AXF-83 concluídas

## Implementação

| Área       | Entrega                                                                                                                                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Autoridade | `Account` é a raiz do titular. `AXF_CLS_AuthorizedContextService` usa `with sharing` e SOQL `WITH USER_MODE`; não cria objeto de grant paralelo.                                                            |
| Contrato   | DTO mínimo com `accountId`, rótulo, tipo `PERSON/BUSINESS` e moeda de apresentação. Registros fora dos Record Types AXF não são contextos.                                                                  |
| Controller | `AXF_CLS_CTRL_AuthorizedContext`, cacheable e com mensagem sanitizada em falha de acesso.                                                                                                                   |
| UI         | `aXF_LWC_contextBar`: loading, vazio neutro, erro/retry e combobox somente com os contextos retornados pelo servidor.                                                                                       |
| Propagação | `AXF_ContextChanged__c` via Lightning Message Service e evento `contextchange`. Cada seleção leva `selectionVersion`; consumidores devem limpar estado anterior e recarregar dados, atualidade e confiança. |
| Acesso     | Classes e aba adicionadas a `AXF_PS_GestorFinanceiro` e `AXF_PS_Participante`; nenhuma permissão Delete, ViewAll ou ModifyAll adicionada.                                                                   |

## Critérios de aceite

- **AC1/AC2:** visibilidade deriva de OWD, sharing, CRUD/FLS e `USER_MODE`; a resposta contém apenas Accounts titulares acessíveis.
- **AC3:** a troca publica um contexto completo e versionado; regiões consumidoras podem rejeitar respostas antigas sem misturar o contexto anterior.
- **AC4/AC5:** campos não autorizados não entram no DTO; vazio e falha usam mensagens neutras sem confirmar registros privados.
- **AC6:** nenhuma automação de sharing é criada nesta US; eventual falha do mecanismo nativo permanece sem fallback que amplie acesso.
- **AC7:** controller dedicado, serviço `with sharing`, DTO tipado e autorização no servidor.

## Validação

- Check-only AXON_DEV `0Afaj00000itM9pCAE`: 9/9 componentes e 5/5 testes Apex; serviço 88% e controller 80% de cobertura.
- Jest focal: 4/4 testes verdes.
- Nenhum deploy persistente em UAT/PROD.
