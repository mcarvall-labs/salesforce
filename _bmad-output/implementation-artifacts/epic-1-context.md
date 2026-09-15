<!-- AXF-106-DECISION-20260912 -->
## AXF-106 — current bank and holder decision (2026-09-12)

Traceability: AXF-106 is the owner of the new decision. Open epic integration: AXF-1/10/26/34/58/81; installation/migration: AXF-77/78/79; source consumers adopt scoped supplements in Jira. Completed story requirements are historical baseline, not silently rewritten.

Decision approved by Michel on 2026-09-12; authoritative scope: AXF-106. This active supplement supersedes conflicting bank-reference and onboarding-order assumptions in this document only. It is a requirement change, not evidence of implementation, migration or deployment.

Reuse the Financial Institution object reported in production as the canonical bank directory. Its exact API name/schema and availability in DEV/UAT still require read-only verification. Do not create a duplicate object or infer schema from a label.

Connections select Bank through a Lookup to that directory and a suggested Holder through a Lookup to Account (AXF_Person / AXF_Business). Register/reuse holders before connections; provide inline New holder without losing Item ID or bank selection. Holder registration creates no User and grants no access.

Bank accounts, credit cards, manual-source forms and relevant selectors, filters, reports and integrations consume canonical institution references. Preserve provider connector/institution text and IDs separately. MeuPluggy, name similarity or bank equality never proves bank mapping, source identity or ownership.

Connection holder remains a suggestion. Confirm the holder per account/card through AXF-85 before financial use. Editing connection references must not rewrite confirmed holders, grants, financial facts, allocations or immutable document/archive snapshots.

Display bank and holder names plus masked Item ID; support multiple connections sharing bank/holder, explicit edits, idempotent registration and rediscovery. Existing missing references remain visible pending decisions. An alias-only solution does not satisfy this decision.

Inventory consumers before migration; map only unambiguous associations, report unresolved/conflicting mappings, preserve original values and require repeatable backfill and rollback. Do not delete legacy fields until consumers and parity checks pass. Production mutation and destructive cutover require separate authorization.

Open implementation decisions: verified institution identifiers; mandatory fields/progression gates; inactive/deleted-reference policy; and connections with sources from different banks. Do not impose a blanket required-field retrofit or invent a new automatic mapping rule.

Preserve Dev Done and later work-item history. AXF-106 owns the evolution of delivered AXF-80/84/85/86/88/89/90/91/98. Related open work receives only its applicable compatibility obligations; unrelated reviewed contracts/readiness are not reopened.

Canonical page: https://axon-personal-finances.atlassian.net/wiki/pages/viewpage.action?pageId=3702785

Requirements: https://axon-personal-finances.atlassian.net/browse/AXF-106

<!-- /AXF-106-DECISION-20260912 -->

# Epic 1 Context: Espaço financeiro privado e colaboração segura

<!-- Compiled from canonical workspace planning artifacts. Regenerate from C:\Projects\Axon Finance\_bmad-output when planning docs change. -->

## Goal

Permitir que usuários operem finanças de pessoas e empresas titulares somente dentro do escopo efetivamente autorizado, com colaboração limitada, consolidação segura e administração do ciclo de acesso. O épico estabelece a fundação nativa Salesforce para cadastro, papéis, permissões, ownership e sharing, além de cobrir revogação, encerramento, instalação limpa e migração sem preservar a antiga infraestrutura genérica de Household, grants, comandos ou auditoria universal.

## Stories

- Story AXF-3: Selecionar e acessar somente pessoas e empresas autorizadas
- Story AXF-4: Consolidar somente pessoas e empresas autorizadas
- Story AXF-5: Atribuir economicamente contas de uso misto
- Story AXF-6: Colaborar em uma despesa com escopo limitado
- Story AXF-8: Revogar acessos derivados e revalidar superfícies alcançáveis
- Story AXF-9: Exportar e encerrar a instalação sob retenção governada
- Story AXF-77: Instalar o Axon em Developer Edition limpa pelo README
- Story AXF-78: Remover metadados obsoletos com segurança em AXON_DEV
- Story AXF-79: Migrar o projeto reformulado para a produção existente com segurança
- Story AXF-82: Adicionar pessoa e dar acesso ao Axon
- Story AXF-83: Vincular responsáveis por empresa e conceder acesso financeiro
- Story AXF-85: Confirmar titulares das contas e cartões e corrigir vínculos
- Story AXF-7: Configurar papéis e permissões de acesso ao Axon
- Story AXF-80: Cadastrar e manter pessoas e empresas titulares

