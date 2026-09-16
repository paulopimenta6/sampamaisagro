"""Optional slow browser regression using the complete local walking graph."""
import csv
import json
import time
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright

artifacts = Path("outputs/test-artifacts")
artifacts.mkdir(parents=True, exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, executable_path="/usr/bin/google-chrome",
                               args=["--no-sandbox", "--disable-dev-shm-usage"])
    context = browser.new_context(viewport={"width": 1440, "height": 1100}, accept_downloads=True)
    external, errors = [], []

    def intercept(route):
        if urlsplit(route.request.url).hostname not in ("localhost", "127.0.0.1"):
            external.append(route.request.url)
            route.abort()
        else:
            route.continue_()

    context.route("**/*", intercept)
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto("http://127.0.0.1:3939", wait_until="networkidle")
    page.wait_for_selector("#proximity_map .leaflet-interactive", timeout=120000)
    page.locator("#query_radius").fill("1000")
    page.locator("input[name='query_modes'][value='foot']").check()
    started = time.monotonic()
    page.locator("#run_query").click()
    page.wait_for_function("document.querySelector('#query_status').innerText.includes('Consulta concluída')",
                           timeout=600000)
    elapsed = time.monotonic() - started
    # Shiny wraps this hidden select in a visible Selectize control.
    page.locator("#map_metric").locator("..").locator(".selectize-input").click()
    page.locator(".selectize-dropdown [data-value='network_foot_shortest']").click()
    page.wait_for_function("document.querySelector('#proximity_table').innerText.includes('208.6')",
                           timeout=60000)
    page.screenshot(path=str(artifacts / "real-walking.png"), full_page=True)
    with page.expect_download() as download:
        page.locator("#download_results").click()
    path = artifacts / "real-walking.csv"
    download.value.save_as(path)
    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    metrics = sorted({row["metric_id"] for row in rows})
    assert len(metrics) == 7
    network = [row for row in rows if row["distance_family"] == "network"]
    assert {row["path_objective"] for row in network} == {"shortest", "fastest"}
    assert len(network) >= 20
    assert all(row["routing_status"] in ("ok", "snap_warning") for row in network)
    page.get_by_role("tab", name="Estatísticas", exact=True).click()
    page.wait_for_function("document.querySelector('#routing_table').innerText.includes('network_foot')",
                           timeout=60000)
    assert not page.locator(".shiny-output-error").count()
    assert not external and not errors
    evidence = {"passed": True, "query_seconds_including_graph_load": elapsed,
                "metrics": metrics, "network_selected_pairs": len(network),
                "external_requests": external, "browser_errors": errors}
    (artifacts / "walking-browser-evidence.json").write_text(
        json.dumps(evidence, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(evidence, indent=2, ensure_ascii=False))
    context.close()
    browser.close()
