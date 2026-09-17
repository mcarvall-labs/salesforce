import title from "@salesforce/label/c.AXF_AddPersonAccess_title";
import subtitle from "@salesforce/label/c.AXF_AddPersonAccess_subtitle";
import forbidden from "@salesforce/label/c.AXF_AddPersonAccess_forbidden";
import stepPerson from "@salesforce/label/c.AXF_AddPersonAccess_stepPerson";
import stepUser from "@salesforce/label/c.AXF_AddPersonAccess_stepUser";
import stepScope from "@salesforce/label/c.AXF_AddPersonAccess_stepScope";
import stepReview from "@salesforce/label/c.AXF_AddPersonAccess_stepReview";
import personLabel from "@salesforce/label/c.AXF_AddPersonAccess_personLabel";
import nameLabel from "@salesforce/label/c.AXF_AddPersonAccess_nameLabel";
import emailLabel from "@salesforce/label/c.AXF_AddPersonAccess_emailLabel";
import modeLabel from "@salesforce/label/c.AXF_AddPersonAccess_modeLabel";
import modeCreate from "@salesforce/label/c.AXF_AddPersonAccess_modeCreate";
import modeLink from "@salesforce/label/c.AXF_AddPersonAccess_modeLink";
import searchUser from "@salesforce/label/c.AXF_AddPersonAccess_searchUser";
import scopeLabel from "@salesforce/label/c.AXF_AddPersonAccess_scopeLabel";
import scopeOwn from "@salesforce/label/c.AXF_AddPersonAccess_scopeOwn";
import scopeAll from "@salesforce/label/c.AXF_AddPersonAccess_scopeAll";
import licenseWarn from "@salesforce/label/c.AXF_AddPersonAccess_licenseWarn";
import back from "@salesforce/label/c.AXF_AddPersonAccess_back";
import next from "@salesforce/label/c.AXF_AddPersonAccess_next";
import confirm from "@salesforce/label/c.AXF_AddPersonAccess_confirm";
import starting from "@salesforce/label/c.AXF_AddPersonAccess_starting";
import running from "@salesforce/label/c.AXF_AddPersonAccess_running";
import done from "@salesforce/label/c.AXF_AddPersonAccess_done";
import failed from "@salesforce/label/c.AXF_AddPersonAccess_failed";
import retry from "@salesforce/label/c.AXF_AddPersonAccess_retry";
import stalled from "@salesforce/label/c.AXF_AddPersonAccess_stalled";
import watchLimit from "@salesforce/label/c.AXF_AddPersonAccess_watchLimit";
import statusUnavailable from "@salesforce/label/c.AXF_AddPersonAccess_statusUnavailable";
import leave from "@salesforce/label/c.AXF_AddPersonAccess_leave";
import leaveHint from "@salesforce/label/c.AXF_AddPersonAccess_leaveHint";
import resumeHint from "@salesforce/label/c.AXF_AddPersonAccess_resumeHint";
import backToForm from "@salesforce/label/c.AXF_AddPersonAccess_backToForm";
import close from "@salesforce/label/c.AXF_AddPersonAccess_close";
import linkedUser from "@salesforce/label/c.AXF_AddPersonAccess_linkedUser";
import statusStep from "@salesforce/label/c.AXF_AddPersonAccess_statusStep";
import statusState from "@salesforce/label/c.AXF_AddPersonAccess_statusState";
import stepOf from "@salesforce/label/c.AXF_AddPersonAccess_stepOf";
import stepNameCreateOrLinkPerson from "@salesforce/label/c.AXF_AddPersonAccess_stepNameCreateOrLinkPerson";
import stepNameCreateOrLinkUser from "@salesforce/label/c.AXF_AddPersonAccess_stepNameCreateOrLinkUser";
import stepNameAssignRole from "@salesforce/label/c.AXF_AddPersonAccess_stepNameAssignRole";
import stepNameAssignPsg from "@salesforce/label/c.AXF_AddPersonAccess_stepNameAssignPsg";
import stepNameSetOwnerSync from "@salesforce/label/c.AXF_AddPersonAccess_stepNameSetOwnerSync";
import stepNameActivate from "@salesforce/label/c.AXF_AddPersonAccess_stepNameActivate";
import stepNameDone from "@salesforce/label/c.AXF_AddPersonAccess_stepNameDone";

export default {
  title,
  subtitle,
  forbidden,
  stepPerson,
  stepUser,
  stepScope,
  stepReview,
  personLabel,
  nameLabel,
  emailLabel,
  modeLabel,
  modeCreate,
  modeLink,
  searchUser,
  scopeLabel,
  scopeOwn,
  scopeAll,
  licenseWarn,
  back,
  next,
  confirm,
  starting,
  running,
  done,
  failed,
  retry,
  stalled,
  watchLimit,
  statusUnavailable,
  leave,
  leaveHint,
  resumeHint,
  backToForm,
  close,
  linkedUser,
  statusStep,
  statusState,
  stepOf,
  // Raw checkpoint enums (e.g. "ASSIGN_ROLE") are internal identifiers; this
  // maps each one to the human sentence shown in the status line.
  stepNames: {
    CREATE_OR_LINK_PERSON: stepNameCreateOrLinkPerson,
    CREATE_OR_LINK_USER: stepNameCreateOrLinkUser,
    ASSIGN_ROLE: stepNameAssignRole,
    ASSIGN_PSG: stepNameAssignPsg,
    SET_OWNER_SYNC: stepNameSetOwnerSync,
    ACTIVATE: stepNameActivate,
    DONE: stepNameDone
  }
};
