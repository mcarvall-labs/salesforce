import { createElement } from "lwc";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import AXF_LWC_bankInstitutionPicker from "c/aXF_LWC_bankInstitutionPicker";

const VALUES = {
  values: [
    { value: "001", label: "001 - Banco do Brasil" },
    { value: "077", label: "077 - Banco Inter" },
    { value: "301", label: "301 - Contabilizei Bank" },
    { value: "323", label: "323 - Mercado Pago" },
    { value: "336", label: "336 - C6 Bank" },
    { value: "341", label: "341 - Itaú Unibanco" },
    { value: "756", label: "756 - Sicoob" }
  ]
};

const flush = () => Promise.resolve();

const optionValues = (element) =>
  Array.from(element.shadowRoot.querySelectorAll('[role="option"]')).map(
    (o) => o.dataset.value
  );

async function setup() {
  const element = createElement("c-a-x-f-l-w-c-bank-institution-picker", {
    is: AXF_LWC_bankInstitutionPicker
  });
  document.body.appendChild(element);
  getObjectInfo.emit({ defaultRecordTypeId: "012000000000000AAA" });
  getPicklistValues.emit(VALUES);
  await flush();
  return element;
}

async function search(element, term) {
  const input = element.shadowRoot.querySelector("lightning-input");
  input.value = term;
  input.dispatchEvent(new CustomEvent("change"));
  await flush();
}

describe("c-a-x-f-l-w-c-bank-institution-picker", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the six priority banks first", async () => {
    const element = await setup();
    expect(optionValues(element)).toEqual([
      "756",
      "301",
      "341",
      "077",
      "323",
      "336"
    ]);
  });

  it("filters by code or accent-insensitive name", async () => {
    const element = await setup();
    await search(element, "itau");
    expect(optionValues(element)).toEqual(["341"]);
    await search(element, "001");
    expect(optionValues(element)).toEqual(["001"]);
  });

  it("dispatches change with the COMPE code on selection", async () => {
    const element = await setup();
    const handler = jest.fn();
    element.addEventListener("change", handler);
    element.shadowRoot.querySelector('[data-value="341"]').click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ value: "341" });
  });

  it("selects with Enter and Space from the keyboard", async () => {
    const element = await setup();
    const handler = jest.fn();
    element.addEventListener("change", handler);
    const option = element.shadowRoot.querySelector('[data-value="341"]');
    option.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    option.dispatchEvent(new KeyboardEvent("keydown", { key: " " }));
    option.dispatchEvent(new KeyboardEvent("keydown", { key: "a" }));
    expect(handler).toHaveBeenCalledTimes(2);
    expect(handler.mock.calls[0][0].detail).toEqual({ value: "341" });
  });

  it("shows the pill after a selection and clears it", async () => {
    const element = await setup();
    const handler = jest.fn();
    element.addEventListener("change", handler);
    element.value = "341";
    await flush();
    const pill = element.shadowRoot.querySelector("lightning-pill");
    expect(pill.label).toBe("341 - Itaú Unibanco");
    pill.dispatchEvent(new CustomEvent("remove"));
    await flush();
    expect(handler.mock.calls[0][0].detail).toEqual({ value: undefined });
    expect(element.shadowRoot.querySelector("lightning-pill")).toBeNull();
  });

  it("says when no institution matches the search", async () => {
    const element = await setup();
    await search(element, "zzzz");
    expect(optionValues(element)).toEqual([]);
    expect(element.shadowRoot.textContent).toContain(
      "Nenhuma instituição encontrada."
    );
  });

  it("shows an error when the institutions cannot be loaded", async () => {
    const element = createElement("c-a-x-f-l-w-c-bank-institution-picker", {
      is: AXF_LWC_bankInstitutionPicker
    });
    document.body.appendChild(element);
    getObjectInfo.emit({ defaultRecordTypeId: "012000000000000AAA" });
    getPicklistValues.error();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Não foi possível carregar as instituições.");
  });

  it("reports the required validation to the parent", async () => {
    const element = await setup();
    element.required = true;
    expect(element.checkValidity()).toBe(false);
    expect(element.reportValidity()).toBe(false);
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Escolha uma instituição.");
    element.shadowRoot.querySelector('[data-value="341"]').click();
    await flush();
    expect(element.checkValidity()).toBe(true);
    expect(element.reportValidity()).toBe(true);
  });
});
