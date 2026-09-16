"""Real-data browser regression. Start via with_server.py; all external requests are denied."""
import csv
import json
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright

BASE_URL = "http://127.0.0.1:3939"
ARTIFACTS = Path("outputs/test-artifacts")
ARTIFACTS.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path="/usr/bin/google-chrome",
                               args=["--no-sandbox", "--disable-dev-shm-usage"])
    context = browser.new_context(viewport={"width": 1440, "height": 1100}, accept_downloads=True)
    external, errors = [], []
    def deny_external(route):
        if urlsplit(route.request.url).hostname not in ("127.0.0.1", "localhost"):
            external.append(route.request.url)
            route.abort()
        else:
            route.continue_()
    context.route("**/*", deny_external)
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
    page.goto(BASE_URL, wait_until="networkidle")
    page.wait_for_selector("#proximity_map .leaflet-interactive", timeout=90000)
    assert "Base oficial local" in page.locator("#data_notice").inner_text()
    assert page.locator("#cep").input_value() == "05586-001"
    assert page.locator("#proximity_map path.leaflet-interactive").count() > 100
    page.screenshot(path=str(ARTIFACTS / "real-initial.png"), full_page=True)
    # Wait for rendered records, not only the status message or network-idle.
    page.locator("#run_query").click()
    page.wait_for_function("""() => document.querySelector('#proximity_table').innerText.includes('Iquiririm')
        && document.querySelector('#query_kpis').innerText.includes('equipamentos')""", timeout=120000)
    page.wait_for_selector("#proximity_map .legend", timeout=60000)
    page.screenshot(path=str(ARTIFACTS / "real-cep.png"), full_page=True)
    single_status = page.locator("#query_status").inner_text()
    assert "-23.571872" in single_status and "-46.730196" in single_status
    assert page.locator("#proximity_map path.leaflet-interactive").count() > 20
    with page.expect_download() as pending:
        page.locator("#download_results").click()
    downloaded = ARTIFACTS / "real-cep-results.csv"
    pending.value.save_as(downloaded)
    rows = list(csv.DictReader(downloaded.open(encoding="utf-8")))
    assert len(rows) > 20
    assert all(r["origin_cep"] == "05586001" for r in rows)
    assert len({r["metric_id"] for r in rows}) >= 5
    with page.expect_download(timeout=120000) as pending:
        page.locator("#download_report").click()
    pending.value.save_as(ARTIFACTS / "real-cep-report.html")

    page.get_by_role("tab", name="Estatísticas", exact=True).click()
    page.wait_for_selector("#distance_plot img", timeout=60000)
    page.wait_for_function("document.querySelector('#summary_table').innerText.includes('consulta-1')", timeout=60000)
    page.screenshot(path=str(ARTIFACTS / "real-statistics.png"), full_page=True)

    page.get_by_role("tab", name="Banco offline", exact=True).click()
    page.wait_for_function("document.querySelector('#inventory_table').innerText.includes('csv')", timeout=60000)
    assert "05586001" in page.locator("#cep_table").inner_text()
    page.screenshot(path=str(ARTIFACTS / "real-offline-inventory.png"), full_page=True)

    # A CEP absent locally must show an actionable error and clear stale results.
    page.get_by_role("tab", name="Explorar", exact=True).click()
    page.locator("#cep").fill("99999-999")
    page.locator("#run_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('índice local')", timeout=60000)
    assert "Iquiririm" not in page.locator("#proximity_table").inner_text()

    # Coordinates must work without any geocoder.
    page.locator("input[name='origin_method'][value='coordinates']").check()
    page.locator("#latitude").fill("-23.55008")
    page.locator("#longitude").fill("-46.63408")
    page.locator("#run_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('Coordenadas fornecidas')", timeout=90000)
    page.wait_for_function("document.querySelector('#proximity_table tbody').innerText.includes('consulta-1')", timeout=60000)

    page.get_by_role("tab", name="Lotes", exact=True).click()
    page.locator("#batch_file").set_input_files("inst/examples/origens-reais.csv")
    page.wait_for_function("document.querySelector('#batch_file_progress').innerText.includes('Upload complete')", timeout=30000)
    page.locator("#submit_batch").click()
    page.wait_for_function("document.querySelector('#batch_message').innerText.includes('Lote concluído')", timeout=180000)
    batch_status = page.locator("#batch_message").inner_text()
    assert "2 origens válidas; 1 com erro" in batch_status
    page.wait_for_function("document.querySelector('#batch_errors').innerText.includes('cep-a-preparar')", timeout=60000)
    with page.expect_download() as pending:
        page.locator("#download_batch").click()
    pending.value.save_as(ARTIFACTS / "real-batch.zip")
    page.get_by_role("tab", name="Explorar", exact=True).click()
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('teste-iquiririm')", timeout=60000)
    page.screenshot(path=str(ARTIFACTS / "real-batch-map.png"), full_page=True)
    assert not page.locator(".shiny-output-error").count()
    evidence = {"single_status": single_status, "batch_status": batch_status,
                "download_rows": len(rows), "external_requests": external, "browser_errors": errors}
    (ARTIFACTS / "browser-evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    assert not external, f"Application attempted external requests: {external}"
    assert not errors, f"Browser errors: {errors}"
    context.close()
    browser.close()
    print(json.dumps(evidence, ensure_ascii=False, indent=2))
