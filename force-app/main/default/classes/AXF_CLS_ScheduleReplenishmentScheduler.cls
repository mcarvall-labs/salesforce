/**
 * AXF-103 fatia 2 — agendador da reposição rolante da janela do cronograma.
 *
 * O agendador NÃO gera nada: ele apenas seleciona cronogramas vencidos e habilitados e enfileira
 * trabalho limitado. Toda geração passa pela porta única de escrita, o que mantém uma autoridade
 * só sobre identidade e valor.
 *
 * Duas passagens do contrato (L85): a MENSAL e a de RECUPERAÇÃO
 * (`AXF_CLS_ScheduleReplenishmentRecovery`, que também realarma o orçamento esgotado). As duas
 * expressões CRON vivem em `AXF_ScheduleReplenishmentPolicy__mdt.Default` — artefato versionado,
 * e não comentário de código. Registrar o `CronTrigger` permanece passo de OPERAÇÃO do dono: este
 * deploy não agenda nada.
 *
 * FATO DE PLATAFORMA VERIFICADO: `System.schedule` NAO tem overload com fuso — o compilador
 * recusa a quarta assinatura, e o `CronTrigger` herda o fuso do USUARIO que registra. Portanto a
 * promessa de "04:00" so se sustenta com quem registra no fuso declarado, e o registro RECUSA rodar
 * fora dele em vez de prometer um horario que nao sera cumprido:
 *   AXF_CLS_ScheduleReplenishmentScheduler.registerMonthly();
 *   AXF_CLS_ScheduleReplenishmentRecovery.registerRecovery();
 * `AXF_CLS_ScheduleReplenishmentPolicy.describeSchedule()` devolve as duas expressões, o fuso
 * DECLARADO, o fuso EFETIVO do principal e o nome das classes e dos jobs, para que o passo de
 * operação leia de uma superfície só.
 *
 * QUEM pode disparar: despacho e recuperação dirigida são operações do DONO/principal técnico
 * provisionado, não do Gestor Financeiro. `AXF_PS_GestorFinanceiro` não concede acesso de classe a
 * nenhuma classe desta fatia; o permission set dedicado do principal técnico continua pendente e é
 * passo do dono antes de ligar a funcionalidade.
 */
