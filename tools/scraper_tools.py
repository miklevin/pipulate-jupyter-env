# /home/mike/repos/pipulate/tools/scraper_tools.py
import asyncio
import hashlib
import json
import os
import sys
import shutil
import tempfile
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, urlparse
import random
import time

from loguru import logger
import undetected_chromedriver as uc
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By

from tools import auto_tool
from . import dom_tools

async def generate_optics_subprocess(target_dir_path: str):
    """Isolated wrapper to call llm_optics.py as a subprocess, protecting the event loop."""
    script_path = Path(__file__).resolve().parent / "llm_optics.py"
    
    proc = await asyncio.create_subprocess_exec(
        sys.executable, str(script_path), str(target_dir_path),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    
    stdout, stderr = await proc.communicate()
    
    if proc.returncode == 0:
        return {"success": True, "output": stdout.decode()}
    else:
        return {"success": False, "error": stderr.decode()}

def get_safe_path_component(url: str) -> tuple[str, str]:
    """Converts a URL into filesystem-safe components for directory paths."""
    parsed = urlparse(url)
    domain = parsed.netloc
    path = parsed.path
    if not path or path == '/':
        path_slug = "%2F"
    else:
        path_slug = quote(path, safe='').replace('/', '_')[:100]
    return domain, path_slug


def _guided_path_component(url: str) -> tuple[str, str]:
    """Build a final-URL-specific cache key without exposing query or fragment text."""
    parsed = urlparse(url)
    readable_path = quote(parsed.path or "/", safe="")[:80]
    url_digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    return parsed.netloc, f"{readable_path}--{url_digest}"


# --- Optional audio during browser startup ---
# Forked from stream.py's start_updating_music/stop_updating_music pattern:
# a marker-tagged shell loop in its OWN process group (os.setsid), killed as
# a group, with an idempotent pkill backstop keyed to the marker so it can
# never touch any other aplay pipeline. The wav lives in repo negative space
# (gitignored) or ~/.local/share/pipulate/; absent file = silent no-op.
SCRAPE_MUSIC_MARKER = "pipulate-scrape-music"


def _find_music_file():
    candidates = [
        Path(__file__).resolve().parent.parent / "jeopardy.wav",
        Path.home() / ".local/share/pipulate/jeopardy.wav",
        Path.home() / ".local/share/honeybot/jeopardy.wav",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def _start_scrape_music(verbose=True):
    import subprocess
    music = _find_music_file()
    if not music:
        return None

    try:
        return subprocess.Popen(
            ["sh", "-c", f'while :; do aplay -q -D default "{music}"; done # {SCRAPE_MUSIC_MARKER}'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )
    except Exception:
        return None


def _stop_scrape_music(proc):
    import signal
    import subprocess
    if proc is not None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            pass
    try:
        subprocess.run(["pkill", "-f", SCRAPE_MUSIC_MARKER], check=False)
    except Exception:
        pass


def _simplify_html_for_llm(html_content, default_title=""):
    """Applies a symmetrical, opinionated filter to HTML for LLM consumption."""
    try:
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html_content, 'html.parser')
        
        # Remove all noise elements that confuse LLMs (Added 'svg' to the hit list!)
        for tag in soup(['script', 'style', 'noscript', 'meta', 'link', 'head', 'svg']):
            tag.decompose()

        # Clean up attributes - keep only automation-relevant ones
        for element in soup.find_all():
            attrs_to_keep = {}
            for attr, value in element.attrs.items():
                # Added 'rel' and 'target' to preserve SEO link data!
                if attr in ['id', 'role', 'data-testid', 'name', 'type', 'href', 'src', 'class', 'for', 'value', 'placeholder', 'title', 'rel', 'target'] or attr.startswith('aria-'):
                    attrs_to_keep[attr] = value
            element.attrs = attrs_to_keep
        
        simple_html = soup.prettify()
    except Exception as e:
        logger.warning(f"⚠️ DOM simplification failed, using fallback: {e}")
        simple_html = html_content

    # Add minimal metadata wrapper
    title = soup.title.string if soup and soup.title else default_title
    final_html = f"<html>\n<head><title>{title}</title></head>\n<body>\n{simple_html}\n</body>\n</html>"
    return final_html


# NOT a tool, and the leading underscore always said so. The 2026-07-24 patch
# that introduced this function anchored its SEARCH block on the `async def`
# line below and inserted ABOVE it -- which left @auto_tool sitting where it
# was, silently transplanting it onto this helper and stripping it from
# selenium_automation. Nothing raised; ruff passed; the registry was simply
# wrong. DECORATOR STRADDLE RULE: decorators bind downward, so any insertion
# anchored on a def must include the line above it in the SEARCH.
def _document_candidates(cdp_events: list, domain: str, final_url: str = "") -> list:
    """Document responseReceived events that plausibly ARE the requested page.

    Returned in ledger order; the caller takes [-1]. Pure and ledger-only on
    purpose: no live CDP call appears here, so this selection can be REPLAYED
    over any cached network_log.jsonl offline. A selection that needs a live
    browser can never be audited against captures you already have.
    """
    from urllib.parse import urlsplit

    def _norm(host: str) -> str:
        host = (host or "").lower()
        return host[4:] if host.startswith("www.") else host

    docs = [
        ev for ev in cdp_events
        if ev.get("method") == "Network.responseReceived"
        and ev.get("params", {}).get("type") == "Document"
    ]
    # THE SAME-ORIGIN IFRAME DEFEAT (convicted 2026-08-04). The host-exact
    # filter below was hardened on 2026-07-24 against THIRD-PARTY frames that
    # carry the target host in a query parameter. It is structurally blind to a
    # SAME-ORIGIN frame: a Shop Pay buyer-recognition callback served from the
    # storefront's own host passes host-exactness BY DEFINITION, fires late,
    # and the caller then takes [-1] -- the LAST Document, which is the iframe.
    # The frame tiebreaker below is only a tiebreaker, and it is permitted to
    # no-op, so nothing downstream can tell a witnessed choice from a guess.
    # ANCHOR ON A VALUE THE BROWSER AUTHORED, NOT ON AN INFERENCE. final_url is
    # driver.current_url, read before this selection runs. A sub-frame URL is
    # NEVER the browser's current URL, so an exact match cannot be a frame --
    # which makes this correct regardless of which inferential step below was
    # the one that broke.
    # PURITY PRESERVED, deliberately: the caller passes final_url IN, no live
    # CDP call appears here, and the whole selection is still replayable
    # offline over any cached network_log.jsonl -- which is what makes the
    # straddle for this very patch cost zero browser flights.
    # FAILS OPEN: no exact match degrades to the host+frame path unchanged, so
    # the worst case equals the behaviour shipped before this block existed.
    if final_url:
        target = final_url.split("#", 1)[0]
        exact = [
            ev for ev in docs
            if ev.get("params", {}).get("response", {}).get("url", "").split("#", 1)[0] == target
        ]
        if exact:
            return exact
    want = _norm(domain)
    on_host = [
        ev for ev in docs
        if _norm(urlsplit(ev.get("params", {}).get("response", {}).get("url", "")).hostname) == want
    ]
    if not on_host:
        # NEVER REGRESS. An apex->subdomain redirect can legitimately leave no
        # host-exact Document. Falling back to the historical substring set
        # makes the worst case identical to the behaviour shipped before this
        # function existed -- and the source_provenance flag now makes the
        # consequence visible if the fallback itself comes up empty.
        return [
            ev for ev in docs
            if domain in ev.get("params", {}).get("response", {}).get("url", "")
        ]
    if len(on_host) > 1 and docs:
        # TIEBREAKER ONLY, AND IT CAN ONLY NARROW. The browser navigates the
        # top frame before any subframe can exist, so the FIRST Document event
        # in the ledger carries the main frameId -- available with zero extra
        # CDP round trips, and stable across a challenge reload because a
        # navigation changes loaderId, not frameId. Guarded so it can never
        # empty the set: an unrecognised frame layout degrades to host-exact
        # selection rather than to nothing.
        main_frame = docs[0].get("params", {}).get("frameId")
        same_frame = [ev for ev in on_host if ev.get("params", {}).get("frameId") == main_frame]
        if same_frame:
            return same_frame
    return on_host


def _capture_checkpoint(stdin=None, stdout=None) -> dict:
    """Require an explicit CAPTURE token from the human's keyboard.

    /DEV/TTY PREFERENCE (convicted 2026-07-29, public_walk stop 1): the
    inherited sys.stdin returned INSTANT EOF at the CAPTURE> prompt -- the
    "Browser closed" line landed 0.14s after the staleness wait, so fd 0
    was already dead before the prompt printed. The keyboard was fine; the
    inherited descriptor was not. /dev/tty is the controlling terminal
    itself and bypasses every inherited-fd failure mode: a consumed pipe,
    a closed fd, and -- the destination this fence is riding toward -- a
    `curl | bash` stdin, where the pipe IS the script and /dev/tty is the
    only honest way to ask a human anything. Prefer it whenever the caller
    handed us the real sys.stdin; an EXPLICIT non-sys stdin (test
    harnesses) is honored untouched. No controlling terminal at all falls
    through to the original isatty gate, which fails closed exactly as
    before.
    """
    input_stream = sys.stdin if stdin is None else stdin
    output_stream = sys.stdout if stdout is None else stdout

    tty_handle = None
    if input_stream is sys.stdin:
        try:
            tty_handle = open("/dev/tty", "r", encoding="utf-8")
            input_stream = tty_handle
        except OSError:
            tty_handle = None

    try:
        try:
            if not input_stream.isatty():
                return {
                    "success": False,
                    "error": "interactive capture requires a TTY on stdin",
                }
        except Exception as exc:
            return {
                "success": False,
                "error": f"could not verify interactive stdin: {exc}",
            }

        try:
            output_stream.write(
                "\nNavigate in the visible browser, then type CAPTURE and press Enter.\n"
                "Any other response aborts without capturing artifacts.\n"
                "CAPTURE> "
            )
            output_stream.flush()
            response = input_stream.readline()
        except KeyboardInterrupt:
            return {
                "success": False,
                "error": "interactive checkpoint interrupted",
            }
        except Exception as exc:
            return {
                "success": False,
                "error": f"interactive checkpoint read failed: {exc}",
            }

        if response == "":
            return {
                "success": False,
                "error": "interactive checkpoint reached EOF",
            }
        # CASE-INSENSITIVE ON PURPOSE (banked 2026-08-01). The token's safety
        # comes entirely from being IMPOSSIBLE TO PRODUCE BY ACCIDENT: no pipe,
        # no EOF, no stray Enter, no dead descriptor and no automation emits
        # these seven letters. Lowercase is exactly as impossible as uppercase,
        # so the shift key was a tax with no revenue -- and it was collected at
        # the newcomer's first handshake, where a refusal reads as "this thing
        # is broken" rather than "you missed a key."
        # DELIBERATELY NOT A RETRY LOOP. A retry gives the fence a SECOND STATE,
        # and "nothing was written" stops being provable in one sentence. One
        # read, one comparison, one branch, and every non-match returns before
        # mkdir. A wrong answer still costs the ENTIRE ride, because a non-token
        # answer is the human's ABORT, and abort must be as instant as consent.
        if response.strip().upper() != "CAPTURE":
            return {
                "success": False,
                "error": "interactive checkpoint was not confirmed",
            }
        return {"success": True}
    finally:
        if tty_handle is not None:
            try:
                tty_handle.close()
            except Exception:
                pass


async def _selenium_capture(params: dict, checkpoint=None) -> dict:
    """
    Performs an advanced browser automation scrape of a single URL using undetected-chromedriver.
    Checks for cached data before initiating a new scrape.
    ...
    """
    url = params.get("url")
    domain = params.get("domain")
    url_path_slug = params.get("url_path_slug")
    take_screenshot = params.get("take_screenshot", False)
    headless = params.get("headless", True)
    is_notebook_context = params.get("is_notebook_context", False)
    persistent = params.get("persistent", False)
    profile_name = params.get("profile_name")
    if not profile_name:
        # NO LOCAL IMPORT HERE. urlparse is imported at module level; a
        # function-level `from urllib.parse import urlparse` inside this
        # conditional made urlparse a LOCAL for the whole function, bound
        # only when profile_name was falsy. Every sigil scrape omits
        # profile_name, so the bind always ran and the shadow slept.
        # The first caller to SUPPLY profile_name (public_walk's trail
        # defaults, 2026-07-29) skipped the bind, and urlparse(final_url)
        # after the CAPTURE checkpoint died with UnboundLocalError.
        _host = urlparse(params.get("url", "")).netloc.split(":")[0]
        _labels = [label for label in _host.split(".") if label]
        _slug = _labels[-2] if len(_labels) >= 2 else (_labels[0] if _labels else "")
        if _slug and Path(f"data/uc_profiles/{_slug}").exists():
            profile_name = _slug
        else:
            profile_name = "default"
    verbose = params.get("verbose", True)
    override_cache = params.get("override_cache", False)
    delay_range = params.get("delay_range")
    interactive = checkpoint is not None

    if not all([url, domain, url_path_slug is not None]):
        return {"success": False, "error": "URL, domain, and url_path_slug parameters are required."}

    base_dir = Path("browser_cache/")
    if not is_notebook_context:
        base_dir = base_dir / "looking_at"
    
    output_dir = base_dir / domain / url_path_slug
    artifacts = {}
    final_url = None

    def failure(message):
        return {
            "success": False,
            "error": str(message),
            "looking_at_files": dict(artifacts),
            "cached": False,
            "requested_url": url,
            "final_url": final_url,
            "interactive": interactive,
        }

    if interactive and (
        headless is not False
        or persistent is not True
        or override_cache is not True
    ):
        return failure(
            "interactive capture requires headless=False, "
            "persistent=True, and override_cache=True"
        )

    # --- CACHE OVERRIDE LOGIC ---
    if not interactive and override_cache and output_dir.exists():
        if verbose:
            logger.info(f"🧹 override_cache is True. Clearing existing directory: {output_dir}")
        try:
            shutil.rmtree(output_dir)
        except Exception as e:
            logger.error(f"Failed to clear cache directory: {e}")

    # --- IDEMPOTENCY CHECK ---
    # Check if the primary artifact (hydrated_dom.html) already exists.
    dom_path = output_dir / "hydrated_dom.html"
    if not interactive and dom_path.exists():
        if verbose:
            logger.info(f"✅ Using cached data from: {output_dir}")

        # Gather paths of existing artifacts
        for artifact_name in [
            "hydrated_dom.html", 
            "source.html", 
            "simple_source_html.html",
            "simple_hydrated_dom.html",
            "diff_boxes.txt",
            "diff_boxes.html",
            "diff_hierarchy.txt",
            "diff_hierarchy.html",
            "diff_simple_dom.txt",
            "diff_simple_dom.html",
            "links.md",
            "network_log.jsonl",
            "screenshot.png", 
            "seo.md",
            "source_dom_layout_boxes.txt", 
            "source_dom_layout_boxes.html", 
            "source_dom_hierarchy.txt", 
            "source_dom_hierarchy.html", 
            "hydrated_dom_layout_boxes.txt", 
            "hydrated_dom_layout_boxes.html", 
            "hydrated_dom_hierarchy.txt", 
            "hydrated_dom_hierarchy.html", 
            "accessibility_tree.json", 
            "accessibility_tree_summary.txt"
        ]:
            artifact_path = output_dir / artifact_name
            if artifact_path.exists():
                 artifacts[Path(artifact_name).stem] = str(artifact_path)

        # Normalize cached artifact keys to match the fresh-scrape vocabulary.
        # The loop above keys files by filename stem, so "source.html" lands under
        # "source" and "headers.json" was never enumerated at all. Fresh scrapes
        # expose 'source_html' and 'headers', so cached results must agree or the
        # $URL route (headers + raw source only) silently finds nothing.
        for filename, semantic_key in [
            ("source.html", "source_html"),
            ("headers.json", "headers"),
            ("seo.md", "seo_md"),
            ("links.md", "links_md"),
            ("diff_hierarchy.txt", "diff_hierarchy_txt"),
            ("diff_simple_dom.txt", "diff_simple_txt"),
            ("accessibility_tree_summary.txt", "accessibility_tree_summary"),
            ("optics_manifest.txt", "optics_manifest"),
        ]:
            candidate = output_dir / filename
            if candidate.exists():
                artifacts[semantic_key] = str(candidate)

        return {"success": True, "looking_at_files": artifacts, "cached": True}

    # --- Fuzzed Delay Logic (only runs if not cached) ---
    if delay_range and isinstance(delay_range, (tuple, list)) and len(delay_range) == 2:
        min_delay, max_delay = delay_range
        if isinstance(min_delay, (int, float)) and isinstance(max_delay, (int, float)) and min_delay <= max_delay:
            delay = random.uniform(min_delay, max_delay)
            if verbose:
                logger.info(f"⏳ Waiting for {delay:.3f} seconds before next request...")
            await asyncio.sleep(delay)
        else:
            logger.warning(f"⚠️ Invalid delay_range provided: {delay_range}. Must be a tuple of two numbers (min, max).")

    driver = None
    profile_path = None
    temp_profile = False
    music_proc = None

    # --- Find the browser executable path (Platform-Specific) ---
    effective_os = os.environ.get("EFFECTIVE_OS") # This is set by your flake.nix
    
    # Fallback in case script is run outside of the Nix shell
    if not effective_os:
        import platform
        effective_os = platform.system().lower()

    browser_path = None
    driver_path = None

    if effective_os == "linux":
        if verbose: logger.info("🐧 Linux platform detected. Looking for Nix-provided Chromium...")
        browser_path = shutil.which("chromium")
        driver_path = shutil.which("undetected-chromedriver")
        if not browser_path:
            browser_path = shutil.which("chromium-browser")
        
        if not browser_path:
            logger.error("❌ Could not find Nix-provided chromium or chromium-browser.")
            return {"success": False, "error": "Chromium executable not found in Nix environment."}
        if not driver_path:
            logger.error("❌ Could not find Nix-provided 'undetected-chromedriver'.")
            return {"success": False, "error": "undetected-chromedriver not found in Nix environment."}

    elif effective_os == "darwin":
        if verbose: logger.info("🍏 macOS platform detected. Looking for host-installed Google Chrome...")
        # On macOS, we rely on the user's host-installed Google Chrome.
        # undetected-chromedriver will use webdriver-manager to find/download the driver.
        browser_path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        driver_path = None # This tells uc to find/download the driver automatically

        if not Path(browser_path).exists():
            # Fallback for Chrome Canary
            browser_path_canary = "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
            if Path(browser_path_canary).exists():
                browser_path = browser_path_canary
                if verbose: logger.info("  -> Google Chrome not found, using Google Chrome Canary.")
            else:
                logger.error(f"❌ Google Chrome not found at default path: {browser_path}")
                logger.error("   Please install Google Chrome on your Mac to continue.")
                return {"success": False, "error": "Google Chrome not found on macOS."}
        
        # Check if webdriver-manager is installed (it's a dependency of undetected-chromedriver)
        try:
            import webdriver_manager
        except ImportError:
            logger.error("❌ 'webdriver-manager' package not found.")
            logger.error("   Please add 'webdriver-manager' to requirements.txt and re-run 'nix develop'.")
            return {"success": False, "error": "webdriver-manager Python package missing."}
    
    else:
        logger.error(f"❌ Unsupported EFFECTIVE_OS: '{effective_os}'. Check flake.nix.")
        return {"success": False, "error": "Unsupported operating system."}

    if verbose: 
        logger.info(f"🔍 Using browser executable at: {browser_path}")
        if driver_path:
            logger.info(f"🔍 Using driver executable at: {driver_path}")
        else:
            logger.info(f"🔍 Using driver executable from webdriver-manager (uc default).")

    try:
        # Guided capture cannot know its truthful destination until after the
        # human checkpoint exposes the browser's final current URL.
        if not interactive:
            output_dir.mkdir(parents=True, exist_ok=True)
            if verbose: logger.info(f"💾 Saving new artifacts to: {output_dir}")

        options = uc.ChromeOptions()
        options.set_capability("goog:loggingPrefs", {"performance": "ALL"})
        if headless:
            options.add_argument("--headless")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--start-maximized")
        options.add_argument("--window-size=1920,1080")

        if persistent:
            profile_path = Path(f"data/uc_profiles/{profile_name}")
            profile_path.mkdir(parents=True, exist_ok=True)
            logger.info(f"🔒 Using persistent profile: {profile_path}")
        else:
            profile_path = tempfile.mkdtemp(prefix='pipulate_automation_')
            temp_profile = True
            logger.info(f"👻 Using temporary profile: {profile_path}")
        
        if verbose:
            print("Opening the browser; waiting for the page...", flush=True)
        music_proc = _start_scrape_music(verbose=verbose)
        logger.info(f"🚀 Initializing undetected-chromedriver (Headless: {headless})...")
        try:
            driver = uc.Chrome(options=options, 
                               user_data_dir=str(profile_path), 
                               browser_executable_path=browser_path,
                               driver_executable_path=driver_path)
        except Exception as e:
            error_msg = str(e)
            if "Current browser version is" in error_msg:
                import re
                match = re.search(r'Current browser version is (\d+)', error_msg)
                if match:
                    fallback_version = int(match.group(1))
                    logger.warning(f"⚠️ Chrome version mismatch detected. Auto-healing with version_main={fallback_version}")
                    # UC consumes the options object. We must forge a fresh one.
                    fresh_options = uc.ChromeOptions()
                    fresh_options.set_capability("goog:loggingPrefs", {"performance": "ALL"})
                    if headless:
                        fresh_options.add_argument("--headless")
                    fresh_options.add_argument("--no-sandbox")
                    fresh_options.add_argument("--disable-dev-shm-usage")
                    fresh_options.add_argument("--start-maximized")
                    fresh_options.add_argument("--window-size=1920,1080")
                    
                    driver = uc.Chrome(options=fresh_options, 
                                       user_data_dir=str(profile_path), 
                                       browser_executable_path=browser_path,
                                       driver_executable_path=driver_path,
                                       version_main=fallback_version)
                else:
                    raise
            else:
                raise

        logger.info(f"Navigating to: {url}")
        driver.get(url)

        try:
            if verbose: logger.info("Waiting for security challenge to trigger a reload (Stage 1)...")
            initial_body = driver.find_element(By.TAG_NAME, 'body')
            WebDriverWait(driver, 20).until(EC.staleness_of(initial_body))
            if verbose: logger.success("✅ Page reload detected!")
            
            if verbose: logger.info("Waiting for main content to appear after reload (Stage 2)...")
            WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.CSS_SELECTOR, "body")))
            if verbose: logger.success("✅ Main content located!")
        except Exception as e:
            if verbose: logger.info(f"Did not detect a page reload for security challenge. Proceeding anyway.")

        # The wait is over one way or the other: cut the think-music sharply.
        _stop_scrape_music(music_proc)
        music_proc = None

        if checkpoint is not None:
            try:
                checkpoint_result = checkpoint()
            except KeyboardInterrupt:
                return failure("interactive checkpoint interrupted")
            except Exception as exc:
                return failure(f"interactive checkpoint failed: {exc}")

            if not isinstance(checkpoint_result, dict):
                return failure("interactive checkpoint returned a non-dict result")
            if not checkpoint_result.get("success"):
                return failure(
                    checkpoint_result.get("error")
                    or "interactive checkpoint was not confirmed"
                )

        try:
            final_url = driver.current_url
        except Exception as exc:
            return failure(f"could not read browser final URL: {exc}")

        final_parsed = urlparse(final_url)
        if (
            not isinstance(final_url, str)
            or final_parsed.scheme not in {"http", "https"}
            or not final_parsed.netloc
        ):
            return failure(f"browser final URL is not absolute http(s): {final_url!r}")

        if interactive:
            final_domain, final_slug = _guided_path_component(final_url)
            output_dir = base_dir / final_domain / final_slug
            if output_dir.exists():
                shutil.rmtree(output_dir)
            output_dir.mkdir(parents=True, exist_ok=True)
            if verbose:
                logger.info(
                    f"💾 Saving guided artifacts for {final_url} to: {output_dir}"
                )

        # --- Capture Core Artifacts ---
        dom_content = driver.execute_script("return document.documentElement.outerHTML;")
        dom_path = output_dir / "hydrated_dom.html"
        dom_path.write_text(dom_content, encoding='utf-8')
        artifacts['hydrated_dom'] = str(dom_path)

        # --- Network Flight Recorder (CDP perf log -> network_log.jsonl) ---
        # ORDERING IS LOAD-BEARING, AND NOT FOR THE REASON THIS COMMENT USED TO
        # GIVE. The old note said this drain must precede "the XHR header replay
        # below." That replay no longer exists -- the wire-truth block below now
        # reads this ledger instead of reissuing anything. SAME-CAR LABEL RULE
        # conviction 2026-07-24: the guard rail named a hazard already removed,
        # which reads as documentation and functions as archaeology.
        #
        # The real constraint is stronger. This drain is the PRODUCER and the
        # getResponseBody block below is the CONSUMER: cdp_events is built here
        # and doc_events filters nothing else. Move this drain below that block
        # and cdp_events is empty, doc_events is empty, getResponseBody never
        # runs, and true_raw_source falls through to driver.page_source -- the
        # HYDRATED DOM written into source.html under the name "raw source."
        # Hinge A then diffs the hydrated DOM against itself, reports FLAT 0
        # degrees, and testifies that the site does nothing with JavaScript.
        # Silent, plausible, and it inverts the one measurement the triptych
        # exists to take.
        #
        # get_log() DRAINS: this is the one and only read. A second
        # get_log("performance") anywhere returns [], so any debug drain added
        # above this line steals the whole flight and leaves the ledger empty.
        if verbose: logger.info("🛜 Draining CDP performance log (network flight recorder)...")
        cdp_events = []
        try:
            perf_entries = driver.get_log("performance")
            netlog_path = output_dir / "network_log.jsonl"
            with netlog_path.open("w", encoding="utf-8") as f:
                for entry in perf_entries:
                    try:
                        ev = json.loads(entry["message"])["message"]
                        cdp_events.append(ev)
                        f.write(json.dumps(ev) + "\n")
                    except (KeyError, json.JSONDecodeError):
                        continue
            artifacts['network_log'] = str(netlog_path)
            if verbose: logger.info(f"🛜 Captured {len(perf_entries)} raw CDP events to {netlog_path.name}")
        except Exception as e:
            logger.warning(f"⚠️ Could not capture CDP performance log: {e}")
        
        # 1. Wire Truth Capture (CDP ledger + Network.getResponseBody)
        # The organic Document response is already sitting in the drained CDP
        # ledger. Pull its actual headers and its actual body — no reenactment,
        # no second request from the same IP. Probe-verified 2026-07-09:
        # body survives the buffer post-drain, headed, uc + Nix chromium.
        if verbose: logger.info("🌐 Extracting wire-truth headers and raw source from CDP ledger...")
        actual_headers = {}
        true_raw_source = ""
        # PROVENANCE: source.html is only "raw source" when it came off the
        # wire. Every fallback below writes the HYDRATED DOM into that file
        # under the same name, and until now the only witness was a log line
        # that scrolls away. Stamp the artifact instead, so the mislabel cannot
        # outlive the terminal that reported it.
        source_provenance = "wire"
        # Bound HERE, before the try, because headers_data below is built
        # OUTSIDE that try and references this name on every path -- including
        # the paths where wire extraction raised and nothing was selected. The
        # 2026-07-24 car that introduced the reference shipped with a prose
        # caveat saying the binding was "derivable" instead of deriving it.
        # CONDITIONAL CAR RULE: prose does not execute. An empty string is the
        # honest value for "no Document was selected," and it is falsy, so a
        # reader can tell it from a real url without a sentinel.
        doc_url = ""
        try:
            # FRAME SELECTION, CONVICTED AND REPLACED 2026-07-24. The previous
            # filter was `domain in url` -- a SUBSTRING test -- and a census of
            # 18 cached ledgers found 5 in which it admitted more than one
            # candidate. In every one of those 5, [-1] selected a THIRD-PARTY
            # url: a consent-sync frame, a vendor SDK frame, and a conversion
            # pixel. None was served by the site under test. The match was not
            # the predicted cdn.<domain> subdomain case at all -- these vendors
            # carry the target host in a QUERY PARAMETER, which is the default
            # behaviour of most tag, consent and attribution products. So the
            # substring test does not merely admit subdomains; it admits every
            # third party polite enough to say who sent it.
            #
            # Selection now lives in _document_candidates() at module level:
            # host-exact (www-normalised), with main-frameId as a tiebreaker
            # that can only narrow, and a fallback to the historical substring
            # set so the worst case equals the old behaviour. It is pure and
            # ledger-only so it can be replayed offline over any cached capture.
            #
            # [-1] SURVIVES, and its rationale is still UNWITNESSED: the
            # staleness_of() wait above exists because a security challenge
            # serves an interstitial Document and then reloads, making the LAST
            # candidate the real page. No capture on this machine has ever been
            # challenged -- every scrape logs "Did not detect a page reload."
            # The reasoning is sound from the code and has no receipt behind it.
            # Redirect chains do not threaten it either way; CDP surfaces those
            # as requestWillBeSent with redirectResponse, not as extra
            # responseReceived events.
            doc_events = _document_candidates(cdp_events, domain, final_url)
            if doc_events:
                doc_params = doc_events[-1]["params"]
                # The subject of the headers on the very next line. Captured
                # from the SAME event so the two can never drift apart.
                doc_url = doc_params.get("response", {}).get("url", "")
                wire_headers = doc_params.get("response", {}).get("headers", {})
                actual_headers = {str(k).lower(): v for k, v in wire_headers.items()}
                body_result = driver.execute_cdp_cmd(
                    "Network.getResponseBody", {"requestId": doc_params["requestId"]}
                )
                true_raw_source = body_result.get("body", "")
                if body_result.get("base64Encoded"):
                    import base64
                    true_raw_source = base64.b64decode(true_raw_source).decode("utf-8", errors="replace")
            if not true_raw_source.strip():
                if verbose: logger.warning("⚠️ Wire body unavailable; falling back to page_source.")
                true_raw_source = driver.page_source
                source_provenance = "page_source_fallback"
            if not actual_headers:
                actual_headers = {"error": "No Document response found in CDP ledger"}
        except Exception as e:
            if verbose: logger.warning(f"⚠️ Failed to extract wire truth from CDP ledger: {e}")
            if not actual_headers:
                actual_headers = {"error": "Could not extract headers from CDP ledger"}
            if not true_raw_source.strip():
                # This path carried NO warning at all until now -- a completely
                # silent swap of hydrated DOM for wire source, which is the
                # worst shape this failure can take.
                if verbose: logger.warning("⚠️ Wire extraction raised; falling back to page_source.")
                true_raw_source = driver.page_source  # Fallback to the live DOM
                source_provenance = "page_source_fallback"
            
        # Save True Raw Source
        source_html_path = output_dir / "source.html"
        source_html_path.write_text(true_raw_source, encoding='utf-8')
        artifacts['source_html'] = str(source_html_path)
        
        # Save Headers
        headers_data = {
            "url": url,
            "final_url": final_url,
            "title": driver.title,
            "timestamp": datetime.now().isoformat(),
            "status": "success",
            # WHOSE HEADERS ARE THESE? "url" above is the url we REQUESTED;
            # this is the url the headers actually came off. They differed on
            # 5 of 18 cached captures under the pre-2026-07-24 substring
            # selector, which stacked a third-party frame's response headers
            # into a payload labelled as the site's. The body fell back to
            # page_source on those captures and is merely mislabelled; the
            # headers did not fall back and are simply someone else's. An
            # artifact that does not record its own subject cannot be audited
            # against the ledger sitting next to it.
            "header_source_url": doc_url,
            # WHICH RULE CHOSE IT. header_source_url (2026-07-24) records the
            # SUBJECT of these headers; this records HOW that subject was
            # picked. The 2026-08-04 conviction cost two turns precisely
            # because the artifact could name its subject but not its
            # selection path. "final_url_exact" means the browser's own
            # current URL matched a Document response; "host_fallback" means
            # the selector guessed from host and frame order and the result
            # did NOT match the final URL -- treat the whole triptych as
            # suspect on that value; "none" means no Document was selected at
            # all. One jq, not a two-turn investigation.
            "header_selection": (
                "none" if not doc_url
                else "final_url_exact"
                if final_url and doc_url.split("#", 1)[0] == final_url.split("#", 1)[0]
                else "host_fallback"
            ),
            # Consumers read this to decide whether source.html may be trusted
            # as the LEFT PANEL of the triptych. Absent on captures taken
            # before 2026-07-24, which consumers therefore treat as UNFLAGGED,
            # not as bad -- fail-open on purpose, because marking years of
            # legacy captures suspect is noise wearing caution's hat.
            "source_provenance": source_provenance,
            "headers": actual_headers
        }
        headers_path = output_dir / "headers.json"
        headers_path.write_text(json.dumps(headers_data, indent=2), encoding='utf-8')
        artifacts['headers'] = str(headers_path)

        if take_screenshot:
            screenshot_path = output_dir / "screenshot.png"
            driver.save_screenshot(str(screenshot_path))
            artifacts['screenshot'] = str(screenshot_path)



        # 2. Create LLM-Optimized Simplified DOMs (The Symmetrical Lens)
        if verbose: logger.info("🧠 Creating LLM-optimized simplified DOMs (Symmetrical Lens)...")
        
        simple_source_content = _simplify_html_for_llm(true_raw_source, driver.title)
        simple_source_path = output_dir / "simple_source_html.html"
        simple_source_path.write_text(simple_source_content, encoding='utf-8')
        artifacts['simple_source'] = str(simple_source_path)

        simple_hydrated_content = _simplify_html_for_llm(dom_content, driver.title)
        simple_hydrated_path = output_dir / "simple_hydrated_dom.html"
        simple_hydrated_path.write_text(simple_hydrated_content, encoding='utf-8')
        artifacts['simple_hydrated'] = str(simple_hydrated_path)

        # --- Generate Accessibility Tree Artifact ---
        if verbose: logger.info("🌲 Extracting accessibility tree...")
        try:
            driver.execute_cdp_cmd("Accessibility.enable", {})
            ax_tree_result = driver.execute_cdp_cmd("Accessibility.getFullAXTree", {})
            ax_tree = ax_tree_result.get("nodes", [])
            ax_tree_path = output_dir / "accessibility_tree.json"
            ax_tree_path.write_text(json.dumps({"success": True, "node_count": len(ax_tree), "accessibility_tree": ax_tree}, indent=2), encoding='utf-8')
            artifacts['accessibility_tree'] = str(ax_tree_path)

            summary_result = await dom_tools.summarize_accessibility_tree({"file_path": str(ax_tree_path)})
            if summary_result.get("success"):
                summary_path = output_dir / "accessibility_tree_summary.txt"
                summary_path.write_text(summary_result["output"], encoding='utf-8')
                artifacts['accessibility_tree_summary'] = str(summary_path)
        except Exception as ax_error:
            logger.warning(f"⚠️ Could not extract accessibility tree: {ax_error}")

        # --- Generate LLM Optics (Subprocess Bulkhead) ---
        if verbose: logger.info("👁️‍🗨️ Running LLM Optics Engine (Subprocess Bulkhead)...")
        # We pass the output_dir, not the dom_path
        optics_result = await generate_optics_subprocess(str(output_dir))
        
        if optics_result.get('success'):
            if verbose: logger.success("✅ LLM Optics Engine completed successfully.")
            
            # === LEAN DEFAULT BUNDLE FOR !https:// IN PROMPT_FOO ===
            # Primary "what's on the page" + wire truth
            default_keys = ['seo_md', 'headers']
            for key in default_keys:
                if key == 'seo_md':
                    p = output_dir / 'seo.md'
                else:
                    p = output_dir / f"{key}.json"
                if p.exists():
                    artifacts[key] = str(p)
            
            # === CAPPED MANIFEST FOR DRILL-DOWN (address book) ===
            manifest = []
            for f in sorted(output_dir.glob("*.*"), key=lambda p: p.stat().st_size, reverse=True):
                if f.suffix in ('.txt', '.html', '.json', '.jsonl', '.md'):
                    size_kb = len(f.read_text(encoding='utf-8', errors='ignore')) // 1000
                    manifest.append(f"{f.name} (~{size_kb}k)")
                elif f.suffix == '.png':
                    manifest.append(f"{f.name} (~{f.stat().st_size // 1000}k, image)")
                else:
                    continue
                if len(manifest) >= 15:  # prevent bloat in parent prompt
                    break
            if manifest:
                manifest_content = "OPTICS MANIFEST (drill-down available):\n" + "\n".join(manifest)
                manifest_path = output_dir / "optics_manifest.txt"
                manifest_path.write_text(manifest_content, encoding='utf-8')
                artifacts['optics_manifest'] = str(manifest_path)
            
            # Still populate full set for power users / notebooks
            for optic_key, filename in [
                ('source_hierarchy_txt', 'source_dom_hierarchy.txt'),
                # ... (keep the rest of the original list if desired, or prune)
                ('diff_hierarchy_txt', 'diff_hierarchy.txt'),
                ('diff_simple_txt', 'diff_simple_dom.txt'),
                ('links_md', 'links.md'),
                # etc.
            ]:
                optic_path = output_dir / filename
                if optic_path.exists():
                    artifacts[optic_key] = str(optic_path)
        else:
            if verbose: logger.warning(f"⚠️ LLM Optics Engine partially failed: {optics_result.get('error')}")

        logger.success(f"✅ Scrape successful for {url}")
        return {
            "success": True,
            "looking_at_files": artifacts,
            "cached": False,
            "requested_url": url,
            "final_url": final_url,
            "interactive": interactive,
        }

    except Exception as exc:
        logger.error(f"❌ Browser capture failed for {url}: {exc}")
        return failure(f"browser capture failed: {exc}")

    finally:
        _stop_scrape_music(music_proc)
        if driver:
            try:
                driver.quit()
                if verbose: logger.info("Browser closed.")
            except Exception as e:
                logger.warning(f"Error while quitting browser: {e}")

        if temp_profile and profile_path and os.path.exists(profile_path):
            try:
                # Add ignore_errors=True to prevent ghost processes from crashing the cleanup
                shutil.rmtree(profile_path, ignore_errors=True)
                if verbose: logger.info(f"Cleaned up temporary profile: {profile_path}")
            except Exception as e:
                logger.warning(f"Could not completely remove temp profile (this is normal): {e}")


