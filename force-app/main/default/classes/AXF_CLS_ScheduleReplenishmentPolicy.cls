/**
 * @description Leitor tipado de AXF_ScheduleReplenishmentPolicy__mdt (AXF-103 fatia 2).
 *
 * Toda a cadencia e os limites do despacho — expressao CRON mensal, expressao CRON de
 * recuperacao, fuso, tamanho do lote de despacho, teto de rodadas de continuacao, janela do
 * realarme e a escada de recuo — vem do registro "Default" aprovado, nunca de um literal no
 * agendador. A expressao do cronograma, em particular, fica em artefato versionado em vez de
 * comentario; registrar o `CronTrigger` continua sendo passo de operacao do dono.
 *
 * O orcamento de tentativas NAO e declarado duas vezes: ele e o tamanho da escada aprovada
 * (`ALT_CLS_ScheduleReplenishment.MAX_RETRY_COUNT`), e a escada declarada precisa ser exatamente
 * 1, 5, 30 minutos — altera-la exige aprovacao humana.
 *
 * Os limites DECLARADOS sao validados na fronteira, porque a plataforma nao impoe `<required>`
 * de custom metadata: registro ausente, campo em branco, valor nao numerico, lote ou rodadas
 * fora do teto da cadeia => o despacho RECUSA rodar, em vez de usar um default inventado.
 */
