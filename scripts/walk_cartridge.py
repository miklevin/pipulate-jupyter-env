#!/usr/bin/env python3
"""
walk_cartridge.py -- the sealed, immutable form of a Mother Cat trail.

Schema: walk-cartridge-integrity-v3. Stdlib only. Single file by design.

WHY THIS DOES NOT IMPORT scripts/foo_cartridge.py
-------------------------------------------------
That file's own docstring states the constraint this one inherits: "A
clean-room consumer can fetch this single file and verify or rebuild a
cartridge with nothing but the Python standard library." Two files is not one
file. So the canonicalization primitives below are DUPLICATED, deliberately,
per the WET doctrine -- Write Everything Twice, on purpose, for a stated
reason.

The cost is named rather than hidden: a ZIP-metadata bug found here must be
fixed in two places, and the second fix can be forgotten. The mitigation is
that what forks is small and the forked part is the SCHEMA, not the physics.
The primitives (_sha256_hex, _canonical_json_bytes, _canonical_zip_info,
_reject_duplicate_json_keys) are pure and schema-blind; the member tuple, the
derivation rule, and the verify entry point are what differ.

WHY A SECOND SCHEMA RATHER THAN A GENERALIZED foo_cartridge
-----------------------------------------------------------
1. foo_cartridge's payload->prompt derivation is not a convenience, it is the
   schema's identity. Generalizing it means a branch; with one caller that
   branch always goes the same way and is untested by construction -- the
   SINGLE-CANDIDATE BLINDNESS failure, in the one file whose entire value is
   being unconditional.
2. replay.sh pins foo_cartridge.py BY SHA-256 (CORE_SHA256). Editing the
   verifier invalidates that pin. Building the walk lane by first breaking the
   pinning mechanism it will depend on is backwards.
3. Opposite mutability, per GLOSSARY.md's NAME RULING: a context cartridge is
   a snapshot of evidence; a walk cartridge is a sealed program that will
   actuate a browser on a stranger's machine. One verifier for both means one
   bug class crosses between them.

MEMBERS (exactly two, in this order)
------------------------------------
  trail.yaml     the JSON-subset-of-YAML trail, BYTE-IDENTICAL to source
  manifest.json  sha256 of trail.yaml + the CONSENT SURFACE derived from it

THE CONSENT SURFACE is the analogue of payload->prompt: a projection a human
reads BEFORE deciding to ride, recomputed by the verifier from trail.yaml and
required to match exactly, so it cannot drift from the bytes it describes.

  name              the trail's own name
  stop_names        ORDERED, never sorted. Sequence is the one property a
                    replayable artifact exists to preserve, and walk.py
                    already enforces uniqueness, so sorting buys no dedup and
                    costs the ride order.
  direct_urls       ORDERED, never sorted, and present unconditionally --
                    empty list and all -- so the surface has ONE shape a human
                    can learn to read at a glance. A stop may carry a literal
                    `url` instead of a `url_env`; these are those, in ride
                    order, for the same reason stop_names is ordered.
  url_envs          SORTED. These are a SET: the walk DEMANDS all of them,
                    order-free, and mck.sh prints them as a checklist. Since
                    v3 this is the REQUIRED set only.
  optional_url_envs SORTED. Present unconditionally, empty list and all. An
                    unset one SKIPS its stop instead of refusing the ride
                    (walk.py `optional: true`). A variable named by both a
                    required and an optional stop is required, and is listed
                    once, under url_envs.
  connector_scripts SORTED, unique. Car B does not execute connectors today;
                    walk.py's build_plan already constructs their argv, and a
                    consent surface omitting the executable half is not one.
  browser           headless / persistent / override_cache / profile_name.
                    mother_cat._capture_compatible checks the first three and
                    NOT profile_name -- which selects WHICH logged-in browser
                    profile the ride opens. Surfacing it costs one line.

WHAT THIS DELIBERATELY IS NOT: a validator. walk.py owns the seven-key exact
set-difference check, the regex compile, the {harvested} placeholder count,
and the read_only force. Re-implementing any of it here would mint a second
authority for the trail schema. This module DERIVES, REFUSES on a shape it
cannot derive from, and adjudicates nothing. Run walk.py against a trail
before sealing it.

WHAT A HASH DOES NOT BUY: authorship. A malicious trail with a perfect digest
verifies GREEN forever, by construction. Per THE RECEIPT LADDER RULE, a
signature is a different rung and is owed separately (MANIFEST-SIGNING LANE).
And a digest fetched from the same host as its bytes is a checksum, not a
seal: the digest must arrive out of band.

NO WALL-CLOCK VALUE ENTERS THE HASHED BODY. Identical trail bytes produce
identical archive bytes, forever, which is what makes content addressing work.

USAGE
-----
  python scripts/walk_cartridge.py seal assets/trails/*.yaml
  python scripts/walk_cartridge.py verify data/walks/<sha256>/walk.zip
  python scripts/walk_cartridge.py show   data/walks/<sha256>/walk.zip

Sealed cartridges land at data/walks/<archive_sha256>/walk.zip. The path is a
pure function of the content -- THE DERIVED-PATH RULE made literal, so a
collision is unrepresentable and re-sealing is idempotent. data/ is already
gitignored wholesale.

Exit codes: 0 all good | 2 refusal (any cartridge or trail rejected).
"""

