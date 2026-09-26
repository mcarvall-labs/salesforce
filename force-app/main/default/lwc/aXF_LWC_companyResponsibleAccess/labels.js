import LANG from "@salesforce/i18n/lang";

const PT = {
  title: "Acesso de responsáveis pela empresa",
  subtitle:
    "Acompanhe e retire o acesso financeiro concedido a responsáveis desta empresa. Retirar um responsável remove apenas o acesso derivado desse vínculo; direitos independentes e o usuário permanecem.",
  forbidden:
    "Você não tem autorização para gerenciar responsáveis pela empresa.",
  noBusiness:
    "Abra este componente em uma empresa (Business Account) para ver os responsáveis.",
  empty: "Nenhum responsável vinculado a esta empresa.",
  error: "Não foi possível carregar os responsáveis desta empresa.",
  colPerson: "Pessoa",
  colRole: "Papel",
  colStatus: "Situação",
  colWhen: "Desde / retirado em",
  colAction: "Próxima ação",
  rolePartner: "Sócia",
  roleManager: "Administradora",
  statusGranted: "Acesso concedido",
  statusPending: "Aguardando usuário vinculado",
  statusFailed: "Falha ao conceder",
  statusRevoked: "Acesso retirado",
  hintPending:
    "O acesso é concedido automaticamente quando a pessoa tiver um usuário Axon.",
  hintRevoked: "Nenhuma ação pendente.",
  hintFailedPrefix: "Retomável: ",
  actionRevoke: "Retirar acesso",
  actionRetry: "Tentar novamente",
  actionNone: "—",
  grantedOn: "Concedido em {0}",
  revokedOn: "Retirado em {0}",
  confirmTitle: "Retirar o acesso deste responsável?",
  confirmBody:
    "O acesso financeiro derivado deste vínculo será removido e o servidor passará a negar novas leituras e ações sem outro acesso legítimo. Direitos independentes e o usuário não são afetados. A retirada só é confirmada após verificação.",
  confirmYes: "Retirar acesso",
  confirmNo: "Cancelar",
  working: "Processando…",
  revokeDone: "Acesso retirado e verificado.",
  retryDone: "Concessão reprocessada.",
  conflictReload:
    "Este responsável mudou em outra sessão. A lista foi recarregada; revise antes de continuar.",
  genericFail: "Não foi possível concluir. Tente novamente."
};

const EN = {
  title: "Company responsible access",
  subtitle:
    "Track and revoke the financial access granted to this company's responsibles. Revoking a responsible removes only the access derived from that link; independent rights and the user remain.",
  forbidden: "You are not authorized to manage company responsibles.",
  noBusiness:
    "Open this component on a company (Business Account) to see its responsibles.",
  empty: "No responsible is linked to this company.",
  error: "Could not load this company's responsibles.",
  colPerson: "Person",
  colRole: "Role",
  colStatus: "Status",
  colWhen: "Since / revoked on",
  colAction: "Next action",
  rolePartner: "Partner",
  roleManager: "Manager",
  statusGranted: "Access granted",
  statusPending: "Waiting for a linked user",
  statusFailed: "Grant failed",
  statusRevoked: "Access revoked",
  hintPending:
    "Access is granted automatically once the person has an Axon user.",
  hintRevoked: "No pending action.",
  hintFailedPrefix: "Retryable: ",
  actionRevoke: "Revoke access",
  actionRetry: "Try again",
  actionNone: "—",
  grantedOn: "Granted on {0}",
  revokedOn: "Revoked on {0}",
  confirmTitle: "Revoke this responsible's access?",
  confirmBody:
    "The financial access derived from this link is removed and the server will deny new reads and actions without other legitimate access. Independent rights and the user are not affected. Removal is only confirmed after verification.",
  confirmYes: "Revoke access",
  confirmNo: "Cancel",
  working: "Working…",
  revokeDone: "Access revoked and verified.",
  retryDone: "Grant reprocessed.",
  conflictReload:
    "This responsible changed in another session. The list was reloaded; review before continuing.",
  genericFail: "Could not finish. Try again."
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
