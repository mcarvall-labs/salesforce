import LANG from "@salesforce/i18n/lang";

const PT = {
  title: "Adicionar pessoa e dar acesso ao Axon",
  subtitle:
    "Cria ou vincula um usuário Salesforce a uma pessoa e aplica o nível de acesso. Não muda senha nem perfil de usuário existente.",
  forbidden: "Você não tem autorização para conceder acesso ao Axon.",
  stepPerson: "Pessoa",
  stepUser: "Usuário",
  stepScope: "Acesso",
  stepReview: "Revisar",
  personLabel: "Pessoa (Person Account)",
  nameLabel: "Nome",
  emailLabel: "E-mail",
  modeLabel: "Usuário Salesforce",
  modeCreate: "Criar novo usuário",
  modeLink: "Vincular usuário existente",
  searchUser: "Buscar usuário por nome, login ou e-mail",
  scopeLabel: "Nível de acesso",
  scopeOwn:
    "Só os próprios dados e empresas sob responsabilidade (Participante)",
  scopeAll: "Todos os dados do Axon (Gestor Financeiro)",
  licenseWarn: "Não há licença Salesforce disponível para criar um usuário.",
  back: "Voltar",
  next: "Próximo",
  confirm: "Confirmar",
  starting: "Iniciando…",
  running: "Provisionando… acompanhe o andamento.",
  done: "Acesso concluído.",
  failed: "Não foi possível concluir. Veja a mensagem e retome.",
  retry: "Retomar",
  stalled:
    "Sem progresso por um tempo. O provisionamento pode continuar no servidor; retome para continuar.",
  watchLimit:
    "O acompanhamento automático atingiu o limite de espera. O provisionamento pode continuar no servidor; retome para verificar.",
  statusUnavailable:
    "Não foi possível consultar o andamento agora. O provisionamento pode continuar no servidor; retome para verificar.",
  leave: "Sair e continuar depois",
  leaveHint:
    "O provisionamento pode continuar no servidor. Ao voltar, retome pelo mesmo cadastro — nada é duplicado.",
  resumeHint: "Retoma agora e confere se já terminou.",
  backToForm: "Voltar ao formulário",
  close: "Adicionar outra pessoa",
  linkedUser: "Usuário vinculado",
  statusStep: "Etapa",
  statusState: "Situação",
  stepOf: "Etapa {0} de {1}",
  stepNames: {
    CREATE_OR_LINK_PERSON: "Confirmando a pessoa",
    CREATE_OR_LINK_USER: "Criando ou vinculando o usuário",
    ASSIGN_ROLE: "Atribuindo o papel",
    ASSIGN_PSG: "Atribuindo as permissões de acesso",
    SET_OWNER_SYNC: "Sincronizando o responsável",
    ACTIVATE: "Ativando o usuário",
    DONE: "Concluído"
  }
};

const EN = {
  title: "Add a person and grant Axon access",
  subtitle:
    "Creates or links a Salesforce user to a person and applies the access level. Never changes a password or an existing user's profile.",
  forbidden: "You are not authorized to grant Axon access.",
  stepPerson: "Person",
  stepUser: "User",
  stepScope: "Access",
  stepReview: "Review",
  personLabel: "Person (Person Account)",
  nameLabel: "Name",
  emailLabel: "Email",
  modeLabel: "Salesforce user",
  modeCreate: "Create a new user",
  modeLink: "Link an existing user",
  searchUser: "Search a user by name, username or email",
  scopeLabel: "Access level",
  scopeOwn:
    "Only their own data and businesses they are responsible for (Participant)",
  scopeAll: "All Axon data (Financial Manager)",
  licenseWarn: "No Salesforce license is available to create a user.",
  back: "Back",
  next: "Next",
  confirm: "Confirm",
  starting: "Starting…",
  running: "Provisioning… follow the progress.",
  done: "Access granted.",
  failed: "Could not finish. Read the message and resume.",
  retry: "Resume",
  stalled:
    "No progress for a while. Provisioning may still be running on the server; resume to continue.",
  watchLimit:
    "Automatic tracking reached its wait limit. Provisioning may still be running on the server; resume to check.",
  statusUnavailable:
    "Could not read the progress now. Provisioning may still be running on the server; resume to check.",
  leave: "Leave and continue later",
  leaveHint:
    "Provisioning may keep running on the server. Coming back, resume the same request — nothing is duplicated.",
  resumeHint: "Resumes now and checks whether it already finished.",
  backToForm: "Back to the form",
  close: "Add another person",
  linkedUser: "Linked user",
  statusStep: "Step",
  statusState: "State",
  stepOf: "Step {0} of {1}",
  stepNames: {
    CREATE_OR_LINK_PERSON: "Confirming the person",
    CREATE_OR_LINK_USER: "Creating or linking the user",
    ASSIGN_ROLE: "Assigning the role",
    ASSIGN_PSG: "Assigning access permissions",
    SET_OWNER_SYNC: "Syncing the responsible owner",
    ACTIVATE: "Activating the user",
    DONE: "Done"
  }
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
