/**
 * AXF-103 — porta de LEITURA do cronograma financeiro para UI e consumidores.
 *
 * Existe separada de ALT_CLS_FinancialScheduleService de propósito: o acesso de classe em
 * Apex não é granular por método, então um perfil somente-leitura (Participante) que precise
 * ler a projeção não pode receber acesso à classe que contém o comando de escrita. Aqui vive
 * apenas leitura; a escrita permanece em ALT_CLS_FinancialScheduleService, concedida somente
 * a quem pode criar cronogramas.
 *
 * A autoridade continua sendo a do titular (AXF-3), conferida dentro do motor de projeção:
 * esta porta não amplia acesso, apenas o expõe.
 */
public with sharing class AXF_CLS_CTRL_FinancialSchedule {
  /**
   * @description Compromisso restante do cronograma, pelo motor único de projeção.
   * Parâmetros primitivos (e não o DTO do serviço) porque o Aura não preenche campos de uma
   * classe interna de outra classe top-level — mesma convenção de AXF_CLS_CTRL_ScheduleWizard.
   */
  @AuraEnabled
  public static ALT_CLS_ScheduleProjection.ProjectionResult readProjection(
    Id scheduleId,
    Date asOfDate,
    Integer throughSequence
  ) {
    ALT_CLS_ScheduleProjection.ProjectionInput input = new ALT_CLS_ScheduleProjection.ProjectionInput();
    input.scheduleId = scheduleId;
    input.asOfDate = asOfDate;
    input.throughSequence = throughSequence;
    return ALT_CLS_FinancialScheduleService.readProjection(input);
  }
}
