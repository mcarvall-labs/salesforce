const fs = require("fs");
const path = require("path");

const bundleDirectory = path.resolve(__dirname, "..");
const css = fs.readFileSync(
  path.join(bundleDirectory, "aXF_LWC_quickFlowActions.css"),
  "utf8"
);
const template = fs.readFileSync(
  path.join(bundleDirectory, "aXF_LWC_quickFlowActions.html"),
  "utf8"
);

const controller = fs.readFileSync(
  path.join(bundleDirectory, "aXF_LWC_quickFlowActions.js"),
  "utf8"
);

describe("aXF_LWC_quickFlowActions responsive layout", () => {
  it("uses bounded grid tracks and border-box button sizing", () => {
    expect(template).toContain('class="quick-actions-grid"');
    expect(css).toMatch(
      /grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)/
    );
    expect(css).toMatch(/\.btn-full-width\s*{[^}]*box-sizing:\s*border-box/s);
    expect(css).toMatch(/\.btn-full-width\s*{[^}]*min-width:\s*0/s);
  });

  it("stacks the actions when the available region becomes narrow", () => {
    expect(css).toMatch(/@media\s*\(max-width:\s*30rem\)/);
    expect(css).toMatch(
      /@media\s*\(max-width:\s*30rem\)[\s\S]*grid-template-columns:\s*minmax\(0,\s*1fr\)/
    );
  });

  it("preserves both button actions", () => {
    expect(template).toContain("onclick={handleOpenExpenseModal}");
    expect(template).toContain("onclick={handleOpenRevenueModal}");
  });

  it("formats monetary input from cents while the user types", () => {
    expect(template).toMatch(
      /name="amount"[\s\S]*value={amountDisplay}[\s\S]*oninput={handleCurrencyInput}/
    );
    expect(template).toMatch(
      /name="paidValue"[\s\S]*value={paidValueDisplay}[\s\S]*oninput={handleCurrencyInput}/
    );
    expect(controller).toContain('new Intl.NumberFormat("pt-BR"');
    expect(controller).toMatch(/Number\(digits\) \/ 100/);
  });
});