public with sharing class AXF_CLS_ScheduleReplenishmentScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    run();
  }

  /**
   * @description Passo de OPERAÇÃO do dono: registra o job mensal com a expressão aprovada, no
   * fuso declarado. Recusa quando o principal que registra está em outro fuso — sem isso o
   * `CronTrigger` herdaria o fuso do usuário e cumpriria outro horário em silêncio.
   */
  public static Id registerMonthly() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    policy.requireRegisteringPrincipalInDeclaredTimeZone();
    return System.schedule(
      AXF_CLS_ScheduleReplenishmentPolicy.MONTHLY_JOB_NAME,
      policy.monthlyCron,
      new AXF_CLS_ScheduleReplenishmentScheduler()
    );
  }

  /**
   * Rastro consultável de UMA passagem de despacho: quantos candidatos foram lidos, quantos
   * despachados, quantas verificações de lacuna foram consumidas, quantos candidatos foram
   * despachados SEM verificação e quantos cronogramas entraram pela leitura de realarme.
   */
  public class PassReport {
    public Id jobId;
    public Integer candidatesRead = 0;
    public Integer dispatched = 0;
    public Integer holeChecksConsumed = 0;
    public Integer unverifiedDispatched = 0;
    public Integer holesFound = 0;
    public Integer skippedByState = 0;
    public Integer rearmCandidatesRead = 0;
    public Integer rearmDispatched = 0;

    public String describe() {
      return 'passagem job=' +
        jobId +
        ' candidatos=' +
        candidatesRead +
        ' despachados=' +
        dispatched +
        ' verificacoesLacuna=' +
        holeChecksConsumed +
        ' naoVerificadosDespachados=' +
        unverifiedDispatched +
        ' lacunas=' +
        holesFound +
        ' puladosPorEstado=' +
        skippedByState +
        ' realarmeLidos=' +
        rearmCandidatesRead +
        ' realarmeDespachados=' +
        rearmDispatched;
    }
  }

  /**
   * @description Uma passagem: seleciona o trabalho devido e entrega UMA cadeia limitada.
   * Devolve o rastro da passagem, com o id do job enfileirado quando houve trabalho.
   *
   * O que exceder o lote desta passagem não é descartado: permanece no conjunto devido (a
   * seleção é por cobertura atrás da janela, então um cronograma coberto sai por si) e é
   * re-selecionado pela própria cadeia, que continua drenando enquanto houver trabalho, ou pela
   * passagem seguinte do agendamento. Ausência de política aprovada faz a passagem FALHAR
   * VISIVELMENTE em vez de rodar com limite adivinhado.
   */
  public static PassReport run() {
    AXF_CLS_ScheduleReplenishmentPolicy policy = AXF_CLS_ScheduleReplenishmentPolicy.current();
    List<AXF_CLS_ScheduleReplenishmentSelector.WorkItem> due = AXF_CLS_ScheduleReplenishmentSelector.selectDue(
      policy.dispatchBatchSize
    );
    PassReport report = reportOf(
      AXF_CLS_ScheduleReplenishmentSelector.lastTrace()
    );
    if (due.isEmpty()) {
      return report;
    }
    report.jobId = System.enqueueJob(
      new AXF_CLS_ScheduleReplenishmentQueueable(due, 0)
    );
    return report;
  }

  /**
   * @description Passagem de recuperação DIRIGIDA: retoma cronogramas NOMEADOS cujo estado ficou
   * acionável (orçamento esgotado, código terminal), porque o operador já corrigiu a causa.
   * Ignora apenas o portão de DESPACHO; estado, enabled-state, autoridade do titular e permissão
   * continuam sendo revalidados na transação de geração, e uma passagem bem-sucedida limpa o
   * estado. É este caminho que torna o estado esgotado acionável em vez de apenas visível.
   *
   * O chamador é submetido à autoridade de titular do serviço ANTES de qualquer identidade ser
   * devolvida: um cronograma cujo titular ele não enxerga é recusado e relatado, nunca processado
   * em silêncio — senão "dirigir recuperação" viraria um caminho para queimar o estado acionável
   * de um titular alheio.
   */
  public static RecoveryResult recover(Set<Id> scheduleIds) {
    AXF_CLS_ScheduleReplenishmentSelector.DirectedWork work = AXF_CLS_ScheduleReplenishmentSelector.directedWork(
      scheduleIds
    );
    RecoveryResult result = new RecoveryResult();
    result.refused = work.refused;
    result.accepted = work.accepted.size();
    if (work.accepted.isEmpty()) {
      result.message = 'Nenhum dos cronogramas nomeados pôde ser retomado: nenhum titular autorizado foi comprovado ou nenhum Id corresponde a um cronograma. Nada foi enfileirado.';
      return result;
    }
    result.jobId = AXF_CLS_ScheduleReplenishmentQueueable.recover(
      work.accepted
    );
    result.message =
      work.accepted.size() +
      ' cronograma(s) retomado(s) pela passagem dirigida' +
      (work.refused.isEmpty()
        ? '.'
        : '; ' +
          work.refused.size() +
          ' recusado(s) por falta de autoridade comprovada sobre o titular.');
    return result;
  }

  /** Desfecho da passagem dirigida, incluindo o que foi recusado e por quê. */
  public class RecoveryResult {
    public Id jobId;
    public Integer accepted = 0;
    public List<Id> refused = new List<Id>();
    public String message;
  }

  private static PassReport reportOf(
    AXF_CLS_ScheduleReplenishmentSelector.DispatchTrace trace
  ) {
    PassReport report = new PassReport();
    if (trace == null) {
      return report;
    }
    report.candidatesRead = trace.candidatesRead;
    report.dispatched = trace.dispatched;
    report.holeChecksConsumed = trace.holeChecksConsumed;
    report.unverifiedDispatched = trace.unverifiedDispatched;
    report.holesFound = trace.holesFound;
    report.skippedByState = trace.skippedByState;
    report.rearmCandidatesRead = trace.rearmCandidatesRead;
    report.rearmDispatched = trace.rearmDispatched;
    return report;
  }
}
