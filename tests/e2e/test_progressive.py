"""Slow real-data regression: progressive routes, responsiveness, cancel, queue and batch.

Run through with_server.py. No remote browser requests are allowed.
SAMPA_TEST_STAGE=single (default), batch or cancel runs bounded stages separately.
"""
import csv
import io
import json
import os
import time
import zipfile
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright

BASE_URL = os.environ.get("SAMPA_TEST_URL", "http://127.0.0.1:3940")
ARTIFACTS = Path(os.environ.get("SAMPA_TEST_ARTIFACTS", "outputs/test-artifacts/async-network"))
ARTIFACTS.mkdir(parents=True, exist_ok=True)
STAGE = os.environ.get("SAMPA_TEST_STAGE", "single")
if STAGE not in ("single", "batch", "cancel"):
    raise ValueError("SAMPA_TEST_STAGE must be single, batch or cancel")


def choose(page, element, value):
    page.locator(f"#{element}").locator("..").locator(".selectize-input").click()
    page.locator(f".selectize-dropdown [data-value='{value}']").click()


def download_csv(page, name):
    with page.expect_download() as pending:
        page.locator("#download_results").click()
    path = ARTIFACTS / name
    pending.value.save_as(path)
    return list(csv.DictReader(path.open(encoding="utf-8")))


