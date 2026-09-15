#!/usr/bin/env python3
"""Mother Cat trail walker, Car B: actuate Car A's validated plan.

walk.py remains the strict, stdlib-only dry-run planner. This module adds the
actuating side of the Mother Cat Kata:

  EXPORTS                  -- the walk's exports file, when one resolves, is
                              layered UNDER the environment: --exports PATH
                              wins, else <trail>.exports.sh beside the trail.
                              An exported, non-empty variable is never
                              overwritten by the file.
  PRE-FLIGHT               -- every url_env the WHOLE walk needs is checked
                              before anything opens, speaks, or writes.
                              Required and unset REFUSES; optional and unset
                              SKIPS that stop and says so.
  NARRATE                  -- Piper reads the stop guidance, best-effort.
  SETTLE + FENCE + CAPTURE -- guided_browser_capture opens the persistent,
                              visible browser and requires the human CAPTURE
                              token before writing artifacts.
  ADVANCE                  -- continue only after a successful capture receipt.

Connector execution is deliberately out of scope. This car captures context;
it does not run Jira, Botify, Gmail, or shell actuators.
"""

import argparse
import asyncio
import base64
import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = Path(__file__).resolve().parent

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import walk  # noqa: E402
import walk_cartridge  # noqa: E402

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _narrate(text, disclosed):
    """Speak scripted guidance if Piper is available; never gate the ride."""
    try:
        from imports.voice_synthesis import chip_voice_system
    except Exception as exc:
        print(f"  (voice import unavailable: {exc}) {text}")
        return disclosed

    if chip_voice_system is None:
        print(f"  (voice unavailable) {text}")
        return disclosed

    # THE NARRATION VANISHED WITH ITS OWN ERROR (convicted 2026-08-02, ride
    # five): the stop guidance reached the human ONLY inside a voice-failure
    # message. When the per-user lock fix made speak_text stop failing, the
    # printed text disappeared with the error that had been carrying it, and
    # the ride delivered NEITHER audio NOR words -- the NARRATE beat of the
    # kata became a silent no-op that reported success. Print first, then
    # speak, so the visible channel never depends on the audible one failing.
    print(f"  {text}")
    try:
        if not disclosed:
            result = chip_voice_system.speak_text(
                "This is the automated trail guide. I read each step aloud; "
                "you handle only the CAPTURE checkpoint at each stop. Any "
                "sign-in a stop needs is named in that stop's own guidance."
            )
            if isinstance(result, dict) and not result.get("success"):
                print(
                    "  (voice disclosure failed: "
                    f"{result.get('error', 'unknown error')})"
                )
            disclosed = True

        result = chip_voice_system.speak_text(text)
        if isinstance(result, dict) and not result.get("success"):
            print(
                "  (voice guidance failed: "
                f"{result.get('error', 'unknown error')})"
            )
    except Exception as exc:
        print(f"  (voice error, continuing: {exc}) {text}")

    return disclosed


def _capture_compatible(trail):
    """Return violations of guided_browser_capture's checked preconditions."""
    defaults = trail.get("defaults", {})
    required = {
        "headless": False,
        "persistent": True,
        "override_cache": True,
    }
    return [
        f"{key} must be {expected!r}; got {defaults.get(key)!r}"
        for key, expected in required.items()
        if defaults.get(key) is not expected
    ]


# --- DECANT: pour captured artifacts into one clipboard-ready payload --------
# Preview only: these lenses are frozen from the banked bytes, then capped.
# The full local captures.md is independent of these presentation limits.
# BANKED 2026-09-15 -- HANDOFF COVERAGE: name a requested lens that did not
# arrive; returned empty text is present, not missing. The private preview
# file and clipboard attempt receive the same checked string. The fixed
# filename denotes the last successful save, not the last attempted ride.
# NEXT RIDE -- THE FIRST FIVE MINUTES, ON RAILS (not implemented): disclose
# preview saving and clipboard replacement before choosing the real walk;
# complete after the final capture and existing checks without another word.
# Keep CAPTURE synchronization, archive integrity, caps, scrubbing, secret
# checks, private replacement and honest destination-specific failures.
# Change narration, public pages, launcher and completion labels together;
# move fingerprint/checkword exercises after completion. Frame practice as
# rehearsal. Explicitly scope shared/custom behavior: a private trail can
# shadow public_walk, so its name alone does not identify the bundled route.
DECANT_INLINE_KEYS = (
    "seo_md",
    "headers",
    "accessibility_tree_summary",
    "links_md",
    "diff_simple_txt",
    "optics_manifest",
)
DECANT_INLINE_CAP = 20000  # chars per inlined lens; the rest lives on disk
DECANT_PREVIEW_PATH = REPO_ROOT / "data" / "decant-preview.md"


def _capture_append(archive, record):
    """Append one framed JSON record; only a closed frame is a banked record."""
    body = json.dumps(record, ensure_ascii=True, indent=2)
    with archive["path"].open("a", encoding="utf-8", newline="\n") as stream:
        stream.write("\n--- START: Capture record ---\n```json\n" + body
                     + "\n```\n--- END: Capture record ---\n")
        stream.flush()
        os.fsync(stream.fileno())