import argparse
import hashlib
import io
import json
import os
import sys
import tempfile
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# v2 (2026-08-25): the consent surface gained direct_urls, because a stop may
# now carry a literal `url` instead of a `url_env`. That changes manifest.json
# bytes for EVERY trail, including trails with zero direct URLs, so every
# cartridge sealed under v1 is invalidated. data/ is gitignored, so nothing
# tracked or published breaks. Re-seal with
#   .venv/bin/python scripts/walk_cartridge.py seal assets/trails/*.yaml
# Re-sealing WRITES A NEW content-addressed cartridge under a new digest. It
# does not upgrade the old one, which stays on disk and stays red until pruned.
# v3 (2026-09-02): the consent surface gained optional_url_envs, and url_envs
# narrowed to the REQUIRED set. Emitted unconditionally, so manifest.json bytes
# change for EVERY trail again, including trails with no optional stop -- the
# same invalidation v2 caused, for the same reason: ONE SHAPE beats a
# conditional key. Byte-for-byte reproduction holds WITHIN a schema, never
# across one. Re-seal as above; v1 and v2 cartridges stay red until pruned.
WALK_CARTRIDGE_SCHEMA_V1 = "walk-cartridge-integrity-v1"
WALK_CARTRIDGE_SCHEMA_V2 = "walk-cartridge-integrity-v2"
WALK_CARTRIDGE_SCHEMA = "walk-cartridge-integrity-v3"
WALK_CARTRIDGE_MEMBERS = ("trail.yaml", "manifest.json")
WALK_CARTRIDGE_SOURCE_EPOCH = 1767225600
WALK_CARTRIDGE_ZIP_TIME = (2026, 1, 1, 0, 0, 0)
WALK_CARTRIDGE_FILE_MODE = 0o100644 << 16
WALK_CACHE_ROOT = REPO_ROOT / "data" / "walks"


# ---------------------------------------------------------------------------
# Canonicalization primitives (duplicated from foo_cartridge.py on purpose)
# ---------------------------------------------------------------------------

def _sha256_hex(data):
    """Return a lowercase SHA-256 digest for exact member bytes."""
    return hashlib.sha256(data).hexdigest()


def _canonical_json_bytes(value):
    """Serialize canonical JSON: UTF-8, sorted keys, compact, one final LF."""
    text = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return (text + "\n").encode("utf-8")


def _reject_duplicate_json_keys(pairs):
    """Fail closed when JSON repeats an object key."""
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"Duplicate key: {key!r}")
        value[key] = item
    return value


