#!/usr/bin/env python3
"""Extract only Java runtimes and LWJGL/graphics code from a vetted iOS IPA.

No third-party launcher application, UI, signing identity or accounts are copied.
Output is a staging bundle, NOT a working or signed NovaCraft IPA.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import zipfile

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if len(args.sha256) != 64 or any(c not in "0123456789abcdefABCDEF" for c in args.sha256):
        parser.error("Provide full SHA-256 of the input IPA")
    digest = hashlib.sha256()
    with args.ipa.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest().lower() != args.sha256.lower():
        sys.exit("IPA SHA-256 mismatch: refusing unverified dependency extraction")
    staging = args.output.resolve()
    if staging.exists() and any(staging.iterdir()):
        sys.exit("Output directory must be empty")
    staging.mkdir(parents=True, exist_ok=True)
    counts = {"java": 0, "native": 0}
    with zipfile.ZipFile(args.ipa) as archive:
        for item in archive.infolist():
            filename = item.filename
            if item.is_dir():
                continue
            parts = filename.split("/")
            if len(parts) < 4 or parts[0] != "Payload" or not parts[1].endswith(".app"):
                continue
            relative = parts[2:]
            group = None
            if len(relative) >= 3 and relative[0] == "java_runtimes" and relative[1] in {
                "java-8-openjdk", "java-17-openjdk", "java-21-openjdk"
            }:
                group = "java"
                dest = staging / "java_runtimes" / Path(*relative[1:])
            elif relative[0] == "Frameworks" and parts[-1].endswith(".dylib"):
                # Copy native library files as dependency *candidates*.
                # Later linking/signing must resolve dependencies and LC_ID_DYLIB.
                group = "native"
                dest = staging / "native" / parts[-1]
            else:
                continue
            if item.file_size > 2 * 1024 * 1024 * 1024:
                sys.exit("Unexpectedly large IPA member")
            if item.external_attr >> 16 & 0o170000 == 0o120000:
                continue  # do not follow upstream symlinks
            if not all(part not in {"", ".", ".."} for part in relative):
                sys.exit("Unsafe IPA member name")
            if not str(dest.resolve()).startswith(str(staging) + os.sep):
                sys.exit("Unsafe extraction destination")
            dest.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as src, dest.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            counts[group] += 1
    print(f"Extracted: {counts['java']} Java runtime files, {counts['native']} native dylibs")
    if counts["java"] == 0:
        sys.exit("No Java runtimes found in this IPA (possibly a slimmed build)")
    if counts["native"] == 0:
        sys.exit("No framework dylibs found in this IPA")
    print("Staged dependencies require license audit, Mach-O validation, relocation, signing, and integration.")

if __name__ == "__main__":
    main()
