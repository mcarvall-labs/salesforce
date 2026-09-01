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
  cancel: "Cancelar",
  starting: "Iniciando…",
  running: "Provisionando… acompanhe o andamento.",
  done: "Acesso concluído.",
  failed: "Não foi possível concluir. Veja a mensagem e retome.",
  retry: "Retomar",
  statusStep: "Etapa",
  statusState: "Situação"
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
  cancel: "Cancel",
  starting: "Starting…",
  running: "Provisioning… follow the progress.",
  done: "Access granted.",
  failed: "Could not finish. Read the message and resume.",
  retry: "Resume",
  statusStep: "Step",
  statusState: "State"
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