def test_batch(page):
    page.locator("input[name='query_modes'][value='motorcar']").check()
    page.get_by_role("tab", name="Lotes", exact=True).click()
    page.locator("#batch_file").set_input_files("inst/examples/origens-reais.csv")
    page.wait_for_function("document.querySelector('#batch_file_progress').innerText.includes('Upload complete')", timeout=30000)
    started = time.monotonic()
    page.locator("#submit_batch").click()
    page.wait_for_function("document.querySelector('#batch_message').innerText.includes('2/4 unidades')", timeout=60000)
    partial_seconds = time.monotonic() - started
    page.wait_for_function("document.querySelector('#batch_errors').innerText.includes('cep-a-preparar')", timeout=15000)
    page.get_by_role("tab", name="Explorar", exact=True).click()
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('teste-iquiririm')", timeout=15000)
    page.wait_for_function("HTMLWidgets.find('#proximity_map').getMap().getZoom() >= 11", timeout=15000)
    page.screenshot(path=str(ARTIFACTS / "batch-partial-map.png"), full_page=True)
    page.get_by_role("tab", name="Lotes", exact=True).click()
    page.wait_for_function("document.querySelector('#batch_message').innerText.includes('Lote concluído')", timeout=1200000)
    elapsed = time.monotonic() - started
    assert "2 origens válidas; 1 com erro" in page.locator("#batch_message").inner_text()
    with page.expect_download(timeout=60000) as pending:
        page.locator("#download_batch").click()
    bundle = ARTIFACTS / "network-batch.zip"
    pending.value.save_as(bundle)
    with zipfile.ZipFile(bundle) as z:
        manifest = json.loads(z.read("manifest.json"))
        assert manifest["complete"] and manifest["completed_units"] == 4
        assert manifest["valid_rows"] == 2 and manifest["error_rows"] == 1
        rows = list(csv.DictReader(io.StringIO(z.read("results.csv").decode("utf-8"))))
        for origin in {r["origin_id"] for r in rows}:
            assert len({r["metric_id"] for r in rows if r["origin_id"] == origin}) == 7
        assert not any("request" in name or "worker" in name for name in z.namelist())
    return {"batch_geometry_seconds": partial_seconds, "batch_total_seconds": elapsed}


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
    page.goto(BASE_URL, wait_until="networkidle")
    page.wait_for_selector("#proximity_map .leaflet-interactive", timeout=120000)
    page.locator("#query_radius").fill("1000")

    def finish(evidence):
        assert not external and not errors, (external, errors)
        assert not page.locator(".shiny-output-error").count()
        evidence.update(passed=True, stage=STAGE, external_requests=external, browser_errors=errors)
        (ARTIFACTS / f"{STAGE}-evidence.json").write_text(
            json.dumps(evidence, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps(evidence, indent=2, ensure_ascii=False), flush=True)
        context.close()
        browser.close()
        raise SystemExit(0)

    if STAGE == "batch":
        finish(test_batch(page))
    page.locator("input[name='query_modes'][value='foot']").check()
    started = time.monotonic()
    page.locator("#run_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('1/2 unidades')", timeout=60000)
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('Iquiririm')", timeout=30000)
    partial_seconds = time.monotonic() - started
    assert page.locator("#run_query").is_disabled()
    assert page.locator("#download_results").get_attribute("aria-disabled") == "true"
    choose(page, "map_metric", "geodesic_haversine")
    page.get_by_role("tab", name="Estatísticas", exact=True).click()
    page.wait_for_function("document.querySelector('#summary_table').innerText.includes('consulta-1')", timeout=15000)
    page.wait_for_selector("#distance_plot img", timeout=15000)
    page.screenshot(path=str(ARTIFACTS / "partial-statistics.png"), full_page=True)
    page.get_by_role("tab", name="Explorar", exact=True).click()
    page.wait_for_function("HTMLWidgets.find('#proximity_map').getMap().getZoom() >= 13", timeout=15000)
    # Prove an input can still reach R and change the rendered metric mid-route.
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('consulta-1')", timeout=15000)
    page.screenshot(path=str(ARTIFACTS / "partial-map.png"), full_page=True)
    cancelled = time.monotonic()
    page.locator("#cancel_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('Consulta cancelada')", timeout=10000)
    cancel_seconds = time.monotonic() - cancelled
    rows = download_csv(page, "cancelled.csv")
    assert {r["analysis_status"] for r in rows} == {"cancelled"}
    assert len({r["metric_id"] for r in rows}) == 5
    with page.expect_download(timeout=120000) as pending:
        page.locator("#download_report").click()
    report = ARTIFACTS / "cancelled.html"
    pending.value.save_as(report)
    assert "RESULTADOS PARCIAIS" in report.read_text(encoding="utf-8")
    print(json.dumps({"geometry_seconds": partial_seconds, "cancel_seconds": cancel_seconds}), flush=True)
    if STAGE == "cancel":
        finish({"geometry_seconds": partial_seconds, "cancel_seconds": cancel_seconds})

    # Complete all three real networks, both directions, keeping the original CEP
    # even if an input is changed while the worker is using its request snapshot.
    for mode in ("bicycle", "motorcar"):
        page.locator(f"input[name='query_modes'][value='{mode}']").check()
    choose(page, "query_direction", "both")
    started = time.monotonic()
    page.locator("#run_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('1/4 unidades')", timeout=60000)
    page.locator("#cep").fill("99999-999")
    choose(page, "map_metric", "geodesic_haversine")

    # A separate session waits in the local FIFO instead of doubling graph RAM.
    other = context.new_page()
    other.goto(BASE_URL, wait_until="networkidle")
    other.wait_for_selector("#proximity_map .leaflet-interactive", timeout=60000)
    other.locator("#run_query").click()
    other.wait_for_function("document.querySelector('#query_status').innerText.includes('Na fila local')", timeout=15000)
    other.locator("#cancel_query").click()
    other.wait_for_function("document.querySelector('#query_status').innerText.includes('Consulta cancelada')", timeout=10000)
    other.close()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('Consulta concluída')", timeout=1800000)
    full_seconds = time.monotonic() - started
    assert page.locator("#map_metric").input_value() == "geodesic_haversine"
    rows = download_csv(page, "all-networks.csv")
    assert {r["origin_cep"] for r in rows} == {"05586001"}
    assert {r["analysis_status"] for r in rows} == {"completed"}
    metrics = sorted({r["metric_id"] for r in rows})
    assert len(metrics) == 11, metrics
    network = [r for r in rows if r["distance_family"] == "network"]
    assert {r["direction"] for r in network} == {"origin_to_equipment", "equipment_to_origin"}
    assert {r["path_objective"] for r in network} == {"shortest", "fastest"}
    assert all(r["routing_status"] in ("ok", "snap_warning") for r in network)
    choose(page, "map_metric", "network_foot_shortest")
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('208.6')", timeout=30000)
    page.screenshot(path=str(ARTIFACTS / "complete-map.png"), full_page=True)
    page.get_by_role("tab", name="Estatísticas", exact=True).click()
    page.wait_for_function("document.querySelector('#routing_table').innerText.includes('network_foot')", timeout=30000)
    assert not page.locator(".shiny-output-error").count()
    print(json.dumps({"all_modes_both_directions_seconds": full_seconds, "metrics": metrics}), flush=True)

    finish({"geometry_seconds": partial_seconds, "cancel_seconds": cancel_seconds,
            "all_modes_both_directions_seconds": full_seconds, "metrics": metrics})
