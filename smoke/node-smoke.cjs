const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent("<title>runtime smoke</title><main>ok</main>");
    if ((await page.title()) !== "runtime smoke") {
      throw new Error("Chromium did not render the smoke page");
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