def _bank_capture(archive, trail, index, stop, params, result):
    """Freeze returned file bytes before ADVANCE. No network or clipboard here.

    This is collection, not a second ZIP implementation. prompt_foo includes
    captures.md as an ordinary file and its existing core seals the disclosure.
    Coverage is exactly the returned file map, NOT every browser transaction.
    """
    if archive["path"] is None:
        parent = REPO_ROOT / "data" / "captures"
        parent.mkdir(parents=True, exist_ok=True)
        home = Path(tempfile.mkdtemp(prefix="walk-", dir=parent))
        path = home / "captures.md"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(
                "# Local capture archive\n\n"
                "UNSANITIZED. Keep local; review before any disclosure.\n"
                "Absent a closed complete status record, this run is PARTIAL.\n"
                "Ignore an unclosed trailing record; earlier closed records survive.\n"
                "This records returned files, not full HARs or all response bodies.\n"
            )
            stream.flush()
            os.fsync(stream.fileno())
        archive["path"] = path
        _capture_append(archive, {
            "kind": "run", "schema": "pipulate-captures-v1",
            "run_id": home.name, "status": "partial",
            "started_at": datetime.now(timezone.utc).isoformat(),
            "trail": trail,
        })
        print(f"  LOCAL ARCHIVE  {path}  (directory 0700, file 0600)")
    files, preview, problems = {}, {}, []
    for key, source in sorted(result.get("looking_at_files", {}).items()):
        entry = {"source_path": str(source), "status": "unavailable"}
        try:
            if not source:
                raise ValueError("empty source path")
            raw = Path(source).read_bytes()
            entry.update(status="ok", bytes=len(raw),
                         sha256=hashlib.sha256(raw).hexdigest())
            try:
                text = raw.decode("utf-8")
                entry.update(encoding="utf-8", content=text)
                if key in DECANT_INLINE_KEYS:
                    preview[key] = text[:DECANT_INLINE_CAP]
                    if len(text) > DECANT_INLINE_CAP:
                        preview[key] += "\n... [preview truncated; full bytes in captures.md]"
            except UnicodeDecodeError:
                entry.update(encoding="base64", content=base64.b64encode(raw).decode("ascii"))
        except (OSError, ValueError, TypeError) as exc:
            entry["error"] = f"{type(exc).__name__}: {exc}"
            problems.append(key)
        files[key] = entry
    if not files:
        problems.append("no returned files")
    _capture_append(archive, {
        "kind": "capture", "sequence": index, "stop": stop["name"],
        "banked_at": datetime.now(timezone.utc).isoformat(),
        "tool": "guided_browser_capture", "arguments": params,
        "requested_url": result.get("requested_url", params["url"]),
        "final_url": result.get("final_url"),
        "status": "incomplete" if problems else "banked",
        "problems": problems, "files": files,
    })
    archive["previews"].append(preview)
    return problems


def _write_walk_router(archive_path):
    """Replace one local selection; never read, disclose or compile its evidence."""
    selected = os.environ.get("PIPULATE_ADHOC_FILE", str(REPO_ROOT / "adhoc.txt"))
    if not selected.strip():
        raise ValueError("PIPULATE_ADHOC_FILE is empty")
    human = Path(selected).expanduser()
    if not human.is_absolute():
        human = REPO_ROOT / human
    target = human.with_name("adhocwalk.txt")
    # Derive beside the selected spelling; never follow a destination symlink.
    if (target.is_symlink() or target.resolve() == human.resolve()
            or (target.exists() and human.exists() and target.samefile(human))):
        raise ValueError("walk router aliases the human router or is a symlink")
    source = str(archive_path)
    # The existing router grammar has no escape for these separators.
    if (not Path(source).is_absolute() or source.splitlines() != [source]
            or "#" in source or "<--" in source):
        raise ValueError("capture path cannot be represented as one router file line")
    temp = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=target.parent,
            prefix=".adhocwalk-", delete=False,
        ) as stream:
            temp = Path(stream.name)
            os.fchmod(stream.fileno(), 0o600)
            stream.write(
                "# Generated: last completed nonempty capture run.\n"
                "# Replaced on completion; partial or empty runs leave this selection unchanged.\n"
                "# UNSANITIZED local evidence; review before disclosure or compilation.\n"
                f"{source}\n"
            )
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, target)
        temp = None
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)
    return target


def _finish_capture_archive(archive, status, skipped=()):
    """Finalize evidence first; a router failure must not block the later DECANT."""
    if archive["path"] is None or archive["finished"]:
        return
    _capture_append(archive, {
        "kind": "status", "status": status,
        "banked_captures": len(archive["previews"]),
        "skipped": list(skipped),
        "finished_at": datetime.now(timezone.utc).isoformat(),
    })
    archive["finished"] = True
    print(f"  ARCHIVE STATUS  {status}")
    _print_next_compile(archive["path"])
    if status == "complete" and archive["previews"]:
        try:
            target = _write_walk_router(archive["path"])
        except Exception as exc:
            print(f"  WALK ROUTER NOT UPDATED ({type(exc).__name__}): {exc}")
            print("  Archive preserved; any prior adhocwalk.txt still selects an earlier run.")
        else:
            print(f"  WALK ROUTER  {target}  (0600; UNSANITIZED; not compiled)")
    else:
        print("  WALK ROUTER unchanged: this run did not complete with captures.")
        print("  Any existing adhocwalk.txt still selects an earlier completed run.")


def _decant(captured, previews, skipped=()):
    """Build a capped preview from bytes frozen when each capture was banked.

    `skipped` is a list of (stop_name, var_name) for optional stops that never
    opened. They are LISTED, not silently absent: the reader downstream must
    be able to tell a baton that was never carried from one that was dropped.
    """
    parts = [
        "# Capture preview -- not the evidence archive",
        "",
        "Selected lenses frozen before ADVANCE; long lenses are truncated here.",
        "Original cache paths below are provenance, not preserved storage.",
        "The local captures.md holds the full returned bytes and coverage.",
        "",
    ]
    if skipped:
        parts.append("## Skipped stops (optional; URL not exported at ride time)")
        for stop_name, var_name in skipped:
            parts.append(
                f"- {stop_name}: {var_name} was unset; nothing opened, nothing captured"
            )
        parts.append("")
    for (stop_name, final_url, artifacts), preview in zip(captured, previews, strict=True):
        parts.append(f"## Stop: {stop_name}")
        parts.append(f"- final_url: {final_url}")
        parts.append("- artifacts on disk:")
        for key, path in sorted(artifacts.items()):
            parts.append(f"  - {key}: {path}")
        missing = [key for key in DECANT_INLINE_KEYS if key not in preview]
        if missing:
            parts.append("- missing preview lenses: " + ", ".join(missing))
        parts.append("")
        for key, text in preview.items():
            parts.append(f"### {stop_name} -- {key}")
            parts.append("```text")
            parts.append(text)
            parts.append("```")
            parts.append("")
    return "\n".join(parts)


