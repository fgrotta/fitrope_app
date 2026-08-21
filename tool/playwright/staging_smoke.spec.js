const { test, expect } = require("@playwright/test");

const pageUrl = process.env.PAGE_URL;

test("artefatto Flutter staging pubblicato", async ({ page, request }) => {
  expect(pageUrl, "PAGE_URL mancante").toBeTruthy();

  const baseUrl = pageUrl.endsWith("/") ? pageUrl : `${pageUrl}/`;
  for (const path of ["", "version.json", "flutter_bootstrap.js"]) {
    const response = await request.get(new URL(path, baseUrl).toString());
    expect(response.ok(), `GET ${path || "index.html"}`).toBeTruthy();
  }

  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  await page.locator("flt-glass-pane").waitFor({ timeout: 60_000 });

  const semanticsPlaceholder = page.locator("flt-semantics-placeholder");
  if (await semanticsPlaceholder.count()) await semanticsPlaceholder.click();
  await expect(page.getByLabel("Ambiente STAGING")).toBeVisible({
    timeout: 30_000,
  });
  expect(errors).toEqual([]);
});