@auto_tool
async def selenium_automation(params: dict) -> dict:
    """Performs an advanced browser scrape with the existing non-interactive contract."""
    return await _selenium_capture(params)


async def guided_browser_capture(params: dict, stdin=None, stdout=None) -> dict:
    """Capture one human-guided page through one visible persistent driver."""
    if not isinstance(params, dict):
        return {
            "success": False,
            "error": "guided browser parameters must be a dict",
            "looking_at_files": {},
            "cached": False,
            "requested_url": None,
            "final_url": None,
            "interactive": True,
        }

    requested_url = params.get("url")

    def fail(message):
        return {
            "success": False,
            "error": str(message),
            "looking_at_files": {},
            "cached": False,
            "requested_url": requested_url,
            "final_url": None,
            "interactive": True,
        }

    for key, expected in (
        ("headless", False),
        ("persistent", True),
        ("override_cache", True),
    ):
        if params.get(key) is not expected:
            return fail(
                f"guided capture requires {key}={expected!r}; "
                f"got {params.get(key)!r}"
            )

    input_stream = sys.stdin if stdin is None else stdin
    try:
        stdin_is_tty = input_stream.isatty()
    except Exception as exc:
        return fail(f"could not verify interactive stdin before browser launch: {exc}")
    if not stdin_is_tty and input_stream is sys.stdin:
        # THE DOORMAN LEARNS THE DOOR'S TRICK (banked 2026-08-01, probe-convicted).
        # _capture_checkpoint was hardened to prefer /dev/tty on 2026-07-29 and its
        # own comment named the destination by name: a `curl | bash` stdin, where
        # the pipe IS the script. The hardening then stopped ONE FUNCTION SHORT --
        # this gate still tested the INHERITED descriptor and refused before the
        # browser ever opened. The door was ready; the doorman turned people away.
        # IDENTITY-GUARDED so the two can never disagree again: an EXPLICIT stream
        # (a test harness passing io.StringIO) fails `is sys.stdin`, is honored
        # untouched, and still refuses. Only the "use the terminal" case gets the
        # second look. No controlling terminal (cron, CI, setsid) raises OSError
        # and falls through, failing closed exactly as before. Strictly additive:
        # this branch runs ONLY where the gate was already about to refuse.
        # COMPILE-LANE BLINDNESS, named so nobody mistakes a green for a witness:
        # prompt_foo's `!` executor spawns with start_new_session=True, which
        # detaches the controlling terminal, so /dev/tty is UNOPENABLE there and an
        # echoed probe prints the refusal whether or not this code exists. That
        # receipt is a fail-closed guard. The only witness is a human riding.
        try:
            with open("/dev/tty", "r", encoding="utf-8") as probe_tty:
                stdin_is_tty = probe_tty.isatty()
        except OSError:
            pass
    if not stdin_is_tty:
        return fail("guided capture requires a TTY on stdin before browser launch")

    return await _selenium_capture(
        dict(params),
        checkpoint=lambda: _capture_checkpoint(
            stdin=input_stream,
            stdout=stdout,
        ),
    )
