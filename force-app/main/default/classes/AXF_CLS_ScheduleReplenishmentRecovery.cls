/**
 * AXF-103 fatia 2 — passagem de RECUPERAÇÃO da reposição rolante (contrato L85).
 *
 * O contrato exige, além da passagem mensal, passagens de recuperação para cobertura incompleta e
 * falha, e exige que o estado esgotado seja alcançável e acionável pelo fluxo REAL — não por Apex
 * anônimo digitado à mão. Esta classe é o ponto de entrada declarado dessa passagem, e a expressão
 * que a agenda vem de `AXF_ScheduleReplenishmentPolicy__mdt.Default.RecoveryCron`:
 *   AXF_CLS_ScheduleReplenishmentRecovery.registerRecovery();
 * Como `System.schedule` não aceita fuso, o registro RECUSA rodar quando o principal que registra
 * está fora do fuso declarado na política — senão o `CronTrigger` herdaria o fuso do usuário e
 * cumpriria outro horário em silêncio.
 *
 * Ela faz duas leituras e UMA cadeia limitada:
 *  1. o conjunto devido normal (cobertura atrás da janela, mais as lacunas abaixo do cursor);
 *  2. o REALARME limitado: cronogramas com o orçamento de tentativas ESGOTADO cuja janela
 *     declarada já venceu. Eles não voltam ao despacho automático — o orçamento continua esgotado —
 *     mas ganham uma tentativa por janela, e cada tentativa fracassada apenas reinicia a janela.
 *     Isso tira o cronograma do limbo "quatro falhas transitórias desligam para sempre" sem virar
 *     um reset irrestrito que repetiria uma falha permanente sem limite.
 *
 * Códigos TERMINAIS (sem visibilidade, sem permissão, identidade conflitante, defeito de plano)
 * NÃO são realarmados automaticamente: eles dependem de ação humana, e a retomada deles é a
 * passagem DIRIGIDA (`AXF_CLS_ScheduleReplenishmentScheduler.recover`).
 *
 * Como o agendador mensal, esta passagem não gera nada por conta própria: ela só seleciona e
 * enfileira, e toda geração continua passando pela porta única de escrita.
 */
public with sharing class AXF_CLS_ScheduleReplenishmentRecovery implements Schedulable {
  public void execute(SchedulableContext context) {
    run();
  }

  /**
   * @description Passo de OPERAÇÃO do dono: registra a passagem de recuperação com a expressão
   * aprovada, no fuso declarado. Recusa quando o principal que registra está em outro fuso.
   */
  public static Id registerRecovery() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    policy.requireRegisteringPrincipalInDeclaredTimeZone();
    return System.schedule(
      AXF_CLS_ScheduleReplenishmentPolicy.RECOVERY_JOB_NAME,
      policy.recoveryCron,
      new AXF_CLS_ScheduleReplenishmentRecovery()
    );
  }

  public static AXF_CLS_ScheduleReplenishmentScheduler.PassReport run() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    Integer batchSize = policy.dispatchBatchSize;
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      batchSize
    );
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> rearm = AXF_CLS_ScheduleReplenishmentSelector.selectBlockedForRearm(
      System.now(),
      batchSize
    );
    AXF_CLS_ScheduleReplenishmentScheduler.PassReport report = new AXF_CLS_ScheduleReplenishmentScheduler.PassReport();
    AXF_CLS_ScheduleReplenishmentSelector.DispatchTrace trace = AXF_CLS_ScheduleReplenishmentSelector.lastTrace();
    if (trace != null) {
      report.candidatesRead = trace.candidatesRead;
      report.dispatched = trace.dispatched;
      report.holeChecksConsumed = trace.holeChecksConsumed;
      report.unverifiedDispatched = trace.unverifiedDispatched;
      report.holesFound = trace.holesFound;
      report.skippedByState = trace.skippedByState;
      report.rearmCandidatesRead = trace.rearmCandidatesRead;
      report.rearmDispatched = trace.rearmDispatched;
    }
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> work = new List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem>();
    Set<Id> seen = new Set<Id>();
    // O realarme vem primeiro: ele é a razão de existir desta passagem, e o que exceder o lote
    // continua no conjunto devido para a passagem seguinte.
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : rearm) {
      if (seen.add(item.scheduleId)) {
        work.add(item);
      }
    }
    for (AXF_CLS_ScheduleReplenishmentSelector.WorkItem item : due) {
      if (seen.add(item.scheduleId)) {
        work.add(item);
      }
    }
    report.rearmDispatched = rearm.size();
    if (work.isEmpty()) {
      return report;
    }
    // Uma cadeia só, em modo de recuperação: os itens já passaram pelo portão de despacho quando
    // vieram de `selectDue`, e os de realarme são exatamente os que o portão mantém fora.
    report.jobId = System.enqueueJob(
      new AXF_CLS_ScheduleReplenishmentQueueable(work, 0, true)
    );
    return report;
  }
}
