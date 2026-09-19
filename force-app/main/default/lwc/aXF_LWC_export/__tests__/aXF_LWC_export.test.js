import { createElement } from "lwc";
import AxfExport from "c/aXF_LWC_export";
import getContext from "@salesforce/apex/AXF_CLS_CTRL_Export.getContext";
import requestExport from "@salesforce/apex/AXF_CLS_CTRL_Export.request";
import readExport from "@salesforce/apex/AXF_CLS_CTRL_Export.read";
import downloadExport from "@salesforce/apex/AXF_CLS_CTRL_Export.download";
import statusRUNNING from "@salesforce/label/c.AXF_Export_statusRUNNING";
import statusPARTIAL from "@salesforce/label/c.AXF_Export_statusPARTIAL";

jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Export.getContext",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Export.request",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Export.read",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AXF_CLS_CTRL_Export.download",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 8; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

const context = { canExport: true };

const preparedRun = {
  runId: "a0E1",
  name: "EPR-000001",
  status: "PREPARED",
  fileName: "axon-export-EPR-000001.csv",
  contentHash: "abc123",
  version: 1,
  canDownload: true,
  nextAction: "DOWNLOAD"
};

function mount() {
  const element = createElement("c-a-x-f-_-l-w-c-_export", { is: AxfExport });
  element.recordId = "001000000000001AAA";
  document.body.appendChild(element);
  return element;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-aXF_LWC_export", () => {
  it("shows the no-capability message when the user cannot export", async () => {
    const element = mount();
    getContext.emit({ canExport: false });
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="noCapability"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="request"]')).toBeNull();
  });

  it("requests an export and shows the prepared status with a download button", async () => {
    requestExport.mockResolvedValue(preparedRun);
    const element = mount();
    getContext.emit(context);
    await flush();

    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    expect(requestExport).toHaveBeenCalledWith({
      accountId: "001000000000001AAA",
      expectedVersion: null
    });
    expect(
      element.shadowRoot.querySelector('[data-id="statusText"]').textContent
    ).toBeTruthy();
    expect(
      element.shadowRoot.querySelector('[data-id="download"]')
    ).not.toBeNull();
  });

  it("shows a sanitized error when the request fails", async () => {
    requestExport.mockRejectedValue({ body: { message: "FORBIDDEN" } });
    const element = mount();
    getContext.emit(context);
    await flush();

    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
  });

  it("downloads the artifact and refreshes the run after a ready download", async () => {
    requestExport.mockResolvedValue(preparedRun);
    downloadExport.mockResolvedValue({
      ready: true,
      outcome: "READY",
      fileName: "axon-export-EPR-000001.csv",
      mimeType: "text/csv",
      bodyBase64: btoa("date,direction\n2026-06-01,DEBIT")
    });
    readExport.mockResolvedValue({
      ...preparedRun,
      status: "DOWNLOADED",
      nextAction: "DOWNLOAD"
    });
    const createObjectURL = jest.fn(() => "blob:mock");
    const revokeObjectURL = jest.fn();
    global.URL.createObjectURL = createObjectURL;
    global.URL.revokeObjectURL = revokeObjectURL;

    const element = mount();
    getContext.emit(context);
    await flush();
    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    element.shadowRoot.querySelector('[data-id="download"]').click();
    await flush();

    expect(downloadExport).toHaveBeenCalledWith({
      runId: "a0E1",
      expectedVersion: 1
    });
    expect(createObjectURL).toHaveBeenCalled();
    expect(readExport).toHaveBeenCalledWith({ runId: "a0E1" });
  });

  it("shows a sanitized message when the download is refused instead of ready", async () => {
    requestExport.mockResolvedValue(preparedRun);
    downloadExport.mockResolvedValue({ ready: false, outcome: "EXPIRED" });
    readExport.mockResolvedValue({
      ...preparedRun,
      status: "REVOKED",
      canDownload: false,
      nextAction: "REQUEST_AGAIN"
    });

    const element = mount();
    getContext.emit(context);
    await flush();
    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    element.shadowRoot.querySelector('[data-id="download"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="download"]')).toBeNull();
  });

  it("shows the localized RUNNING label and no download button while a batch is processing", async () => {
    requestExport.mockResolvedValue({
      ...preparedRun,
      status: "RUNNING",
      canDownload: false,
      nextAction: "PROCESSING"
    });
    const element = mount();
    getContext.emit(context);
    await flush();

    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="statusText"]').textContent
    ).toBe(statusRUNNING);
    expect(
      element.shadowRoot.querySelector('[data-id="statusText"]').textContent
    ).not.toBe("RUNNING");
    expect(element.shadowRoot.querySelector('[data-id="download"]')).toBeNull();
  });

  it("shows the localized PARTIAL label and no download button while a chunk failure is resumable", async () => {
    requestExport.mockResolvedValue({
      ...preparedRun,
      status: "PARTIAL",
      canDownload: false,
      nextAction: "PROCESSING"
    });
    const element = mount();
    getContext.emit(context);
    await flush();

    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector('[data-id="statusText"]').textContent
    ).toBe(statusPARTIAL);
    expect(
      element.shadowRoot.querySelector('[data-id="statusText"]').textContent
    ).not.toBe("PARTIAL");
    expect(element.shadowRoot.querySelector('[data-id="download"]')).toBeNull();
  });

  it("refreshes the run via read() without re-requesting", async () => {
    requestExport.mockResolvedValue(preparedRun);
    readExport.mockResolvedValue({ ...preparedRun, status: "DOWNLOADED" });

    const element = mount();
    getContext.emit(context);
    await flush();
    element.shadowRoot.querySelector('[data-id="request"]').click();
    await flush();

    element.shadowRoot.querySelector('[data-id="refresh"]').click();
    await flush();

    expect(readExport).toHaveBeenCalledWith({ runId: "a0E1" });
    expect(requestExport).toHaveBeenCalledTimes(1);
  });
});
