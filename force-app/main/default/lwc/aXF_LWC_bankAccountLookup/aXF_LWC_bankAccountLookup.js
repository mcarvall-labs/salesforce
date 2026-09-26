import { LightningElement, api, wire } from 'lwc';
import getBankAccountOptions from '@salesforce/apex/AXF_CLS_CTRL_BankAccountLookup.getBankAccountOptions';

const CLOSE_DELAY_MS = 150;

export default class AXF_LWC_bankAccountLookup extends LightningElement {
    @api label = 'Conta Bancária';
    @api placeholder = 'Buscar conta bancária...';

    allOptions = [];
    searchTerm = '';
    isOpen = false;
    displayValue = '';

    _value = '';

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val || '';
        this.syncDisplayFromValue();
    }

    @wire(getBankAccountOptions)
    wiredOptions({ data }) {
        this.allOptions = data
            ? data.map((opt) => ({
                  id: opt.id,
                  label: opt.displayLabel,
                  searchText: opt.displayLabel.toLowerCase()
              }))
            : [];
        this.syncDisplayFromValue();
    }

    syncDisplayFromValue() {
        if (!this._value) {
            this.displayValue = '';
            return;
        }
        const match = this.allOptions.find((opt) => opt.id === this._value);
        this.displayValue = match ? match.label : '';
    }

    get inputValue() {
        return this.isOpen ? this.searchTerm : this.displayValue;
    }

    get filteredOptions() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.allOptions;
        }
        return this.allOptions.filter((opt) => opt.searchText.includes(term));
    }

    get hasNoResults() {
        return this.filteredOptions.length === 0;
    }

    get comboboxClass() {
        return this.isOpen
            ? 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open'
            : 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
    }

    get showClear() {
        return !!this._value && !this.isOpen;
    }

    handleFocus() {
        this.isOpen = true;
        this.searchTerm = '';
    }

    handleBlur() {
        window.setTimeout(() => {
            this.isOpen = false;
            this.searchTerm = '';
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

    handleClearMouseDown(event) {
        event.preventDefault();
        this.selectValue('');
    }

    selectValue(id) {
        this._value = id;
        this.syncDisplayFromValue();
        this.isOpen = false;
        this.searchTerm = '';
        const match = this.allOptions.find((opt) => opt.id === id);
        const accountId = match ? match.accountId : '';
        this.dispatchEvent(new CustomEvent('change', { detail: { value: id, accountId: accountId } }));
    }
}