# --- THE EGRESS BARRIER -----------------------------------------------------
# The per-stop CAPTURE token gates each WRITE TO DISK, on the operator's own
# machine. This gates EGRESS: a composite of authenticated material leaving the
# machine on the clipboard, with mck.sh then telling the human to paste it into
# a cloud chat. Different consequence class, therefore a different word.
#
# WHY NOT REUSE "CAPTURE": by the time this fires the human has typed CAPTURE
# once per stop. A fourth identical prompt is answered by MUSCLE MEMORY, not by
# decision -- and a fence satisfied by habit is not a fence. mck.sh already runs
# this grammar: INSTALL and RIDE are different words for different acts.
#
# NOT SKIPPABLE BY --yolo, and the argument is not merely that barriers are not
# skippable. (1) --yolo is typed at t=0, before a browser opens; it cannot
# consent to the disposition of material the consenter had not yet seen.
# (2) --yolo already blocks at every CAPTURE fence, so no unattended capability
# exists to lose. (3) The bypass-under-another-name corollary does NOT apply:
# _decant is the only builder of this composite and _ride_async its only caller,
# so a flag would not duplicate a shipped capability, it would create one.
DECANT_TOKEN = "DECANT"
def _print_artifact_homes(captured):
    """Name WHERE the captured material sits, not merely that it exists.

    CARGO, NOT BIBLIOGRAPHY. A refusal that says "your artifacts are safe" and
    does not say where is a refusal the human cannot act on.
    """
    print("   Full bytes are in the local archive printed above. Original cache homes:")
    for stop_name, _final_url, artifacts in captured:
        homes = sorted({os.path.dirname(p) for p in artifacts.values() if p})
        if not homes:
            print(f"     {stop_name}: (no artifact paths recorded)")
        for home in homes:
            print(f"     {stop_name}: {home}")
def _decant_checkpoint(payload, captured):
    """Refuse to release the bundle until a human types DECANT. Returns bool.

    THE ARMED LINE IS UNCONDITIONAL AND IT IS THE POINT. An armed gate that
    passes silently and a DISARMED gate both print nothing, so this announces
    its own state and the payload size on every ride before asking anything --
    the same shape prompt_foo's secrets tripwire uses for the same reason.

    THREE OUTCOMES, THREE STRINGS THAT ARE NEVER INTERCHANGEABLE, so a fence
    stuck shut is distinguishable from a fence correctly refusing:
      AUTHORIZED   the human typed the word       -> released
      DECLINED     the human typed anything else  -> withheld, paths printed
      REFUSED      nowhere to ask                 -> withheld, paths printed

    /dev/tty FIRST, the trick the CAPTURE prompt already learned: under
    `curl | bash` this process's stdin is the PIPE, so isatty(0) is the wrong
    question. mck.sh already hands the ride </dev/tty; this works either way.

    FAILS CLOSED ON NO TTY, and that is not a collision with THE FAIL-OPEN
    THRESHOLD RULE. That rule protects an ENTRY path where blocking would
    STRAND an unattended caller. This is an EXIT path: refusing does not block,
    it degrades, the artifacts are already durable, and the process still exits
    0 -- and a world with no terminal to ask on is by definition a world with
    no human waiting to paste a clipboard. Blocking on readline() is safe here
    for a stronger reason than the boot menu's isatty gate: three CAPTURE
    fences have already proved a human present.
    """
    payload_bytes = len(payload.encode("utf-8"))
    print(
        f"\n🔒 DECANT gate: ARMED -- {len(captured)} stop(s), "
        f"{payload_bytes:,} bytes assembled, still ON THIS MACHINE ONLY."
    )
    stream = None
    close_after = False
    try:
        stream = open("/dev/tty", "r", encoding="utf-8")
        close_after = True
    except OSError:
        if sys.stdin is not None and sys.stdin.isatty():
            stream = sys.stdin
    if stream is None:
        print("   REFUSED: nowhere to ask -- /dev/tty is unavailable and stdin")
        print("   is not a terminal. Nothing was copied.")
        _print_artifact_homes(captured)
        print("   Re-ride from a terminal to decant.")
        return False
    answer = ""
    try:
        print(
            f"   Type {DECANT_TOKEN} to save the checked preview and attempt its clipboard copy "
            "(anything else leaves any older preview unchanged)."
        )
        print(f"   {DECANT_TOKEN}> ", end="", flush=True)
        answer = stream.readline()
    except (OSError, KeyboardInterrupt):
        answer = ""
    finally:
        if close_after:
            stream.close()
    if answer.strip() != DECANT_TOKEN:
        print(f"\n   DECLINED by human (read {answer.strip()!r}). Nothing was copied.")
        _print_artifact_homes(captured)
        return False
    print(
        f"\n   AUTHORIZED by human: checking {payload_bytes:,} assembled bytes "
        "before the preview-file and clipboard attempts."
    )
    return _decant_to_clipboard(payload)
def _write_decant_preview(payload):
    """Atomically replace the private preview; never append or follow its old inode."""
    target = DECANT_PREVIEW_PATH
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=target.parent,
            prefix=".decant-", delete=False,
        ) as stream:
            temp = Path(stream.name)
            os.fchmod(stream.fileno(), 0o600)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, target)
        temp = None
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)
    return target