def _canonical_zip_info(member_name):
    """Return fixed ZIP metadata for one canonical cartridge member."""
    info = zipfile.ZipInfo(member_name, date_time=WALK_CARTRIDGE_ZIP_TIME)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.create_version = 20
    info.extract_version = 20
    info.flag_bits = 0
    info.internal_attr = 0
    info.external_attr = WALK_CARTRIDGE_FILE_MODE
    info.extra = b""
    info.comment = b""
    return info


# ---------------------------------------------------------------------------
# The derivation: trail.yaml -> consent surface
# ---------------------------------------------------------------------------

def _derive_consent_surface(trail_bytes):
    """Project trail.yaml into what a human must know before riding.

    Pure json parsing, no import of walk.py, no validation beyond what the
    projection itself requires. Every refusal names the exact field, so a
    trail this cannot seal is a trail whose shape is stated, not guessed at.
    """
    try:
        trail = json.loads(
            trail_bytes.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_json_keys,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(
            f"trail.yaml is not the JSON subset of YAML 1.2: {exc}"
        ) from exc

    if not isinstance(trail, dict):
        raise ValueError("trail.yaml must be a mapping")

    name = trail.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("trail.name must be a non-empty string")

    stops = trail.get("stops")
    if not isinstance(stops, list) or not stops:
        raise ValueError("trail.stops must be a non-empty list")

    defaults = trail.get("defaults")
    if not isinstance(defaults, dict):
        raise ValueError("trail.defaults must be a mapping")

    stop_names = []
    url_envs = set()
    optional_url_envs = set()
    connector_scripts = set()
    direct_urls = []

    for index, stop in enumerate(stops):
        where = f"stops[{index}]"
        if not isinstance(stop, dict):
            raise ValueError(f"{where} must be a mapping")
        name_value = stop.get("name")
        if not isinstance(name_value, str) or not name_value.strip():
            raise ValueError(f"{where}.name must be a non-empty string")
        # Exactly one of url / url_env, checked here too. This module is
        # deliberately not a validator -- walk.py owns the schema -- but a
        # projection cannot project a field it cannot find, so the shape it
        # depends on is the one shape it insists on.
        present = {"url", "url_env"} & set(stop)
        if len(present) != 1:
            raise ValueError(
                f"{where} must carry exactly one of ['url', 'url_env']; "
                f"found {sorted(present)}"
            )
        if "url" in present:
            url_value = stop.get("url")
            if not isinstance(url_value, str) or not url_value.strip():
                raise ValueError(f"{where}.url must be a non-empty string")
            direct_urls.append(url_value.strip())
        else:
            env_value = stop.get("url_env")
            if not isinstance(env_value, str) or not env_value.strip():
                raise ValueError(f"{where}.url_env must be a non-empty string")
            # The projection depends on this one flag, so its type is the one
            # thing about it this module insists on; walk.py owns the rest.
            optional = stop.get("optional", False)
            if not isinstance(optional, bool):
                raise ValueError(f"{where}.optional must be true or false")
            if optional:
                optional_url_envs.add(env_value.strip())
            else:
                url_envs.add(env_value.strip())
        connector = stop.get("connector")
        if not isinstance(connector, dict):
            raise ValueError(f"{where}.connector must be a mapping")
        script = connector.get("script")
        if not isinstance(script, str) or not script.strip():
            raise ValueError(f"{where}.connector.script must be a non-empty string")
        stop_names.append(name_value.strip())
        connector_scripts.add(script)

    if len(set(stop_names)) != len(stop_names):
        raise ValueError("trail.stops contains duplicate stop names")

    return {
        "browser": {
            "headless": defaults.get("headless"),
            "override_cache": defaults.get("override_cache"),
            "persistent": defaults.get("persistent"),
            "profile_name": defaults.get("profile_name"),
        },
        "connector_scripts": sorted(connector_scripts),
        # ORDERED, never sorted, for the same reason stop_names is ordered:
        # a rider reads this as "where it takes me, in order". url_envs stays
        # a sorted set because those are a checklist, not a sequence. Present
        # unconditionally, empty list and all, so the surface has ONE shape.
        "direct_urls": direct_urls,
        "name": name,
        # A variable a REQUIRED stop needs is required no matter how many
        # optional stops also name it, so it is listed once, under url_envs.
        "optional_url_envs": sorted(optional_url_envs - url_envs),
        "stop_names": stop_names,
        "url_envs": sorted(url_envs),
    }


def _build_manifest(trail_bytes):
    """Build the complete reproducible manifest from exact trail bytes."""
    return {
        "canonicalization": {
            "json": "utf-8-sorted-compact-lf-v1",
            "zip": "stored-fixed-metadata-v1",
            "zip_file_mode": "0100644",
            "zip_member_order": list(WALK_CARTRIDGE_MEMBERS),
            "zip_source_epoch": WALK_CARTRIDGE_SOURCE_EPOCH,
        },
        "schema": WALK_CARTRIDGE_SCHEMA,
        "sha256": {"trail.yaml": _sha256_hex(trail_bytes)},
        "trail": _derive_consent_surface(trail_bytes),
    }


# ---------------------------------------------------------------------------
# Verify and write
# ---------------------------------------------------------------------------

def verify_walk_cartridge(path):
    """Verify membership, metadata, canonical JSON, CRCs, derivation, bytes.

    Fail closed on every deviation. The verifier accepts no archive comment,
    no extra fields, no alternate compression, no timestamps, no permissions,
    and no alternate JSON representation.
    """
    cartridge_path = Path(path)

    with zipfile.ZipFile(cartridge_path, "r") as archive:
        if archive.comment:
            raise ValueError("Archive comment must be empty.")

        names = archive.namelist()
        duplicates = sorted({n for n in names if names.count(n) > 1})
        missing = sorted(set(WALK_CARTRIDGE_MEMBERS) - set(names))
        unexpected = sorted(set(names) - set(WALK_CARTRIDGE_MEMBERS))
        if duplicates or missing or unexpected:
            raise ValueError(
                f"Invalid cartridge members: missing={missing}, "
                f"unexpected={unexpected}, duplicates={duplicates}"
            )
        if tuple(names) != WALK_CARTRIDGE_MEMBERS:
            raise ValueError(f"Invalid member order: {names!r}")

        member_bytes = {}
        for member_name in WALK_CARTRIDGE_MEMBERS:
            info = archive.getinfo(member_name)
            if info.date_time != WALK_CARTRIDGE_ZIP_TIME:
                raise ValueError(f"Noncanonical timestamp for {member_name!r}.")
            if info.compress_type != zipfile.ZIP_STORED:
                raise ValueError(f"Noncanonical compression for {member_name!r}.")
            if (
                info.create_system != 3
                or info.create_version != 20
                or info.extract_version != 20
            ):
                raise ValueError(
                    f"Noncanonical ZIP version metadata for {member_name!r}."
                )
            if info.flag_bits != 0 or info.internal_attr != 0:
                raise ValueError(f"Noncanonical ZIP flags for {member_name!r}.")
            if info.external_attr != WALK_CARTRIDGE_FILE_MODE:
                raise ValueError(f"Noncanonical file mode for {member_name!r}.")
            if info.extra or info.comment or info.is_dir():
                raise ValueError(f"Noncanonical member metadata for {member_name!r}.")
            member_bytes[member_name] = archive.read(info)

        corrupt_member = archive.testzip()
        if corrupt_member is not None:
            raise ValueError(f"CRC failure in {corrupt_member!r}.")

    try:
        manifest = json.loads(
            member_bytes["manifest.json"].decode("utf-8"),
            object_pairs_hook=_reject_duplicate_json_keys,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"Invalid manifest.json: {exc}") from exc

    # Grade the SCHEMA before grading the BYTES. Without this branch, a
    # cartridge sealed under an older schema fails the byte comparison below
    # and is reported as "does not match the consent surface derived from
    # trail.yaml" -- a sentence that accuses the TRAIL of drifting when the
    # VERIFIER is the thing that changed. Fail-closed either way; the only
    # difference is whether the refusal names the right cause.
    #
    # NARROW ON PURPOSE. Only the schema strings this repo has actually
    # shipped (v1, v2) earn the reassuring "not corruption" wording. A missing,
    # invented, or mangled value is neither known-stale nor known-corrupt, and
    # a verifier that guesses is a verifier whose refusals stop meaning
    # anything.
    sealed_schema = manifest.get("schema")
    if sealed_schema != WALK_CARTRIDGE_SCHEMA:
        if sealed_schema in (WALK_CARTRIDGE_SCHEMA_V1, WALK_CARTRIDGE_SCHEMA_V2):
            raise ValueError(
                f"cartridge schema {sealed_schema!r} predates "
                f"{WALK_CARTRIDGE_SCHEMA!r}. This is a schema change, not "
                "corruption; re-seal the trail. Re-sealing writes a NEW "
                "content-addressed cartridge; it does not upgrade this one, "
                "which stays on disk and stays red until it is pruned."
            )
        raise ValueError(
            f"cartridge schema {sealed_schema!r} is not recognized "
            f"(expected {WALK_CARTRIDGE_SCHEMA!r}). Refusing without ruling "
            "on whether it is stale or corrupt."
        )
    expected_manifest = _build_manifest(member_bytes["trail.yaml"])

    if manifest != expected_manifest:
        raise ValueError(
            "manifest.json does not match the consent surface derived from "
            "trail.yaml."
        )
    if member_bytes["manifest.json"] != _canonical_json_bytes(expected_manifest):
        raise ValueError("manifest.json is not canonical JSON.")

    canonical_buffer = io.BytesIO()
    with zipfile.ZipFile(
        canonical_buffer,
        "w",
        compression=zipfile.ZIP_STORED,
        allowZip64=False,
    ) as canonical_archive:
        canonical_archive.comment = b""
        for member_name in WALK_CARTRIDGE_MEMBERS:
            canonical_archive.writestr(
                _canonical_zip_info(member_name),
                member_bytes[member_name],
            )

    archive_bytes = cartridge_path.read_bytes()
    if archive_bytes != canonical_buffer.getvalue():
        raise ValueError("Archive bytes are not canonical.")

    return {
        "archive_sha256": _sha256_hex(archive_bytes),
        "trail_sha256": expected_manifest["sha256"]["trail.yaml"],
        "consent_surface": expected_manifest["trail"],
    }


def write_walk_cartridge(trail_bytes, output_path):
    """Atomically emit and self-verify a canonical two-member walk.zip."""
    cartridge_path = Path(output_path)
    manifest_bytes = _canonical_json_bytes(_build_manifest(trail_bytes))
    members = (
        ("trail.yaml", trail_bytes),
        ("manifest.json", manifest_bytes),
    )

    with tempfile.NamedTemporaryFile(
        dir=cartridge_path.parent,
        prefix=f".{cartridge_path.name}.",
        suffix=".tmp",
        delete=False,
    ) as temp_file:
        temp_path = Path(temp_file.name)

    try:
        with zipfile.ZipFile(
            temp_path,
            "w",
            compression=zipfile.ZIP_STORED,
            allowZip64=False,
        ) as archive:
            archive.comment = b""
            for member_name, data in members:
                archive.writestr(_canonical_zip_info(member_name), data)
        verification = verify_walk_cartridge(temp_path)
        os.replace(temp_path, cartridge_path)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise

    return verification


def seal_trail(trail_path, output_path=None, cache_root=None):
    """Seal one trail. Returns (final_path, archive_sha256, consent_surface).

    With no explicit output_path the cartridge lands at
    <cache_root>/<archive_sha256>/walk.zip. The digest is not knowable until
    the archive exists, so the archive is built in a scratch file inside the
    cache root, verified, and only then moved into its content-addressed home.
    """
    trail_path = Path(trail_path)
    trail_bytes = trail_path.read_bytes()

    # Fail closed BEFORE touching disk: a trail this cannot derive from is a
    # trail this must not seal.
    _build_manifest(trail_bytes)

    if output_path is not None:
        final = Path(output_path)
        final.parent.mkdir(parents=True, exist_ok=True)
        verification = write_walk_cartridge(trail_bytes, final)
        return final, verification["archive_sha256"], verification["consent_surface"]

    root = Path(cache_root) if cache_root else WALK_CACHE_ROOT
    root.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(
        dir=root,
        prefix=".seal.",
        suffix=".zip",
        delete=False,
    ) as scratch_file:
        scratch = Path(scratch_file.name)

    try:
        verification = write_walk_cartridge(trail_bytes, scratch)
        digest = verification["archive_sha256"]
        target_dir = root / digest
        target_dir.mkdir(parents=True, exist_ok=True)
        final = target_dir / "walk.zip"
        os.replace(scratch, final)
    except Exception:
        scratch.unlink(missing_ok=True)
        raise

    return final, digest, verification["consent_surface"]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _resolve(raw):
    path = Path(raw)
    return path if path.is_absolute() else REPO_ROOT / path


def _print_surface(surface, indent="    "):
    print(f"{indent}name              {surface['name']}")
    print(f"{indent}stops (in order)  {', '.join(surface['stop_names'])}")
    if surface.get("direct_urls"):
        print(f"{indent}opens directly    {', '.join(surface['direct_urls'])}")
    if surface.get("url_envs"):
        print(f"{indent}demands of you    {', '.join(surface['url_envs'])}")
    if surface.get("optional_url_envs"):
        print(f"{indent}optional, if set  {', '.join(surface['optional_url_envs'])}")
    print(f"{indent}names as runnable {', '.join(surface['connector_scripts'])}")
    browser = surface["browser"]
    print(
        f"{indent}browser           profile={browser['profile_name']!r} "
        f"persistent={browser['persistent']} headless={browser['headless']} "
        f"override_cache={browser['override_cache']}"
    )


def _cmd_seal(args):
    if args.out is not None and len(args.trail) != 1:
        print("--out names one file; pass exactly one trail with it.", file=sys.stderr)
        return 2
    exit_code = 0
    for raw in args.trail:
        try:
            final, digest, surface = seal_trail(
                _resolve(raw),
                output_path=args.out,
                cache_root=args.cache_root,
            )
        except (OSError, ValueError) as exc:
            print(f"REFUSED  {raw}: {exc}", file=sys.stderr)
            exit_code = 2
            continue
        print(f"{digest}  {final}")
        print(f"    sealed from       {raw}")
        _print_surface(surface)
    return exit_code


def _cmd_verify(args):
    exit_code = 0
    for raw in args.cartridge:
        try:
            result = verify_walk_cartridge(_resolve(raw))
        except (OSError, ValueError) as exc:
            print(f"REFUSED  {raw}: {exc}", file=sys.stderr)
            exit_code = 2
            continue
        print(f"VERIFIED {result['archive_sha256']}  {raw}")
    return exit_code


def _cmd_show(args):
    try:
        result = verify_walk_cartridge(_resolve(args.cartridge))
    except (OSError, ValueError) as exc:
        print(f"REFUSED  {args.cartridge}: {exc}", file=sys.stderr)
        return 2
    print(f"archive_sha256  {result['archive_sha256']}")
    print(f"trail_sha256    {result['trail_sha256']}")
    print("consent surface:")
    _print_surface(result["consent_surface"])
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Seal, verify, and read Mother Cat walk cartridges."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    seal = sub.add_parser("seal", help="seal one or more trails")
    seal.add_argument("trail", nargs="+")
    seal.add_argument("--out", default=None, help="explicit output path (one trail only)")
    seal.add_argument("--cache-root", default=None, help="override data/walks")

    verify = sub.add_parser("verify", help="verify one or more cartridges")
    verify.add_argument("cartridge", nargs="+")

    show = sub.add_parser("show", help="verify and print the consent surface")
    show.add_argument("cartridge")

    args = parser.parse_args(argv)

    if args.command == "seal":
        return _cmd_seal(args)
    if args.command == "verify":
        return _cmd_verify(args)
    return _cmd_show(args)


if __name__ == "__main__":
    raise SystemExit(main())
