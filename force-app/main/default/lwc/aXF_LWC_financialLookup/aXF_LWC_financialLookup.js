import { LightningElement, api } from "lwc";

export default class AXF_LWC_financialLookup extends LightningElement {
  @api label;
  @api name;
  @api placeholder = "Buscar...";
  @api disabled = false;
  @api required = false;

  searchTerm = "";
  isOpen = false;
  _options = [];
  _value = "";

  @api
  get options() {
    return this._options;
  }
  set options(value) {
    this._options = (value || []).map((option) => ({
      id: option.id,
      label: option.displayLabel,
      searchText: option.displayLabel.toLowerCase()
    }));
  }

  @api
  get value() {
    return this._value;
  }
  set value(value) {
    this._value = value || "";
  }

  get selectedLabel() {
    return (
      this._options.find((option) => option.id === this._value)?.label || ""
    );
  }

  get inputValue() {
    return this.isOpen ? this.searchTerm : this.selectedLabel;
  }

  get filteredOptions() {
    const term = this.searchTerm.trim().toLowerCase();
    return term
      ? this._options.filter((option) => option.searchText.includes(term))
      : this._options;
  }

  get hasNoResults() {
    return this.filteredOptions.length === 0;
  }

  get comboboxClass() {
    return this.isOpen
      ? "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open"
      : "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click";
  }

  get showClear() {
    return Boolean(this._value) && !this.isOpen && !this.disabled;
  }

  handleFocus() {
    if (!this.disabled) {
      this.searchTerm = "";
      this.isOpen = true;
    }
  }

  handleBlur() {
    this.isOpen = false;
    this.searchTerm = "";
  }

  handleInput(event) {
    this.searchTerm = event.target.value;
    this.isOpen = true;
  }

  handleOptionMouseDown(event) {
    event.preventDefault();
    this.selectValue(event.currentTarget.dataset.id);
  }

  handleClearMouseDown(event) {
    event.preventDefault();
    this.selectValue("");
  }

  selectValue(value) {
    this._value = value;
    this.isOpen = false;
    this.searchTerm = "";
    this.dispatchEvent(
      new CustomEvent("change", { detail: { name: this.name, value } })
    );
  }
}