def _decant_to_clipboard(payload):
    """Check once, save locally, then attempt the existing clipboard handoff.

    Deferred import: prompt_foo drags tiktoken/pydot in at module load, so it is
    imported HERE, on a real DECANT only -- never on module import or
    --dry-narrate. Reuse over re-implement: copy_to_clipboard already owns the
    SSH-bridge and the pbcopy/xclip fallbacks.
    """
    from prompt_foo import copy_to_clipboard, scrub_compile_payload, scan_secrets
    # Reuse the existing baseline; DECANT has no disclosure-relaxation flags.
    scrubbed, substitutions, leaks = scrub_compile_payload(payload)
    secrets = scan_secrets(scrubbed)
    print(f"   DECANT checks: substitutions={substitutions} "
          f"denylist={sum(n for _, n in leaks)} secrets={len(secrets)}")
    if leaks or secrets:
        print("   BLOCKED: preview withheld; local evidence is unchanged.")
        return False
    # AFTER the human's word and baseline checks: one string, two destinations.
    try:
        target = _write_decant_preview(scrubbed)
    except OSError as exc:
        print(f"   LOCAL PREVIEW NOT UPDATED ({type(exc).__name__}): {DECANT_PREVIEW_PATH}")
        print("   Any older preview is unchanged; the clipboard attempt continues.")
    else:
        digest = hashlib.sha256(scrubbed.encode("utf-8")).hexdigest()
        print(f"   LOCAL PREVIEW {target} (0600; sha256={digest})")
    copy_to_clipboard(scrubbed)
    return True


# THE EXPORTS LOADER (2026-09-05, receipt-gated). bookmark_import.py writes
# one export line per stop into <name>.exports.sh beside <name>.walk.md and
# refuses any path git does not ignore; walk_compile.py puts <name>.yaml
# beside both. So the file a trail needs is a pure function of the trail's
# own path -- THE DERIVED-PATH RULE -- and nothing had to be told. Until now
# nothing READ it either: the human sourced it by hand, or did not, and
# PRE-FLIGHT refused. THREE RUNGS, FIRST HIT WINS: an explicit --exports path
# (a miss is a REFUSAL, because the human named it); the derived sibling (a
# miss is silence, because nothing promised it); nothing.
# ENVIRONMENT OVER FILE, the precedence wallet.py's _check_env spells for the
# live board: an exported, non-empty variable is kept. "Non-empty" is the
# same test _missing_url_envs applies, so the loader fills exactly the set
# PRE-FLIGHT would otherwise refuse on, and nothing else changes hands.
# python-dotenv reads the `export NAME='value'` shape bookmark_import writes
# (probe-witnessed 2026-09-05: prefix stripped, value intact). Imported
# lazily, so a ride that resolves no file pays nothing for it.
def _resolve_exports(trail_path, explicit=None):
    """The exports file for this ride, or None when nothing resolves.

    An explicit path is returned whether or not it exists, so the caller can
    refuse BY NAME; a derived sibling is returned only when it is a file.
    Relative explicit paths anchor to the repository root, exactly as the
    trail argument does (UNNAMED-ROOT RULE), never to the current directory.
    """
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_absolute():
            path = REPO_ROOT / path
        return path
    sibling = trail_path.with_name(trail_path.stem + ".exports.sh")
    return sibling if sibling.is_file() else None


def _load_exports(path):
    """Layer one exports file UNDER os.environ. Returns (filled, kept) names."""
    from dotenv import dotenv_values
    filled = []
    kept = []
    for name, value in dotenv_values(path).items():
        if value is None:
            continue
        if os.environ.get(name, "").strip():
            kept.append(name)
        else:
            os.environ[name] = value
            filled.append(name)
    return filled, kept


def _missing_url_envs(stops):
    """Every url_env the WHOLE walk names that the environment lacks, in stop order.

    Returns (required, optional), each [(stop_name, var_name), ...], one entry
    per stop that is short a URL, so a variable two stops share is named
    beside each stop that needs it: the human reads what the walk will do,
    not a deduplicated set. An exported empty or whitespace-only string counts
    as unset, matching walk.build_plan -- an empty export opens nothing.

    TWO LISTS, TWO VERDICTS (2026-09-02). A walk is a linear pipeline and not
    every stop carries the baton. A required stop that is unset refuses the
    whole ride at t=0; an optional stop that is unset is SKIPPED and the ride
    proceeds. The Jira issue is required; the customer's Botify project is
    not, and a ticket with no project must still be walkable.
    """
    required = []
    optional = []
    for stop in stops:
        url_env = stop.get("url_env")
        if url_env and not os.environ.get(url_env, "").strip():
            bucket = optional if stop.get("optional") else required
            bucket.append((stop["name"], url_env))
    return required, optional


def _announce_consent(trail_path):
    """Print what the WHOLE walk demands, before stop one, plus the DECANT.
    IMPORTED, NEVER DUPLICATED, AND THE DIRECTION OF THE ARROW IS THE ARGUMENT.
    walk_cartridge.py duplicates foo_cartridge.py's primitives because a
    clean-room consumer must be able to fetch ONE file and verify a cartridge.
    That constraint governs what walk_cartridge may IMPORT; it says nothing
    about what may import walk_cartridge. mother_cat.py already imports walk,
    scraper_tools, voice_synthesis and (deferred) prompt_foo -- it is in-repo by
    construction and can never be fetched standalone -- so this import costs the
    single-file property nothing, and walk_cartridge still imports only stdlib.
    Duplicating here would be the actual error. A second implementation can
    drift, and on the day it does, the surface a human CONSENTS to and the
    surface the manifest ATTESTS to disagree, so the seal would be signing a
    projection nobody was ever shown. One derivation, or the seal means nothing.
    Derived from the trail's BYTES, not from walk.load_trail's validated dict,
    so what is spoken here is provably what a sealer would hash.
    THIS IS A DISCLOSURE, NOT A FENCE. Nothing is gated. The ruling is banked
    beside the call site.
    """
    try:
        surface = walk_cartridge._derive_consent_surface(trail_path.read_bytes())
    except (OSError, ValueError) as exc:
        # FAIL SOFT AND LOUD. walk.load_trail has already validated this file
        # far more strictly than this projection does, so a refusal HERE means
        # two authorities disagree about one file. That is information worth
        # printing, not a reason to abort a ride the planner already blessed.
        print(f"  (consent surface unavailable: {exc})")
        return
    browser = surface["browser"]
    rule = "=" * 66
    print(rule)
    print(f" THIS WALK: {surface['name']} -- {len(surface['stop_names'])} stop(s)")
    print(rule)
    print(f" stops, in order    {', '.join(surface['stop_names'])}")
    # SHOW the direct URLs rather than hide them. A card that will not say
    # where it is taking you is worse than one that does, and these are the
    # public case by construction: a trail carrying a client address never
    # gets past walk_compile.py, which refuses any compiled trail containing
    # a scheme separator. Each line prints only when it has content, so a
    # single-lane trail never shows an empty row.
    if surface.get("direct_urls"):
        print(f" it opens directly  {', '.join(surface['direct_urls'])}")
    if surface.get("url_envs"):
        print(f" URLs YOU supply    {', '.join(surface['url_envs'])}")
    # Same derivation, one more row. Unset here SKIPS a stop and says so in
    # the PRE-FLIGHT above; unset in the row above REFUSES the ride.
    if surface.get("optional_url_envs"):
        print(f" optional, if set   {', '.join(surface['optional_url_envs'])}")
    print(f" names as runnable  {', '.join(surface['connector_scripts'])}")
    print(
        f" browser profile    {browser['profile_name']!r}"
        f"  (persistent={browser['persistent']}, headless={browser['headless']})"
    )
    print(rule)
    print(" CAPTURE saves each stop locally; captures may include account details.")
    print(f" {DECANT_TOKEN} authorizes a checked preview file and a clipboard attempt.")
    print(f" Preview in workshop: {DECANT_PREVIEW_PATH.relative_to(REPO_ROOT)} (private; replaced on save).")
    print(" Declining or failing checks leaves any previous preview unchanged.")
    print(" Nothing is uploaded automatically. The preview is trimmed.")
    print(" Review before sharing; checks can miss sensitive data.")
    print(rule)
    print("")
