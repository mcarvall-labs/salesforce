import { LightningElement, api } from "lwc";

const MAX_NAME = 80;

// Case and accent insensitive: "agua" finds "Água".
const normalize = (text) =>
  (text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

// Category field of the expense wizard, as in the approved prototype: type to filter the
// hierarchy (parents and children, any level), pick one, or create a new category. Works with
// the keyboard: ArrowUp/ArrowDown move, Enter picks, Escape closes.
export default class AXF_LWC_categoryPicker extends LightningElement {
  @api label = "Categoria";
  // [{ id, label, parentId }]
  @api options = [];
  @api value;

  query = "";
  isOpen = false;
  // "+ Nova categoria" step: the name is kept while the user picks the parent.
  isCreating = false;
  newName = "";
  newParentId = "";
  // Index in `actions` of the row under the keyboard; -1 = none.
  activeIndex = -1;

  // Depth-first walk: a parent comes right before its children. A category whose parent is
  // not in the list is treated as top level. A category that is only reachable through a loop
  // in the data (A under B under A) is appended at the top level, so it stays selectable.
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
    const roots = walk("", 0);
    for (const option of this.options || []) {
      if (!seen.has(option.id)) {
        seen.add(option.id);
        roots.push({ option, depth: 0, children: walk(option.id, 1) });
      }
    }
    return roots;
  }

  get matches() {
    const q = normalize(this.query.trim());
    const flat = [];
    // A match shows all of its children (as in the prototype); an ancestor of a match is shown
    // dimmed so the path stays visible.
    const visit = (nodes, parentMatched) => {
      let anyMatch = false;
      for (const node of nodes) {
        const own =
          !q || parentMatched || normalize(node.option.label).includes(q);
        const index = flat.length;
        flat.push(null);
        const childMatch = visit(node.children, own);
        if (own || childMatch) {
          flat[index] = {
            id: node.option.id,
            label: node.option.label,
            depth: node.depth,
            dim: !own
          };
          anyMatch = true;
        }
      }
      return anyMatch;
    };
    visit(this.tree, false);
    return flat.filter(Boolean);
  }

  // Everything the keyboard can reach, in display order.
  get actions() {
    const list = this.matches.map((m) => ({ type: "option", id: m.id }));
    if (this.canCreate) {
      list.push({ type: "create" });
    }
    if (this.value) {
      list.push({ type: "clear" });
    }
    return list;
  }

  get rows() {
    return this.matches.map((m, index) => ({
      key: m.id,
      id: m.id,
      label: m.label,
      selected: m.id === this.value || index === this.activeIndex,
      className: [
        "option",
        `depth-${Math.min(m.depth, 4)}`,
        m.dim ? "option_dim" : "",
        index === this.activeIndex ? "option_active" : ""
      ]
        .filter(Boolean)
        .join(" ")
    }));
  }

  get hasRows() {
    return this.matches.length > 0;
  }

  get noRows() {
    return !this.hasRows;
  }

  get createClass() {
    return this.classFor("create", "option option_new");
  }

  get clearClass() {
    return this.classFor("clear", "option option_clear");
  }

  classFor(type, base) {
    const active = this.actions[this.activeIndex];
    return active && active.type === type ? `${base} option_active` : base;
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

  // While typing, the chosen category stays visible as the hint.
  get placeholder() {
    return this.selectedPath || "Digite para filtrar, ex.: Moradia ou Energia";
  }

  get maxName() {
    return MAX_NAME;
  }

  get typedName() {
    return this.query.trim().slice(0, MAX_NAME);
  }

  get canCreate() {
    const name = normalize(this.typedName);
    return (
      !!name && !(this.options || []).some((o) => normalize(o.label) === name)
    );
  }

  // Every category as "Moradia › Energia", in tree order, to choose the parent of a new one.
  get parentOptions() {
    const flat = [{ label: "Nenhuma (nível raiz)", value: "" }];
    const walk = (nodes, prefix) => {
      for (const node of nodes) {
        const path = prefix
          ? `${prefix} › ${node.option.label}`
          : node.option.label;
        flat.push({ label: path, value: node.option.id });
        walk(node.children, path);
      }
    };
    walk(this.tree, "");
    return flat;
  }

  get createLabel() {
    return `+ Nova categoria "${this.typedName}"`;
  }

  renderedCallback() {
    const active = this.template.querySelector(".option_active");
    if (active && active.scrollIntoView) {
      active.scrollIntoView({ block: "nearest" });
    }
  }

  handleFocus() {
    this.isOpen = true;
    this.query = "";
    this.activeIndex = -1;
  }

  handleBlur() {
    this.isOpen = false;
  }

  handleInput(event) {
    this.isOpen = true;
    this.query = event.detail.value || "";
    this.activeIndex = -1;
  }

  handleKeydown(event) {
    const count = this.actions.length;
    if (event.key === "Escape") {
      this.isOpen = false;
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      this.isOpen = true;
      if (count) {
        const step = event.key === "ArrowDown" ? 1 : -1;
        this.activeIndex = (this.activeIndex + step + count + 1) % (count + 1);
        if (this.activeIndex === count) {
          this.activeIndex = -1;
        }
      }
    } else if (event.key === "Enter" && this.isOpen) {
      const action = this.actions[this.activeIndex];
      if (action) {
        event.preventDefault();
        this.run(action);
      }
    }
  }

  run(action) {
    if (action.type === "option") {
      this.dispatchEvent(
        new CustomEvent("change", { detail: { value: action.id } })
      );
    } else if (action.type === "clear") {
      this.dispatchEvent(
        new CustomEvent("change", { detail: { value: null } })
      );
    } else {
      // Not created yet: the user still chooses where it goes in the tree.
      this.newName = this.typedName;
      this.newParentId = this.value || "";
      this.isCreating = true;
    }
    this.query = "";
    this.activeIndex = -1;
    this.isOpen = false;
  }

  // mousedown, not click: the input would lose focus (and close the list) before the click.
  handleSelect(event) {
    event.preventDefault();
    this.run({ type: "option", id: event.currentTarget.dataset.id });
  }

  handleClear(event) {
    event.preventDefault();
    this.run({ type: "clear" });
  }

  handleCreate(event) {
    event.preventDefault();
    this.run({ type: "create" });
  }

  // Keeps the focus on the input when the user presses the scrollbar or the list background.
  handleListMouseDown(event) {
    event.preventDefault();
  }

  handleParentChange(event) {
    this.newParentId = event.detail.value || "";
  }

  handleConfirmCreate() {
    this.dispatchEvent(
      new CustomEvent("createcategory", {
        detail: { name: this.newName, parentId: this.newParentId || null }
      })
    );
    this.isCreating = false;
  }

  handleCancelCreate() {
    this.isCreating = false;
  }
}
