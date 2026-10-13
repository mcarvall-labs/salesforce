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
    expect(created.mock.calls[0][0].detail.name).toBe("Pet");
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

  it("does not loop on a cycle in the data", async () => {
    const element = await mount({
      options: [
        { id: "x", label: "X", parentId: "y" },
        { id: "y", label: "Y", parentId: "x" },
        { id: "z", label: "Z" }
      ]
    });
    await open(element);
    expect(labels(element)).toEqual(["Z"]);
  });
});