# The router receives a stable capture file, never an @URL cache lookup.
def _print_next_compile(archive_path):
    """Print one self-contained file line, never mutable @URL cache selectors."""
    print("\nLocal archive file line for context.md or adhoc.txt:")
    print(archive_path)
    print("Review locally before compiling; raw bytes are not a safe disclosure.")

async def _ride_async(trail_path, dry_narrate=False, exports_path=None):
    archive = {"path": None, "finished": False, "previews": []}
    try:
        return await _ride_steps(trail_path, archive, dry_narrate, exports_path)
    finally:
        # Exceptions, cancellation and capture failures cannot promote a run.
        # Even an uncatchable kill leaves the initial PARTIAL statement intact.
        _finish_capture_archive(archive, "partial", archive.get("skipped", ()))


async def _ride_steps(trail_path, archive, dry_narrate=False, exports_path=None):
    trail_path = Path(trail_path)
    trail = walk.load_trail(trail_path)

    problems = _capture_compatible(trail)
    if problems and not dry_narrate:
        print("REFUSING TO RIDE -- trail defaults are not capture-compatible:")
        for problem in problems:
            print(f"  - {problem}")
        return 2
    if problems:
        # A rehearsal that stays silent about a refusal it can already see is
        # a rehearsal for a flight that will not be permitted. Naming it here
        # costs nothing; discovering it at the browser costs the newcomer's
        # first sixty seconds. ATTRIBUTED-VOICE: narration may not imply a
        # capability the next step will withhold.
        print("NOTE -- a real ride of this trail would be REFUSED:")
        for problem in problems:
            print(f"  - {problem}")
        print("  (--dry-narrate continues anyway; nothing will open.)")

    # EXPORTS, BEFORE PRE-FLIGHT, UNDER --dry-narrate TOO: the rehearsal must
    # disclose the ride it rehearses, not a bare shell's. THE LINE PRINTS
    # ONLY WHEN A FILE WAS READ, and it prints a path and two counts -- the
    # names ride on the consent card and the values ride nowhere.
    exports_file = _resolve_exports(trail_path, exports_path)
    if exports_file is not None:
        if not exports_file.is_file():
            print(f"REFUSING TO RIDE -- --exports names a file that is not there: {exports_file}")
            print("  Relative paths resolve from the repository root, never from where you stand.")
            print("  Nothing opened, nothing was spoken, nothing was written.")
            return 2
        filled, kept = _load_exports(exports_file)
        print(f"EXPORTS  {exports_file}")
        print(
            f"  {len(filled)} set from the file; {len(kept)} already exported "
            "and kept (environment wins)."
        )
        print("")
    # PRE-FLIGHT (2026-09-01, the ticket ride that died at stop two). A trail
    # declares every URL it needs before it opens anything, so the rider can
    # know at t=0 whether it can finish -- and it used to find out one stop at
    # a time. ticket.yaml captured the Jira issue, ADVANCED, and only then
    # discovered PIPULATE_TRAIL_BOTIFY_URL was unset; on the Mac the first
    # refusal came AFTER a sixty-megabyte voice download and the spoken
    # guidance for a stop that would never open. A walk that can fail at its
    # last stop for a reason knowable at its first wastes the human's
    # captures, and a long walk would waste many. mck.sh already runs this
    # check in shell, but `mothercat` is the direct alias and the Mac path,
    # and neither passes through mck.sh, so the rider owns it too: EVERY
    # missing variable, named beside its stop, with the export line to type,
    # before narration, before the consent card, before any browser. Under
    # --dry-narrate it is disclosed and not enforced, same as the capture
    # problems above: the rehearsal mck.sh forces on first contact must be
    # able to run in a shell that has exported nothing yet.
    # OPTIONAL FIRST, AS A DISCLOSURE: the skips are named before any refusal
    # so the human reads the whole shape of the ride in one screen. A skipped
    # stop is not a failure and does not read like one.
    missing_envs, optional_missing = _missing_url_envs(trail["stops"])
    skip_vars = dict(optional_missing)
    if optional_missing:
        print("SKIPPING optional stop(s) -- their URLs are not in your environment:")
        for stop_name, var_name in optional_missing:
            print(f"  - stop {stop_name!r} is optional; {var_name} is unset, so it will be SKIPPED")
        print("  Export it and ride again to include that stop.")
        print("")
    if missing_envs:
        if dry_narrate:
            print("NOTE -- a real ride of this trail would be REFUSED before stop one:")
        else:
            print("REFUSING TO RIDE -- this walk needs URLs your environment does not have:")
        for stop_name, var_name in missing_envs:
            print(f"  - stop {stop_name!r} needs {var_name}")
        print("  Export each one, then ride again:")
        seen = set()
        for _stop_name, var_name in missing_envs:
            if var_name in seen:
                continue
            seen.add(var_name)
            print(f"    export {var_name}='https://...'")
        if dry_narrate:
            print("  (--dry-narrate continues anyway; nothing will open.)")
        else:
            print("  Nothing opened, nothing was spoken, nothing was written.")
            return 2
    guided_browser_capture = None
    if not dry_narrate:
        from tools.scraper_tools import guided_browser_capture
        # QUIET ON SUCCESS, LOUD ON FAILURE (2026-09-01, the first real ride).
        # scraper_tools narrates every step through loguru at INFO, and this
        # rider ALREADY narrates the ride in its own voice -- the spoken
        # guidance, the CAPTURE prompt, the "Captured. final_url=" receipt --
        # so the first jira_for_you ride printed fifteen INFO lines saying
        # what the rider had just said. Two narrators, one story. The floor
        # moves to WARNING for the ride only: provenance fallbacks, driver
        # failures and CDP misses still print, because those change what the
        # capture MEANS. PIPULATE_RIDE_LOG=INFO restores the chatter when a
        # ride needs debugging. print() output is untouched: the wait message
        # and both fences ride on it, and it is the human's channel.
        try:
            from loguru import logger as _ride_log
            _ride_log.remove()
            _ride_log.add(
                sys.stderr,
                level=os.environ.get("PIPULATE_RIDE_LOG", "WARNING"),
            )
        except Exception:
            pass

    stops = trail["stops"]
    print(f"Riding trail '{trail['name']}' -- {len(stops)} stop(s).\n")
    # DISCLOSURE, NOT A FENCE, AND THAT IS THE RULING RATHER THAN AN OVERSIGHT.
    # mck.sh owns the practice/real-walk choice. CEREMONY IS SKIPPABLE;
    # BARRIERS ARE NOT: each CAPTURE and DECANT remain in the rider.
    # This surface prints on both paths; practice does not authorize a ride.
    # THE DECANT FENCE LANDED, so this comment's earlier claim that nothing
    # gated the clipboard is RETIRED rather than merely outdated. What the call
    # buys NOW is disclosure BEFORE the material exists: the rider learns at t=0
    # that DECANT is a separate choice and that its checked preview still
    # needs review, before either the file or clipboard is attempted.
    # SAME-CAR LABEL RULE, PAID LATE AND THEREFORE WORTH BANKING. The fence and
    # the strings describing it shipped in DIFFERENT rides, so for one ride this
    # function told every rider "WITHOUT ASKING AGAIN" about a gate that does
    # ask, and public_walk.yaml's third stop said the same thing in trail data.
    # That is not stale documentation; it is a lie told at the exact moment the
    # human decides, and it lied in the EXPENSIVE direction -- understating the
    # protection and overstating the risk, to a newcomer, on the softball walk.

    # THE DESCRIPTION SPEAKS FIRST (2026-09-05). walk.py has validated
    # trail.description as non-empty since Car A, and nothing read it at
    # ride time: not the guidance loop, not the consent card, not the
    # sealed surface. A required field nothing collected. It is the walk's
    # opening sentence, spoken once before the card in the same voice the
    # stops use, and under --dry-narrate too, so the rehearsal opens the
    # way the ride does. The return value carries the one-time disclosure
    # forward, so the guide introduces itself exactly once.
    disclosed = _narrate(trail["description"], False)
    _announce_consent(trail_path)
    captured = []
    skipped = archive.setdefault("skipped", [])
    for index, stop in enumerate(stops, 1):
        print(f"--- Stop {index}/{len(stops)}: {stop['name']} ---")

        # SKIP BEFORE NARRATE. Speaking the guidance for a stop that will not
        # open is the Mac conviction in miniature: voice spent on nothing.
        # Printed under --dry-narrate too, so the rehearsal has the shape of
        # the ride it rehearses.
        if stop["name"] in skip_vars:
            print(
                f"  SKIPPED -- optional stop; {skip_vars[stop['name']]} is unset. "
                "Nothing opened.\n"
            )
            skipped.append((stop["name"], skip_vars[stop["name"]]))
            continue

        disclosed = _narrate(stop["guidance"], disclosed)

        if dry_narrate:
            print("  (dry-narrate: browser and capture skipped)\n")
            continue

        # A stop carries exactly one of `url` or `url_env`. The PRE-FLIGHT
        # above has already checked every url_env for a real ride, so this
        # branch is the belt to those braces: it can only fire if the
        # environment changed under a running ride. The message is unchanged.
        url = stop.get("url")
        if url is None:
            url_env = stop["url_env"]
            try:
                url = os.environ[url_env]
            except KeyError as exc:
                raise walk.TrailError(
                    f"stop {stop['name']!r} requires environment variable {url_env}"
                ) from exc

        params = walk._browser_params(url, trail["defaults"])
        result = await guided_browser_capture(
            params,
            stdin=sys.stdin,
            stdout=sys.stdout,
        )

        if not result.get("success"):
            print(
                f"  CAPTURE failed at {stop['name']!r}: "
                f"{result.get('error', 'no receipt')}"
            )
            print("  Halting -- no ADVANCE without a capture receipt.\n")
            if captured:
                # Work already banked is EVIDENCE, and evidence is not
                # discarded because a later stop failed. The bundle is
                # still withheld -- a partial ride must never be mistaken
                # for a complete one -- but the human is told what exists
                # and where, rather than being left to assume it vanished.
                print("  Stops banked BEFORE this failure (full bytes in captures.md):")
                for banked_name, banked_url, banked_artifacts in captured:
                    print(
                        f"    - {banked_name}: {banked_url} "
                        f"({len(banked_artifacts)} artifacts)"
                    )
                print("  No preview released. The partial archive is preserved locally.\n")
            return 1

        artifacts = result.get("looking_at_files", {})
        problems = _bank_capture(archive, trail, index, stop, params, result)
        captured.append((stop["name"], result.get("final_url"), artifacts))
        if problems:
            print("  ARCHIVE INCOMPLETE: " + ", ".join(problems))
            print("  Details are banked locally; halting without ADVANCE or DECANT.")
            return 1
        print(
            f"  Captured. final_url={result.get('final_url')} "
            f"artifacts={len(artifacts)}"
        )

        if index < len(stops):
            print("  ADVANCE -> next stop.\n")

    if dry_narrate:
        print("\nDry narration complete; no captures were attempted.")
        return 0

    _finish_capture_archive(archive, "complete", skipped)
    # ATTRIBUTED-VOICE: "every stop produced a capture receipt" is only true
    # when nothing was skipped, so the line says which world it is in.
    if skipped:
        print(
            f"\nRide complete. {len(captured)} of {len(stops)} stop(s) captured; "
            f"{len(skipped)} optional stop(s) skipped for an unset URL."
        )
    else:
        print("\nRide complete. Every stop produced a capture receipt.")
    if captured:
        payload = _decant(captured, archive["previews"], skipped)
        decanted = _decant_checkpoint(payload, captured)
        # ATTRIBUTED-VOICE, fixed in passing because these are the exact lines
        # being rewritten: the old text asserted "copied to your clipboard"
        # UNCONDITIONALLY, one statement after calling a function that swallows
        # every clipboard failure and returns None -- a verb naming an act no
        # code in this file performed. copy_to_clipboard prints its own success
        # or warning line; this reports only what IT witnessed, which is the
        # human's authorization.
        if decanted:
            print("   Review the preview before sharing it with a chatbot.")
            print("   Ask it to separate what the files show from what it infers.")
        # The archive file line was printed when its status was banked.
    return 0


