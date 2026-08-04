import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getCategoryOptions from "@salesforce/apex/AXF_CLS_CTRL_CategoryLookup.getCategoryOptions";
import getTopLevelCategoryOptions from "@salesforce/apex/AXF_CLS_CTRL_CategoryLookup.getTopLevelCategoryOptions";
import createCategory from "@salesforce/apex/AXF_CLS_CTRL_CategoryLookup.createCategory";

const CLOSE_DELAY_MS = 150;

export default class AXF_LWC_categoryLookup extends LightningElement {
  @api label;
  @api placeholder = "Buscar categoria...";
  @api recordTypeDeveloperName;
  @api allOptionLabel = "Todas as Categorias";
  @api showAllOption = false;

  allCategories = [];
  parentCategoryOptions = [];
  searchTerm = "";
  isOpen = false;
  displayValue = "";

  isNewCategoryModalOpen = false;
  isSavingCategory = false;
  newCategoryName = "";
  newCategoryParentId = "";

  _value = "";

  @api
  get value() {
    return this._value;
  }
  set value(val) {
    this._value = val || "";
    this.syncDisplayFromValue();
  }

  @wire(getCategoryOptions, {
    recordTypeDeveloperName: "$recordTypeDeveloperName"
  })
  wiredCategories({ data }) {
    this.allCategories = data
      ? data.map((opt) => ({
          id: opt.id,
          label: opt.displayLabel,
          searchText: opt.displayLabel.toLowerCase()
        }))
      : [];
    this.syncDisplayFromValue();
  }

  @wire(getTopLevelCategoryOptions, {
    recordTypeDeveloperName: "$recordTypeDeveloperName"
  })
  wiredParentCategories({ data }) {
    this.parentCategoryOptions = data || [];
  }

  syncDisplayFromValue() {
    if (!this._value) {
      this.displayValue = "";
      return;
    }
    const match = this.allCategories.find((opt) => opt.id === this._value);
    this.displayValue = match ? match.label : "";
  }

  get inputValue() {
    return this.isOpen ? this.searchTerm : this.displayValue;
  }

  get filteredOptions() {
    const term = this.searchTerm.trim().toLowerCase();
    if (!term) {
      return this.allCategories;
    }
    return this.allCategories.filter((opt) => opt.searchText.includes(term));
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
    return !!this._value && !this.isOpen;
  }

  handleFocus() {
    this.isOpen = true;
    this.searchTerm = "";
  }

  handleBlur() {
    // The delay lets an option's mousedown handler run before the dropdown closes.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      this.isOpen = false;
      this.searchTerm = "";
    }, CLOSE_DELAY_MS);
  }

  handleInput(event) {
    this.searchTerm = event.target.value;
    this.isOpen = true;
  }

  handleOptionMouseDown(event) {
    event.preventDefault();
    const id = event.currentTarget.dataset.id;
    this.selectValue(id);
  }

  handleAllOptionMouseDown(event) {
    event.preventDefault();
    this.selectValue("");
  }

  handleClearMouseDown(event) {
    event.preventDefault();
    this.selectValue("");
  }

  selectValue(id) {
    this._value = id;
    this.syncDisplayFromValue();
    this.isOpen = false;
    this.searchTerm = "";
    this.dispatchEvent(new CustomEvent("change", { detail: { value: id } }));
  }

  handleOpenNewCategoryModal() {
    this.isOpen = false;
    this.searchTerm = "";
    this.newCategoryName = "";
    this.newCategoryParentId = "";
    this.isNewCategoryModalOpen = true;
  }

  handleCloseNewCategoryModal() {
    this.isNewCategoryModalOpen = false;
  }

  handleNewCategoryNameChange(event) {
    this.newCategoryName = event.target.value;
  }

  handleNewCategoryParentChange(event) {
    this.newCategoryParentId = event.target.value;
  }

  async handleSaveNewCategory() {
    if (!this.newCategoryName || !this.newCategoryName.trim()) {
      this.showToast("Atenção", "Informe o nome da categoria.", "warning");
      return;
    }

    this.isSavingCategory = true;
    try {
      const dto = {
        name: this.newCategoryName.trim(),
        parentId: this.newCategoryParentId || null,
        recordTypeDeveloperName: this.recordTypeDeveloperName
      };
      const created = await createCategory({ dto });
      const newOption = {
        id: created.id,
        label: created.displayLabel,
        searchText: created.displayLabel.toLowerCase()
      };
      this.allCategories = [...this.allCategories, newOption].sort((a, b) =>
        a.label.localeCompare(b.label)
      );
      this.isNewCategoryModalOpen = false;
      this.selectValue(newOption.id);
      this.showToast(
        "Sucesso",
        `Categoria "${created.displayLabel}" criada e selecionada.`,
        "success"
      );
    } catch (error) {
      const message = error.body ? error.body.message : error.message;
      this.showToast("Erro ao criar categoria", message, "error");
    } finally {
      this.isSavingCategory = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