## Requirements & Constraints

- O acesso efetivo combina acesso ao registro, CRUD/FLS, Permission Sets/Groups, Custom Permissions e operações autorizadas. Restrições devem ser aplicadas no servidor e em todas as superfícies, inclusive UI, API, busca, relatórios, exportações, caches e jobs.
- O sistema deve operar de forma fail-closed: dados não autorizados não podem aparecer em payload, DOM, árvore acessível, agregados ou mensagens, nem ser inferidos por diferença. Revogações removem apenas o acesso derivado da origem revogada e preservam direitos independentes legítimos.
- Pessoas, empresas, usuários Salesforce, titulares econômicos e `OwnerId` são conceitos distintos. Uma empresa pode ter vários responsáveis; uma pessoa pode responder por várias empresas; contas e cartões sem titular confirmado permanecem indisponíveis.
- Gestor Financeiro e Participante não recebem privilégios administrativos globais. A configuração não concede Delete, não substitui silenciosamente perfil ou permissões independentes e não promete neutralizar privilégios amplos preexistentes.
- Mutações materiais devem ser atômicas, idempotentes por efeito, seguras sob concorrência e recuperáveis após resultado desconhecido. Estados pendente, falhou e concluído precisam refletir verificação real, sem sucesso otimista.
- Operações destrutivas, retenção, backup, legal hold e restauração exigem política e prova próprias. Não há retenção global de auditoria por cinco anos; políticas de CSV bruto, documentos e backups são independentes e permanecem sujeitas ao gate de evidência.
- Interfaces devem atender WCAG 2.2 AA, teclado, foco, leitor de tela, reflow e PT-BR/EN, sem depender de cor ou de nomes traduzidos/IDs fixos. Testes positivos e negativos devem cobrir acesso por UI e superfícies nativas aplicáveis.

## Technical Decisions

- Usar mecanismos nativos Salesforce: OWD Private nas raízes independentes, hierarquia Axon — Gestor Financeiro acima de Axon — Participante, ownership/sharing explícito e PS/PSG para CRUD/FLS. Papel e PSG não substituem sharing.
- Não criar ou conservar como alvo `Household`, `EntityAccessGrant`, `BootstrapAuthority`, `CommandExecution` universal, `AuditEvent` obrigatório ou equivalentes genéricos renomeados. Evidência deve ser proporcional ao risco e usar histórico nativo quando suficiente.
- Apex/LWC deve usar controller dedicado, serviço responsável pela regra, DTOs tipados, `with sharing`, validação explícita de CRUD/FLS e autorização no servidor. Filtros de cliente nunca concedem acesso.
- G1 define o modelo mínimo e as relações; G2, a matriz de acesso; G3, autoridade, licença, PSG e transação de provisionamento; G6, identidade por efeito, concorrência e recuperação; G7, evidência e retenção; G9, compatibilidade, migração, rollback e restore. Ausência de contrato aplicável bloqueia o build; não se inventam schema, fallback, protocolo ou budget localmente.
- AXF-77, AXF-78 e AXF-79 são entregas distintas: instalação limpa, limpeza controlada de DEV e migração da produção existente. Nenhuma definição documental autoriza deploy, exclusão ou cutover.

## UX & Interaction Patterns

O seletor de contexto mostra somente pessoas e empresas acessíveis e, ao trocar o escopo, atualiza todas as regiões dependentes sem manter dados anteriores. A administração de acesso apresenta nível e escopo em linguagem simples, detecta permissões amplas existentes e distingue pendente, falhou, resultado desconhecido e concluído. Confirmações materiais nomeiam objeto e impacto, mantêm foco e aguardam o resultado do servidor. Após revogação, superfícies abertas removem conteúdo alcançável e exibem apenas mensagem neutra; a reconexão revalida autorização antes de restaurar dados ou enviar comandos.

## Cross-Story Dependencies

AXF-80 e AXF-7 formam a base de cadastro e acesso. AXF-82 reutiliza ambas para vincular usuário a pessoa; AXF-83 acrescenta responsabilidade empresarial; AXF-3 depende dessa fundação para seleção segura; AXF-85 combina cadastro, descoberta e responsabilidade para confirmar titulares. AXF-5 e AXF-6 dependem do escopo autorizado e de capacidades financeiras específicas; AXF-8 revoga acessos produzidos por AXF-83/AXF-7/AXF-3 sem remover direitos independentes; AXF-9 depende da revogação e do controle de consentimento. AXF-77/78/79 só avançam após as substituições e provas de instalação, limpeza, migração, rollback e restore previstas em G9.
