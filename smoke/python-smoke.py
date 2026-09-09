import asyncio

from playwright.async_api import async_playwright


async def main() -> None:
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=False)
        try:
            page = await browser.new_page()
            await page.set_content("<title>runtime smoke</title><main>ok</main>")
            assert await page.title() == "runtime smoke"
        finally:
            await browser.close()


asyncio.run(main())

