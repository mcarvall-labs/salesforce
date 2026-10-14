import { createElement } from "lwc";
import AXF_LWC_categoryPicker from "c/aXF_LWC_categoryPicker";

const flushPromises = () =>
  Array.from({ length: 5 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );

const options = [
  { id: "m", label: "Moradia" },
  { id: "e", label: "Energia", parentId: "m" },
  { id: "a", label: "Água", parentId: "m" },
  { id: "l", label: "Lazer" },
  { id: "c", label: "Cinema", parentId: "l" },
  { id: "o", label: "Órfã", parentId: "fora-da-lista" }
];

async function mount(props = {}) {
  const element = createElement("c-a-x-f-l-w-c-category-picker", {
    is: AXF_LWC_categoryPicker
  });
  Object.assign(element, { options, ...props });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const $ = (element, selector) => element.shadowRoot.querySelector(selector);
const labels = (element) =>
  Array.from(element.shadowRoot.querySelectorAll("li[data-id]")).map((li) =>
    li.textContent.trim()
  );

async function open(element) {
  $(element, ".category-search").dispatchEvent(new CustomEvent("focus"));
  await flushPromises();
}

async function search(element, text) {
  $(element, ".category-search").dispatchEvent(
    new CustomEvent("change", { detail: { value: text } })
  );
  await flushPromises();
}

describe("c-a-x-f-l-w-c-category-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("lists parents before their children and keeps an orphan at the top level", async () => {
    const element = await mount();
    expect($(element, ".list")).toBeNull();
    await open(element);
    expect(labels(element)).toEqual([
      "Moradia",
      "Energia",
      "Água",
      "Lazer",
      "Cinema",
      "Órfã"
    ]);
    const energy = element.shadowRoot.querySelector('li[data-id="e"]');
    expect(energy.className).toContain("depth-1");
  });

  it("filters by any level and keeps the parent of a match, dimmed", async () => {
    const element = await mount();
    await open(element);
    await search(element, "energ");
    expect(labels(element)).toEqual(["Moradia", "Energia"]);
    expect(
      element.shadowRoot.querySelector('li[data-id="m"]').className
    ).toContain("option_dim");
    await search(element, "morad");
    expect(labels(element)).toEqual(["Moradia", "Energia", "Água"]);
  });

  it("selects an option and shows its path when closed", async () => {
    const element = await mount();
    const changed = jest.fn();
    element.addEventListener("change", changed);
    await open(element);
    element.shadowRoot
      .querySelector('li[data-id="e"]')
      .dispatchEvent(new CustomEvent("mousedown", { cancelable: true }));
    await flushPromises();
    expect(changed.mock.calls[0][0].detail.value).toBe("e");
    element.value = "e";
    await flushPromises();
    expect($(element, ".category-search").value).toBe("Moradia › Energia");
  });

  it("offers a new category only when no category has that exact name", async () => {
    const element = await mount();
    await open(element);
    expect($(element, ".option_new")).toBeNull();
    await search(element, "Pet");
    expect($(element, ".option_new").textContent).toContain(
      '+ Nova categoria "Pet"'
    );
    await search(element, "lazer");
    expect($(element, ".option_new")).toBeNull();
  });

  it("asks to create the typed name", async () => {
    const element = await mount();
    const created = jest.fn();
    element.addEventListener("createcategory", created);
    await open(element);
    await search(element, "  Pet ");
    $(element, ".option_new").dispatchEvent(
      new CustomEvent("mousedown", { cancelable: true })
    );
    await flushPromises();
    expect(created).not.toHaveBeenCalled();
    const parents = $(element, ".new-parent").options;
    expect(parents.map((o) => o.label)).toEqual(
      expect.arrayContaining(["Nenhuma (nível raiz)"])
    );
    $(element, ".new-parent").dispatchEvent(
      new CustomEvent("change", { detail: { value: "e" } })
    );
    await flushPromises();
    $(element, ".confirm-create").dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    expect(created.mock.calls[0][0].detail).toEqual({
      name: "Pet",
      parentId: "e"
    });
  });

  it("sends no parent when the chosen value is not a listed category", async () => {
    const element = await mount();
    const created = jest.fn();
    element.addEventListener("createcategory", created);
    await open(element);
    await search(element, "Pet");
    $(element, ".option_new").dispatchEvent(
      new CustomEvent("mousedown", { cancelable: true })
    );
    await flushPromises();
    $(element, ".new-parent").dispatchEvent(
      new CustomEvent("change", { detail: { value: "Nenhuma (nível raiz)" } })
    );
    await flushPromises();
    $(element, ".confirm-create").dispatchEvent(new CustomEvent("click"));
    await flushPromises();
    expect(created.mock.calls[0][0].detail).toEqual({
      name: "Pet",
      parentId: null
    });
  });

  it("clears the selection and says when nothing matches", async () => {
    const element = await mount({ value: "e" });
    const changed = jest.fn();
    element.addEventListener("change", changed);
    await open(element);
    await search(element, "zzz");
    expect(labels(element)).toEqual([]);
    expect(element.shadowRoot.textContent).toContain(
      "Nenhuma categoria encontrada"
    );
    $(element, ".option_clear").dispatchEvent(
      new CustomEvent("mousedown", { cancelable: true })
    );
    await flushPromises();
    expect(changed.mock.calls[0][0].detail.value).toBeNull();
  });

  it("keeps the members of a cycle selectable at the top level", async () => {
    const element = await mount({
      options: [
        { id: "x", label: "X", parentId: "y" },
        { id: "y", label: "Y", parentId: "x" },
        { id: "z", label: "Z" }
      ]
    });
    await open(element);
    expect(labels(element)).toEqual(["Z", "X", "Y"]);
  });

  it("filters ignoring case and accents, and does not offer to create an accented duplicate", async () => {
    const element = await mount();
    await open(element);
    await search(element, "AGUA");
    expect(labels(element)).toEqual(["Moradia", "Água"]);
    expect($(element, ".option_new")).toBeNull();
    await search(element, "orfa");
    expect(labels(element)).toEqual(["Órfã"]);
  });

  it("limits the typed name to 80 characters", async () => {
    const element = await mount();
    expect($(element, ".category-search").maxLength).toBe(80);
    await open(element);
    await search(element, "a".repeat(100));
    expect($(element, ".option_new").textContent).toContain("a".repeat(80));
    expect($(element, ".option_new").textContent).not.toContain("a".repeat(81));
  });

  it("works with the keyboard: arrows move, Enter picks, Escape closes", async () => {
    const element = await mount();
    const changed = jest.fn();
    element.addEventListener("change", changed);
    await open(element);
    const key = async (name) => {
      $(element, ".category-search").dispatchEvent(
        new KeyboardEvent("keydown", { key: name, cancelable: true })
      );
      await flushPromises();
    };
    await key("ArrowDown");
    await key("ArrowDown");
    const active = () =>
      Array.from(element.shadowRoot.querySelectorAll(".option_active")).map(
        (li) => li.textContent.trim()
      );
    expect(active()).toEqual(["Energia"]);
    await key("ArrowUp");
    expect(active()).toEqual(["Moradia"]);
    await key("ArrowDown");
    await key("Enter");
    expect(changed.mock.calls[0][0].detail.value).toBe("e");
    expect($(element, ".list")).toBeNull();
    await open(element);
    await key("Escape");
    expect($(element, ".list")).toBeNull();
  });

  it("reaches the create and clear rows by keyboard", async () => {
    const element = await mount({ value: "e" });
    const created = jest.fn();
    const changed = jest.fn();
    element.addEventListener("createcategory", created);
    element.addEventListener("change", changed);
    await open(element);
    await search(element, "Pet");
    const key = async (name) => {
      $(element, ".category-search").dispatchEvent(
        new KeyboardEvent("keydown", { key: name, cancelable: true })
      );
      await flushPromises();
    };
    await key("ArrowDown");
    expect($(element, ".option_new").className).toContain("option_active");
    await key("ArrowDown");
    expect($(element, ".option_clear").className).toContain("option_active");
    await key("ArrowUp");
    await key("Enter");
    expect(created).not.toHaveBeenCalled();
    expect($(element, ".new-parent")).not.toBeNull();
    expect(changed).not.toHaveBeenCalled();
  });

  it("keeps the chosen path as the hint while typing", async () => {
    const element = await mount({ value: "e" });
    await open(element);
    expect($(element, ".category-search").placeholder).toBe(
      "Moradia › Energia"
    );
  });
});
