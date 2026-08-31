import LANG from "@salesforce/i18n/lang";

/**
 * Bundled PT-BR / EN strings for the holder register (AXF-80, AC6).
 * The org has no Translation Workbench setup, so i18n is component-local:
 * PT-BR is the base, EN is selected when the user's language starts with "en".
 */
const PT = {
  title: "Titulares",
  subtitle:
    "Pessoas e empresas titulares. Cadastrar aqui não cria usuário, conta ou vínculo.",
  loading: "Carregando titulares…",
  empty: "Nenhum titular cadastrado ainda.",
  emptyHint:
    "O primeiro titular pode ser cadastrado sem banco conectado ou onboarding.",
  errorTitle: "Não foi possível carregar",
  retry: "Tentar novamente",
  forbidden:
    "Você pode consultar titulares, mas não tem autorização para cadastrar ou editar.",
  newHolder: "Novo titular",
  search: "Buscar por nome",
  colName: "Nome",
  colType: "Tipo",
  colOwner: "Proprietário (Salesforce)",
  typePerson: "Pessoa",
  typeBusiness: "Empresa",
  fieldType: "Tipo de titular",
  fieldFirstName: "Nome",
  fieldLastName: "Sobrenome",
  fieldBusinessName: "Razão social / nome da empresa",
  save: "Salvar",
  cancel: "Cancelar",
  saving: "Salvando…",
  saved: "Titular salvo.",
  editTitle: "Editar titular",
  createTitle: "Cadastrar titular",
  dupTitle: "Possível duplicado",
  dupBody:
    "Já existe titular com este nome. Nomes iguais não provam que é a mesma pessoa ou empresa.",
  dupConfirm: "Cadastrar assim mesmo",
  conflict:
    "Este titular mudou desde que você abriu a tela. Recarregue e revise antes de salvar.",
  genericError: "Não foi possível salvar. Nada foi alterado.",
  reload: "Recarregar"
};

const EN = {
  title: "Holders",
  subtitle:
    "Person and business holders. Registering here creates no user, account or link.",
  loading: "Loading holders…",
  empty: "No holders registered yet.",
  emptyHint:
    "The first holder can be registered with no connected bank or onboarding.",
  errorTitle: "Could not load",
  retry: "Try again",
  forbidden: "You can view holders but are not authorized to register or edit.",
  newHolder: "New holder",
  search: "Search by name",
  colName: "Name",
  colType: "Type",
  colOwner: "Owner (Salesforce)",
  typePerson: "Person",
  typeBusiness: "Business",
  fieldType: "Holder type",
  fieldFirstName: "First name",
  fieldLastName: "Last name",
  fieldBusinessName: "Legal / business name",
  save: "Save",
  cancel: "Cancel",
  saving: "Saving…",
  saved: "Holder saved.",
  editTitle: "Edit holder",
  createTitle: "Register holder",
  dupTitle: "Possible duplicate",
  dupBody:
    "A holder with this name already exists. Equal names do not prove the same person or business.",
  dupConfirm: "Register anyway",
  conflict:
    "This holder changed since you opened the screen. Reload and review before saving.",
  genericError: "Could not save. Nothing was changed.",
  reload: "Reload"
};

const L = String(LANG || "")
  .toLowerCase()
  .startsWith("en")
  ? EN
  : PT;
export default L;