public inherited sharing class AXF_CLS_ScheduleReplenishmentPolicy {
  private static final String RECORD_NAME = 'Default';

  /** Nomes dos dois jobs agendados. São passo de OPERAÇÃO do dono, não metadado versionado. */
  public static final String MONTHLY_JOB_NAME = 'AXF Reposicao Rolante';
  public static final String RECOVERY_JOB_NAME = 'AXF Reposicao Rolante Recuperacao';

  @TestVisible
  private static AXF_ScheduleReplenishmentPolicy__mdt overrideRecord;

  /** Forca o caminho "sem politica aprovada" mesmo com o registro Default publicado na org. */
  @TestVisible
  private static Boolean forceMissing = false;

  public class PolicyException extends Exception {
  }

  public final String monthlyCron;
  public final String recoveryCron;
  public final String scheduleTimeZone;
  public final Integer dispatchBatchSize;
  public final Integer maxContinuationRounds;
  public final Integer rearmHours;
  public final List<Integer> backoffMinutes;

  private AXF_CLS_ScheduleReplenishmentPolicy(
    AXF_ScheduleReplenishmentPolicy__mdt record
  ) {
    this.monthlyCron = blankToNull(record.AXF_SRP_TXT_MonthlyCron__c);
    this.recoveryCron = blankToNull(record.AXF_SRP_TXT_RecoveryCron__c);
    this.scheduleTimeZone = blankToNull(record.AXF_SRP_TXT_ScheduleTimeZone__c);
    this.dispatchBatchSize = intOf(record.AXF_SRP_NUM_DispatchBatchSize__c);
    this.maxContinuationRounds = intOf(
      record.AXF_SRP_NUM_MaxContinuationRounds__c
    );
    this.rearmHours = intOf(record.AXF_SRP_NUM_RearmHours__c);
    this.backoffMinutes = ladderOf(record.AXF_SRP_TXT_BackoffMinutes__c);
  }

  /**
   * @description A politica aprovada. Recusa rodar quando o registro esta ausente ou tem valor
   * inutilizavel, para que uma passagem nunca prossiga com um limite adivinhado.
   */
  public static AXF_CLS_ScheduleReplenishmentPolicy current() {
    AXF_ScheduleReplenishmentPolicy__mdt record = forceMissing
      ? null
      : (overrideRecord != null
          ? overrideRecord
          : AXF_ScheduleReplenishmentPolicy__mdt.getInstance(RECORD_NAME));
    if (record == null) {
      throw new PolicyException(
        'Politica da reposicao rolante nao configurada (AXF_ScheduleReplenishmentPolicy__mdt.Default). ' +
        'Publique a cadencia e os limites aprovados antes de despachar a reposicao.'
      );
    }
    AXF_CLS_ScheduleReplenishmentPolicy policy = new AXF_CLS_ScheduleReplenishmentPolicy(
      record
    );
    if (
      policy.monthlyCron == null ||
      policy.recoveryCron == null ||
      policy.scheduleTimeZone == null ||
      policy.dispatchBatchSize == null ||
      policy.dispatchBatchSize < 1 ||
      policy.maxContinuationRounds == null ||
      policy.maxContinuationRounds < 1 ||
      policy.rearmHours == null ||
      policy.rearmHours < 1
    ) {
      throw new PolicyException(
        'Politica da reposicao rolante com valores invalidos. Revise AXF_ScheduleReplenishmentPolicy__mdt.Default.'
      );
    }
    if (
      !ALT_CLS_ScheduleReplenishment.isApprovedLadder(policy.backoffMinutes)
    ) {
      throw new PolicyException(
        'A escada de recuo declarada nao e a aprovada (1, 5 e 30 minutos). Alterar o recuo exige aprovacao humana.'
      );
    }
    // Limite DECLARADO da cadeia: o lote vezes as rodadas nao pode prometer mais cronogramas do
    // que o teto assincrono aceito. Descobrir esse teto no meio da drenagem seria caro.
    if (
      !ALT_CLS_ScheduleReplenishment.isChainBudgetRespected(
        policy.dispatchBatchSize,
        policy.maxContinuationRounds
      )
    ) {
      throw new PolicyException(
        'A politica da reposicao promete ' +
          policy.dispatchBatchSize +
          ' cronogramas por rodada em ' +
          policy.maxContinuationRounds +
          ' rodadas, acima do teto declarado de ' +
          ALT_CLS_ScheduleReplenishment.MAX_SCHEDULES_PER_CHAIN +
          ' cronogramas por cadeia. Reduza o lote ou as rodadas.'
      );
    }
    return policy;
  }

  /**
   * @description Superficie de OPERACAO: o texto que o dono usa para registrar os dois jobs
   * agendados. Ele traz as DUAS expressoes, o fuso DECLARADO, o fuso EFETIVO do principal que
   * registra e o nome das classes, de modo que o passo de operacao nao dependa de reescrever o que
   * o registro aprovado diz.
   *
   * FATO DE PLATAFORMA VERIFICADO (o compilador recusa a quarta assinatura): `System.schedule` NAO
   * aceita fuso como argumento. O `CronTrigger` herda o fuso do USUARIO que registra, e portanto a
   * promessa de "04:00" so se sustenta se quem registra estiver no fuso declarado. E por isso que
   * `requireRegisteringPrincipalInDeclaredTimeZone()` existe e que o registro RECUSA rodar fora
   * dele, em vez de prometer um horario que nao sera cumprido.
   */
  public String describeSchedule() {
    return 'mensal=[' +
      monthlyCron +
      '] recuperacao=[' +
      recoveryCron +
      '] fusoDeclarado=' +
      scheduleTimeZone +
      ' fusoDoRegistrante=' +
      UserInfo.getTimeZone().getID() +
      ' jobMensal=' +
      MONTHLY_JOB_NAME +
      ' jobRecuperacao=' +
      RECOVERY_JOB_NAME +
      ' classeMensal=AXF_CLS_ScheduleReplenishmentScheduler' +
      ' classeRecuperacao=AXF_CLS_ScheduleReplenishmentRecovery' +
      ' lote=' +
      dispatchBatchSize +
      ' rodadas=' +
      maxContinuationRounds +
      ' realarmeHoras=' +
      rearmHours;
  }

  /**
   * @description O principal que registra esta no fuso DECLARADO? Como `System.schedule` nao aceita
   * fuso, o `CronTrigger` herda o do usuario; registrar de outro fuso cumpriria um horario
   * diferente do aprovado. A recusa e explicita e acionavel, em vez de silenciosa.
   */
  public void requireRegisteringPrincipalInDeclaredTimeZone() {
    String effective = UserInfo.getTimeZone().getID();
    if (effective != scheduleTimeZone) {
      throw new PolicyException(
        'O fuso do principal que registra (' +
          effective +
          ') difere do fuso declarado na politica (' +
          scheduleTimeZone +
          '). System.schedule nao aceita fuso e o CronTrigger herda o do usuario, entao registrar aqui cumpriria um horario diferente do aprovado. Registre com um principal no fuso declarado.'
      );
    }
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  private static Integer intOf(Decimal value) {
    return (value == null) ? null : Integer.valueOf(value);
  }

  /** Escada declarada como lista de minutos. Texto invalido devolve lista vazia, que e recusada. */
  private static List<Integer> ladderOf(String declared) {
    List<Integer> ladder = new List<Integer>();
    if (String.isBlank(declared)) {
      return ladder;
    }
    for (String part : declared.split(',')) {
      String token = part.trim();
      if (token == '' || !Pattern.matches('^[0-9]{1,3}$', token)) {
        return new List<Integer>();
      }
      ladder.add(Integer.valueOf(token));
    }
    return ladder;
  }
}
