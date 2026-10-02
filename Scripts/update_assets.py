#!/usr/bin/env python3
"""Check pinned master data, stage changed assets, and record successful runs."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request


TABLES = (
    "gachas", "characterProfiles", "gameCharacters", "gameCharacterUnits",
    "events", "eventDeckBonuses", "eventCards", "eventMusics", "cards",
)
REPOSITORIES = {
    locale: f"Sekai-World/sekai-master-db{suffix}-diff"
    for locale, suffix in (("jp", ""), ("en", "-en"), ("tc", "-tc"), ("cn", "-cn"), ("kr", "-kr"))
}
ASSETS = ("gacha", "character", "event", "card")
STATE_VERSION = 2


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def fetch(url, *, api=False):
    headers = {"User-Agent": "JSON2Proto-asset-update"}
    if api:
        headers["Accept"] = "application/vnd.github+json"
        if token := os.environ.get("GH_TOKEN"):
            headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as response:
        return response.read()


def source_snapshot(locale):
    repository = REPOSITORIES[locale]
    base = f"https://api.github.com/repos/{repository}"
    commit = json.loads(fetch(f"{base}/commits/main", api=True))
    tree = json.loads(fetch(f"{base}/git/trees/{commit['commit']['tree']['sha']}", api=True))
    if tree.get("truncated"):
        raise ValueError(f"Incomplete source tree: {repository}")
    blobs = {entry["path"]: entry["sha"] for entry in tree["tree"] if entry["type"] == "blob"}
    files = {}
    for table in TABLES:
        name = f"{table}.json"
        if name not in blobs:
            raise ValueError(f"Missing source: {repository}/{name}")
        files[name] = blobs[name]
    return {"repository": repository, "commit": commit["sha"], "files": files}


def fingerprint(snapshot):
    # Ignore upstream commits that only change unrelated tables.
    return {
        "version": STATE_VERSION,
        "converter": snapshot["converter"],
        "sources": {
            locale: {"repository": source["repository"], "files": dict(source["files"])}
            for locale, source in snapshot["sources"].items()
        },
    }


def file_hash(path):
    if not path.is_file() or path.stat().st_size == 0:
        return None
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_hashes(directory):
    return {
        f"{name}.aar": file_hash(Path(directory) / f"{name}.aar") for name in ASSETS
    }


def protobuf_hashes(directory):
    return {f"{name}.proto": file_hash(Path(directory) / f"{name}.proto") for name in ASSETS}


def needs_update(snapshot, state, published, *, force=False):
    artifacts = artifact_hashes(published)
    return (
        force or state is None or any(value is None for value in artifacts.values())
        or any((Path(published) / f"{name}.proto").exists() for name in ASSETS)
        or state.get("inputs") != fingerprint(snapshot)
        or state.get("artifacts") != artifacts
    )


def output(name, value):
    value = str(value).lower() if isinstance(value, bool) else str(value)
    print(f"{name}={value}")
    if path := os.environ.get("GITHUB_OUTPUT"):
        with open(path, "a") as file:
            file.write(f"{name}={value}\n")


def check(args):
    with ThreadPoolExecutor(max_workers=5) as pool:
        sources = dict(zip(REPOSITORIES, pool.map(source_snapshot, REPOSITORIES)))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    snapshot = {"converter": revision, "sources": sources}
    write_json(args.snapshot, snapshot)
    try:
        state = read_json(args.state)
        if not isinstance(state, dict):
            state = None
    except (FileNotFoundError, ValueError):
        state = None
    changed = needs_update(snapshot, state, args.published, force=args.force)
    output("changed", changed)
    print("Conversion required." if changed else "Sources, converter and published assets are unchanged; skipping conversion.")


def download_one(source, name, destination):
    # Pin all tables in each region to the commit inspected by check().
    url = f"https://raw.githubusercontent.com/{source['repository']}/{source['commit']}/{name}"
    data = fetch(url)
    blob = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
    if blob != source["files"][name]:
        raise ValueError(f"Source checksum mismatch: {source['repository']}/{name}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def download(args):
    snapshot = read_json(args.snapshot)
    with ThreadPoolExecutor(max_workers=5) as pool:
        tasks = [
            pool.submit(download_one, source, name, Path(args.input) / locale / name)
            for locale, source in snapshot["sources"].items() for name in source["files"]
        ]
        for task in tasks:
            task.result()


def archived_protobuf_hash(archive, name):
    # A cold cache still compares content, not timestamp-bearing archive bytes.
    with tempfile.TemporaryDirectory() as directory:
        try:
            subprocess.run([
                "aa", "extract", "-i", str(archive), "-d", directory,
                "-include-regex", f"^{re.escape(name)}\\.proto$", "-include-type", "f",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return None
        return file_hash(Path(directory) / f"{name}.proto")


def prepare_assets(generated, published, state=None):
    generated, published = Path(generated), Path(published)
    # Validate every output before touching the checkout used for publication.
    hashes = protobuf_hashes(generated)
    if any(value is None for value in hashes.values()):
        raise ValueError("Conversion did not produce all four nonempty Protobuf files")
    changed = []
    for name in ASSETS:
        archive = published / f"{name}.aar"
        archive_hash = file_hash(archive)
        expected_archive = (state or {}).get("artifacts", {}).get(f"{name}.aar")
        previous_content = None
        if archive_hash is not None:
            if archive_hash == expected_archive:
                previous_content = (state or {}).get("protobuf", {}).get(f"{name}.proto")
            if previous_content is None:
                previous_content = archived_protobuf_hash(archive, name)
        binary_changed = hashes[f"{name}.proto"] != previous_content
        if binary_changed:
            subprocess.run(["aa", "archive", "-i", str(generated / f"{name}.proto"), "-o", str(archive)], check=True)
            if file_hash(archive) is None:
                raise ValueError(f"Archive was not created: {archive}")
            changed.append(name)
    # Only remove legacy raw binaries once all archives have been prepared.
    for name in ASSETS:
        legacy = published / f"{name}.proto"
        if legacy.exists():
            legacy.unlink()
            if name not in changed:
                changed.append(name)
    return changed


def record(args):
    hashes = artifact_hashes(args.published)
    contents = protobuf_hashes(args.generated)
    if any(value is None for value in [*hashes.values(), *contents.values()]):
        raise ValueError("Cannot record success with missing or empty assets")
    if any((Path(args.published) / f"{name}.proto").exists() for name in ASSETS):
        raise ValueError("Raw Protobuf files must not be published")
    write_json(args.state, {"inputs": fingerprint(read_json(args.snapshot)), "artifacts": hashes, "protobuf": contents})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--state", required=True)
    check_parser.add_argument("--snapshot", required=True)
    check_parser.add_argument("--published", required=True)
    check_parser.add_argument("--force", action="store_true", default=os.environ.get("FORCE_UPDATE") == "true")
    download_parser = commands.add_parser("download")
    download_parser.add_argument("--snapshot", required=True)
    download_parser.add_argument("--input", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--generated", required=True)
    prepare_parser.add_argument("--published", required=True)
    prepare_parser.add_argument("--state")
    record_parser = commands.add_parser("record")
    record_parser.add_argument("--snapshot", required=True)
    record_parser.add_argument("--state", required=True)
    record_parser.add_argument("--published", required=True)
    record_parser.add_argument("--generated", required=True)
    args = parser.parse_args()
    if args.command == "check":
        check(args)
    elif args.command == "download":
        download(args)
    elif args.command == "prepare":
        try:
            state = read_json(args.state) if args.state else None
            if not isinstance(state, dict):
                state = None
        except (FileNotFoundError, ValueError):
            state = None
        changed = prepare_assets(args.generated, args.published, state)
        output("changed", bool(changed))
        print("Changed assets: " + (", ".join(changed) or "none"))
    else:
        record(args)


if __name__ == "__main__":
    main()