def ride(trail_path=None, dry_narrate=False, exports_path=None):
    """Run one validated trail to completion and return a process exit code."""
    if trail_path is None:
        path = walk.DEFAULT_TRAIL
    else:
        path = Path(trail_path)
        if not path.is_absolute():
            # Mirror walk.main(): repo-root-anchored, never CWD-dependent.
            # A relative trail typed through the flake's `mothercat` alias
            # must resolve identically from any directory (UNNAMED-ROOT).
            path = REPO_ROOT / path
    return asyncio.run(
        _ride_async(path, dry_narrate=dry_narrate, exports_path=exports_path)
    )


class CaptureDisclosureError(ValueError):
    """A refusal carrying only fixed, content-free diagnostics."""


# Selected text lenses, including the simplified-HTML diff; not raw HTML files,
# network logs, headers or binary artifacts.
CAPTURE_DISCLOSURE_TEXT_KEYS = frozenset((
    "seo_md", "links_md", "accessibility_tree_summary", "diff_simple_txt",
))


def _capture_disclosure(raw, scrub, scan):
    """Build a local review derivative, never a certificate of safe disclosure.

    Verify original bytes before selecting content. Apply the existing text
    policy to DECODED strings, then hash the disclosed strings separately.
    Unhandled lenses remain represented by explicit omission receipts.
    """
    if len(raw) > 64 * 1024 * 1024:
        raise CaptureDisclosureError("capture exceeds disclosure limit")
    opening = "\n--- START: Capture record ---\n```json\n"
    closing = "\n```\n--- END: Capture record ---\n"
    header, *chunks = raw.decode("utf-8").split(opening)
    if not header.startswith("# Local capture archive\n") or not chunks:
        raise CaptureDisclosureError("not a capture archive")
    records = []
    for chunk in chunks:
        body, marker, tail = chunk.partition(closing)
        if not marker or tail.strip():
            raise CaptureDisclosureError("incomplete or malformed capture frame")
        record = json.loads(body, object_pairs_hook=walk_cartridge._reject_duplicate_json_keys)
        if not isinstance(record, dict):
            raise CaptureDisclosureError("capture record is not an object")
        records.append(record)
    if records[0].get("kind") != "run" or records[0].get("schema") != "pipulate-captures-v1":
        raise CaptureDisclosureError("unsupported capture schema")
    status = records[-1] if records[-1].get("kind") == "status" else None
    captures = records[1:-1] if status else records[1:]
    if status and (status.get("status") not in ("partial", "complete")
                   or status.get("banked_captures") != len(captures)):
        raise CaptureDisclosureError("inconsistent capture status")
    known = CAPTURE_DISCLOSURE_TEXT_KEYS | set(DECANT_INLINE_KEYS) | {
        "network_log", "source_html", "hydrated_dom", "accessibility_tree", "screenshot",
    }
    result = {
        "schema": "pipulate-capture-disclosure-v1",
        "policy": "review-text-v1",
        "review_required": True,
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "source_status": status["status"] if status else "partial",
        "source_records": len(records), "capture_count": len(captures),
        "metadata_omitted": ["trail", "arguments", "urls", "stop_names",
                             "source_paths", "raw_errors", "timestamps", "unknown_fields"],
        "text_keys": sorted(CAPTURE_DISCLOSURE_TEXT_KEYS),
        "files": [],
    }
    previous = 0
    for record_index, capture in enumerate(captures, 2):
        sequence = capture.get("sequence")
        if (capture.get("kind") != "capture" or type(sequence) is not int
                or sequence <= previous or not isinstance(capture.get("files"), dict)
                or capture.get("status") not in ("banked", "incomplete")):
            raise CaptureDisclosureError("invalid capture record")
        previous = sequence
        if result["source_status"] == "complete" and (
                capture["status"] != "banked" or not capture["files"]):
            raise CaptureDisclosureError("complete run contains incomplete capture")
        for file_index, (key, entry) in enumerate(capture["files"].items(), 1):
            row = {
                "source_record": record_index, "source_file": file_index,
                "sequence": sequence, "lens": key if key in known else "unlisted",
                "action": "omitted", "reason": "source_unavailable",
                "original_sha256": None, "original_bytes": None,
                "disclosed_sha256": None, "disclosed_bytes": None,
            }
            result["files"].append(row)
            if not isinstance(entry, dict) or entry.get("status") not in ("ok", "unavailable"):
                raise CaptureDisclosureError("invalid file receipt")
            if entry["status"] == "unavailable":
                if capture["status"] == "banked":
                    raise CaptureDisclosureError("banked capture contains unavailable file")
                continue
            content, encoding = entry.get("content"), entry.get("encoding")
            if not isinstance(content, str) or encoding not in ("utf-8", "base64"):
                raise CaptureDisclosureError("unsupported stored encoding")
            original = content.encode("utf-8") if encoding == "utf-8" else base64.b64decode(content, validate=True)
            digest = hashlib.sha256(original).hexdigest()
            if (type(entry.get("bytes")) is not int or len(original) != entry["bytes"]
                    or digest != entry.get("sha256")):
                raise CaptureDisclosureError("original content failed length or digest check")
            row.update(original_sha256=digest, original_bytes=len(original))
            if encoding == "base64":
                row["reason"] = "binary_not_supported"
                continue
            if key not in CAPTURE_DISCLOSURE_TEXT_KEYS:
                row["reason"] = "lens_outside_policy"
                continue
            disclosed, substitutions, leaks = scrub(original.decode("utf-8"))
            secret_hits = scan(disclosed)
            row["checks"] = {"substitutions": substitutions,
                             "denylist_hits": sum(n for _, n in leaks),
                             "secret_hits": len(secret_hits)}
            if leaks or secret_hits:
                row["reason"] = "text_policy_blocked"
                continue
            disclosed_bytes = disclosed.encode("utf-8")
            row.update(action="transformed" if disclosed_bytes != original else "retained",
                       reason="baseline_text_checks", content=disclosed, encoding="utf-8",
                       disclosed_sha256=hashlib.sha256(disclosed_bytes).hexdigest(),
                       disclosed_bytes=len(disclosed_bytes))
    return result


