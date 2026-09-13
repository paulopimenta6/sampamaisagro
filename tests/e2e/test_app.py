from pathlib import Path
from playwright.sync_api import sync_playwright


BASE_URL = "http://127.0.0.1:3939"
ARTIFACTS = Path("outputs/test-artifacts")
ARTIFACTS.mkdir(parents=True, exist_ok=True)

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(
        headless=True,
        executable_path="/usr/bin/google-chrome",
        args=["--no-sandbox", "--disable-dev-shm-usage"],
    )
    page = browser.new_page(viewport={"width": 1440, "height": 1000})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
    page.on("response", lambda response: errors.append(f"HTTP {response.status}: {response.url}") if response.status >= 400 else None)
    page.goto(BASE_URL, wait_until="networkidle")
    page.screenshot(path=str(ARTIFACTS / "app-initial.png"), full_page=True)

    assert page.locator("text=Sampa+Rural | proximidade").count() > 0
    assert page.locator("#latitude").is_visible()
    page.locator("#latitude").fill("-23.5505")
    page.locator("#longitude").fill("-46.6333")
    page.locator("#query_k").fill("5")
    page.locator("#query_radius").fill("15000")
    page.locator("#run_query").click()
    page.wait_for_function("document.body.innerText.includes('Consulta concluida')", timeout=30000)
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(ARTIFACTS / "app-query.png"), full_page=True)

    body = page.locator("body").inner_text()
    assert "Geodesica elipsoidal (Karney)" in body
    assert "Dados sinteticos para demonstracao" not in body
    assert "Falha:" not in body
    assert not errors, f"Browser errors: {errors}"
    browser.close()
