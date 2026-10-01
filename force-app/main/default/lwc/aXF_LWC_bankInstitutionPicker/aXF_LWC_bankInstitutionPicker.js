import { LightningElement, api, wire } from "lwc";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import CONNECTION_OBJECT from "@salesforce/schema/AXF_OBJ_PluggyConnection__c";
import INSTITUTION_FIELD from "@salesforce/schema/AXF_OBJ_PluggyConnection__c.AXF_CON_PKL_Institution__c";

const PRIORITY_CODES = ["756", "301", "341", "077", "323", "336"];

export default class AXF_LWC_bankInstitutionPicker extends LightningElement {
  @api label = "Instituição";
  @api required = false;
  _value;

  @api
  get value() {
    return this._value;
  }
  set value(newValue) {
    this._value = newValue;
  }

  searchTerm = "";
  options = [];
  error;

  @wire(getObjectInfo, { objectApiName: CONNECTION_OBJECT })
  objectInfo;

  @wire(getPicklistValues, {
    recordTypeId: "$objectInfo.data.defaultRecordTypeId",
    fieldApiName: INSTITUTION_FIELD
  })
  wiredValues({ data, error }) {
    if (data) {
      this.options = data.values;
      this.error = undefined;
    } else if (error) {
      this.options = [];
      this.error = error;
    }
  }

  get isSearching() {
    return this.searchTerm.length > 0;
  }

  get priorityItems() {
    return PRIORITY_CODES.map((code) =>
      this.options.find((o) => o.value === code)
    )
      .filter(Boolean)
      .map((o) => this.toItem(o));
  }

  get searchItems() {
    const term = this.normalize(this.searchTerm);
    return this.options
      .filter((o) => this.normalize(o.label).includes(term))
      .map((o) => this.toItem(o));
  }

  get hasSearchItems() {
    return this.searchItems.length > 0;
  }

  get selectedLabel() {
    const selected = this.options.find((o) => o.value === this.value);
    return selected ? selected.label : "";
  }

  get hasSelection() {
    return !!this.selectedLabel;
  }

  toItem(option) {
    const selected = option.value === this.value;
    return {
      value: option.value,
      label: option.label,
      className: selected
        ? "slds-listbox__option slds-is-selected"
        : "slds-listbox__option",
      ariaSelected: String(selected)
    };
  }

  normalize(text) {
    return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
  }

  handleSelect(event) {
    const value = event.currentTarget.dataset.value;
    this._value = value;
    this.searchTerm = "";
    this.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  }

  handleClear() {
    this._value = undefined;
    this.dispatchEvent(
      new CustomEvent("change", { detail: { value: undefined } })
    );
  }
}