def _disclose_capture(source):
    """Write a separate private candidate. No ride, router edit or clipboard."""
    import contextlib
    import io
    import prompt_foo as compiler

    source = Path(source).expanduser()
    if not source.is_absolute():
        source = REPO_ROOT / source
    if source.name != "captures.md":
        raise CaptureDisclosureError("expected the original captures.md")
    with source.open("rb") as stream:
        raw = stream.read(64 * 1024 * 1024 + 1)
    def policy_inputs():
        paths = {"substitutions": compiler.PII_SUBSTITUTIONS_FILE,
                 "denylist": compiler.COMMIT_DENYLIST_FILE,
                 "compiler": Path(compiler.__file__), "discloser": Path(__file__)}
        return {key: hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
                for key, path in paths.items()}
    inputs = policy_inputs()
    diagnostics = io.StringIO()
    with contextlib.redirect_stdout(diagnostics):
        result = _capture_disclosure(raw, compiler.scrub_compile_payload, compiler.scan_secrets)
    if "Skipping bad" in diagnostics.getvalue():
        raise CaptureDisclosureError("invalid configured policy pattern")
    if inputs != policy_inputs():
        raise CaptureDisclosureError("policy changed during disclosure")
    result["policy_inputs_sha256"] = inputs
    result["policy_diagnostic_lines"] = len(diagnostics.getvalue().splitlines())
    data = (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    target = source.with_name("captures.disclosed.json")
    # Stage privately, then link into place without overwriting any destination.
    # An identical destination is reused; changed policy needs a new review.
    with tempfile.NamedTemporaryFile(dir=source.parent, prefix=".disclosure-", delete=False) as stream:
        temp = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            temp.unlink(missing_ok=True)
            raise
    try:
        try:
            os.link(temp, target)
        except FileExistsError:
            if (target.is_symlink() or not target.is_file()
                    or target.stat().st_size != len(data)
                    or target.stat().st_mode & 0o777 != 0o600
                    or target.read_bytes() != data):
                raise CaptureDisclosureError("disclosure destination exists with different content") from None
    finally:
        temp.unlink(missing_ok=True)
    counts = {action: sum(f["action"] == action for f in result["files"])
              for action in ("retained", "transformed", "omitted")}
    print("DISCLOSURE_CANDIDATE " + " ".join(f"{key}={value}" for key, value in counts.items())
          + " review_required=True sha256=" + hashlib.sha256(data).hexdigest())
    print(f"LOCAL FILE  {target}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Mother Cat Car B: actuate a validated trail."
    )
    parser.add_argument(
        "trail",
        nargs="?",
        default=None,
        help=(
            "trail path (default: walk.DEFAULT_TRAIL, the zero-auth "
            "public_walk softball). Expert, authenticated: "
            "assets/trails/first_context.yaml"
        ),
    )
    parser.add_argument(
        "--dry-narrate",
        action="store_true",
        help="narrate each stop without opening a browser or capturing",
    )
    parser.add_argument(
        "--exports",
        default=None,
        metavar="PATH",
        help=(
            "exports file to layer UNDER the environment before PRE-FLIGHT "
            "(default: <trail>.exports.sh beside the trail, if it exists); "
            "a relative PATH anchors to the repository root"
        ),
    )
    parser.add_argument("--disclose", metavar="CAPTURES_MD",
                        help="write a private review-text disclosure; no browser or clipboard")
    args = parser.parse_args(argv)
    if args.disclose is not None:
        if args.trail or args.dry_narrate or args.exports:
            parser.error("--disclose cannot be combined with ride arguments")
        try:
            return _disclose_capture(args.disclose)
        except CaptureDisclosureError as exc:
            print(f"DISCLOSURE REFUSED: {exc}. Source unchanged.")
            return 2
        except Exception as exc:
            print(f"DISCLOSURE REFUSED ({type(exc).__name__}); source unchanged. "
                  "Check local input and policy; no content printed.")
            return 2

    try:
        return ride(args.trail, dry_narrate=args.dry_narrate, exports_path=args.exports)
    except walk.TrailError as exc:
        print(f"TRAIL INVALID (Car A refused): {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
