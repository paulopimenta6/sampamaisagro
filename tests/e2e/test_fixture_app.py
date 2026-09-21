"""Manual CI smoke: installed package, synthetic data, no external browser requests."""
import csv
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from urllib.parse import urlsplit
from urllib.request import urlopen
import zipfile

from playwright.sync_api import sync_playwright


def main():
    root = Path(__file__).resolve().parents[2]
    path = os.environ.get("SAMPA_TEST_ARTIFACTS")
    artifacts = Path(path) if path else Path(tempfile.mkdtemp(prefix="sampa-browser-evidence-"))
    if artifacts.exists() and any(artifacts.iterdir()):
        raise RuntimeError("Use a new artifact directory; historical evidence is preserved")
    artifacts.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, R_PROFILE_USER="/dev/null", RENV_CONFIG_AUTOLOADER_ENABLED="FALSE")
    port = env.get("SAMPA_FIXTURE_PORT", "3955")
    url = f"http://127.0.0.1:{port}"
    server_log = (artifacts / "server.log").open("w")
    server = subprocess.Popen(["Rscript", "tests/e2e/run_fixture_app.R"], cwd=root,
                              env=env, stdout=server_log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        deadline = time.monotonic() + 60
        while True:
            if server.poll() is not None:
                raise RuntimeError("Fixture server failed; see server.log")
            try:
                with urlopen(url, timeout=1):
                    break
            except OSError:
                if time.monotonic() > deadline:
                    raise TimeoutError("Fixture server startup exceeded 60 seconds")
                time.sleep(0.1)
        with sync_playwright() as p:
            kwargs = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage",
                "--disable-background-networking", "--disable-component-update", "--no-first-run"]}
            if env.get("PLAYWRIGHT_CHROMIUM_EXECUTABLE"):
                kwargs["executable_path"] = env["PLAYWRIGHT_CHROMIUM_EXECUTABLE"]
            browser = p.chromium.launch(**kwargs)
            context = browser.new_context(accept_downloads=True, service_workers="block",
                                          viewport={"width": 1280, "height": 1000})
            external, errors = [], []

            def deny_external(route):
                if urlsplit(route.request.url).hostname not in ("localhost", "127.0.0.1"):
                    external.append(route.request.url)
                    route.abort()
                else:
                    route.continue_()

            context.route("**/*", deny_external)
            page = context.new_page()
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
            page.goto(url)
            page.wait_for_selector("#proximity_map .leaflet-interactive", timeout=60000)

            def run_query():
                page.locator("#run_query").click()
                page.wait_for_function("document.querySelector('#run_query').disabled === true", timeout=10000)
                page.wait_for_function("document.querySelector('#query_status').innerText.includes('Consulta concluída')",
                                       timeout=60000)
                page.wait_for_function("document.querySelector('#run_query').disabled === false", timeout=10000)

            def download(element, filename):
                with page.expect_download(timeout=60000) as pending:
                    page.locator(f"#{element}").click()
                target = artifacts / filename
                pending.value.save_as(target)
                return target

            page.locator("input[name='origin_method'][value='coordinates']").check()
            page.locator("#latitude").fill("-23.612345")
            page.locator("#longitude").fill("-46.712345")
            run_query()
            rows = list(csv.DictReader(download("download_results", "coordinates.csv").open()))
            assert len({row["metric_id"] for row in rows}) == 5
            assert len({row["equipment_id"] for row in rows}) == 2
            html = download("download_report", "quality.html").read_text(encoding="utf-8")
            assert "Inventário filtrado da consulta" in html and "quality-by-category" in html
            report_page = context.new_page()
            # Parse the actual downloaded HTML in the browser; no file:// or remote assets.
            report_page.set_content(html, wait_until="domcontentloaded")
            cells = report_page.locator("#quality-by-category tbody tr").first.locator("td").all_text_contents()
            assert [float(value.strip()) for value in cells[1:4]] == [4, 2, 50]
            report_page.close()

            page.locator("input[name='origin_method'][value='cep']").check()
            page.locator("#cep").fill("00000-042")
            run_query()
            rows = list(csv.DictReader(download("download_results", "cep.csv").open()))
            assert all(row["origin_cep"] == "00000042" for row in rows)
            assert all(row["geocode_source"] == "Synthetic fixture only" for row in rows)
            page.locator("#cep").fill("00000-043")
            page.locator("#run_query").click()
            page.wait_for_function("document.querySelector('#query_status').innerText.includes('índice local')", timeout=60000)
            assert "Horta Sintetica Alfa" not in page.locator("#proximity_table").inner_text()

            page.locator("#cep").fill("00000-042")
            page.locator("input[name='query_modes'][value='motorcar']").check()
            page.locator("#query_direction").locator("..").locator(".selectize-input").click()
            page.locator(".selectize-dropdown [data-value='both']").click()
            run_query()
            rows = list(csv.DictReader(download("download_results", "network.csv").open()))
            assert len({row["metric_id"] for row in rows}) == 7
            assert {row["analysis_status"] for row in rows} == {"completed"}
            for tab in ("Estatísticas", "Banco offline", "Explorar"):
                page.get_by_role("tab", name=tab, exact=True).click()
                if tab == "Banco offline":
                    page.wait_for_function("document.querySelector('#inventory_table').innerText.includes('tematico')", timeout=10000)
            page.get_by_role("tab", name="Lotes", exact=True).click()
            page.locator("#batch_file").set_input_files(str(root / "tests/fixtures/v02/origins.csv"))
            page.wait_for_function("document.querySelector('#batch_file_progress').innerText.includes('Upload complete')", timeout=30000)
            page.locator("#submit_batch").click()
            page.wait_for_function("document.querySelector('#batch_message').innerText.includes('Lote concluído')", timeout=60000)
            bundle = download("download_batch", "batch.zip")
            with zipfile.ZipFile(bundle) as z:
                manifest = json.loads(z.read("manifest.json"))
                assert manifest["complete"] and manifest["valid_rows"] == 2 and manifest["error_rows"] == 2
                batch_rows = list(csv.DictReader(io.StringIO(z.read("results.csv").decode())))
                assert {row["origin_id"] for row in batch_rows} == {"coord", "cep"}
            assert not page.locator(".shiny-output-error").count()
            (artifacts / "browser-diagnostics.json").write_text(json.dumps(
                {"external": external, "errors": errors}, indent=2), encoding="utf-8")
            assert not external and not errors, (external, errors)
            page.screenshot(path=str(artifacts / "synthetic-smoke.png"), full_page=True)
            (artifacts / "evidence.json").write_text(json.dumps({"passed": True, "synthetic": True,
                "external_browser_requests": external, "javascript_errors": errors,
                "r_network_isolation_claimed": False}, indent=2), encoding="utf-8")
            context.close()
            browser.close()
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
                server.wait(timeout=5)
        server_log.close()
    print(f"Synthetic browser smoke passed: {artifacts}")


if __name__ == "__main__":
    main()
