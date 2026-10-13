import { LightningElement, api } from "lwc";

// Category field of the expense wizard, as in the approved prototype: type to filter the
// hierarchy (parents and children, any level), pick one, or create a new category.
export default class AXF_LWC_categoryPicker extends LightningElement {
  @api label = "Categoria";
  // [{ id, label, parentId }]
  @api options = [];
  @api value;

  query = "";
  isOpen = false;

  // Depth-first walk: a parent comes right before its children. A category whose parent is
  // not in the list is treated as top level. `seen` protects against a loop in the data.
  get tree() {
    const byParent = new Map();
    const ids = new Set((this.options || []).map((o) => o.id));
    for (const option of this.options || []) {
      const key =
        option.parentId && ids.has(option.parentId) ? option.parentId : "";
      if (!byParent.has(key)) {
        byParent.set(key, []);
      }
      byParent.get(key).push(option);
    }
    const seen = new Set();
    const walk = (parentKey, depth) => {
      const rows = [];
      for (const option of byParent.get(parentKey) || []) {
        if (seen.has(option.id)) {
          continue;
        }
        seen.add(option.id);
        rows.push({ option, depth, children: walk(option.id, depth + 1) });
      }
      return rows;
    };
    return walk("", 0);
  }

  get rows() {
    const q = this.query.trim().toLowerCase();
    const flat = [];
    // A match shows all of its children (as in the prototype); an ancestor of a match is shown
    // dimmed so the path stays visible.
    const visit = (nodes, parentMatched) => {
      let anyMatch = false;
      for (const node of nodes) {
        const own =
          !q || parentMatched || node.option.label.toLowerCase().includes(q);
        const index = flat.length;
        flat.push(null);
        const childMatch = visit(node.children, own);
        if (own || childMatch) {
          flat[index] = {
            key: node.option.id,
            id: node.option.id,
            label: node.option.label,
            // An ancestor that only shows up because a descendant matched.
            dim: !own,
            className: `option depth-${Math.min(node.depth, 4)}${own ? "" : " option_dim"}`,
            selected: node.option.id === this.value
          };
          anyMatch = true;
        }
      }
      return anyMatch;
    };
    visit(this.tree, false);
    return flat.filter(Boolean);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get selectedPath() {
    const byId = new Map((this.options || []).map((o) => [o.id, o]));
    const names = [];
    const seen = new Set();
    let current = byId.get(this.value);
    while (current && !seen.has(current.id)) {
      seen.add(current.id);
      names.unshift(current.label);
      current = current.parentId ? byId.get(current.parentId) : undefined;
    }
    return names.join(" › ");
  }

  get inputValue() {
    return this.isOpen ? this.query : this.selectedPath;
  }

  get canCreate() {
    const name = this.query.trim().toLowerCase();
    return (
      !!name &&
      !(this.options || []).some((o) => o.label.toLowerCase() === name)
    );
  }

  get createLabel() {
    return `+ Nova categoria "${this.query.trim()}"`;
  }

  handleFocus() {
    this.isOpen = true;
    this.query = "";
  }

  handleBlur() {
    this.isOpen = false;
  }

  handleInput(event) {
    this.isOpen = true;
    this.query = event.detail.value || "";
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.isOpen = false;
    }
  }

  // mousedown, not click: the input would lose focus (and close the list) before the click.
  handleSelect(event) {
    event.preventDefault();
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: event.currentTarget.dataset.id }
      })
    );
    this.query = "";
    this.isOpen = false;
  }

  handleClear(event) {
    event.preventDefault();
    this.dispatchEvent(new CustomEvent("change", { detail: { value: null } }));
    this.query = "";
    this.isOpen = false;
  }

  handleCreate(event) {
    event.preventDefault();
    this.dispatchEvent(
      new CustomEvent("createcategory", { detail: { name: this.query.trim() } })
    );
    this.query = "";
    this.isOpen = false;
  }
}
