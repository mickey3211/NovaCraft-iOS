#!/usr/bin/env bash
# Build NovaCraft's own Java bootstrap. No third-party launcher source copied.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 path/to/NovaCraft.app" >&2; exit 1; }

APP="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Native/Bootstrap/src/dev/novacraft/GameEntrypoint.java"
[[ -s "$SOURCE" && -d "$APP" ]] || { echo "Java bootstrap source/app missing" >&2; exit 1; }

JAVAC=""
for candidate in "${JAVA8_HOME:-}/bin/javac" "${JAVA_HOME:-}/bin/javac"; do
  if [[ -x "$candidate" ]]; then JAVAC="$candidate"; break; fi
done
if [[ -z "$JAVAC" ]]; then JAVAC="$(command -v javac || true)"; fi
[[ -n "$JAVAC" ]] || { echo "javac not found: cannot produce Java diagnostic bootstrap" >&2; exit 1; }
JAR_TOOL="$(dirname "$JAVAC")/jar"
if [[ ! -x "$JAR_TOOL" ]]; then JAR_TOOL="$(command -v jar || true)"; fi
[[ -n "$JAR_TOOL" ]] || { echo "jar command not found" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/classes" "$APP/NovaBootstrap"
"$JAVAC" -encoding UTF-8 -source 8 -target 8 -d "$TMP/classes" "$SOURCE"
"$JAR_TOOL" cf "$APP/NovaBootstrap/novacraft-bootstrap.jar" -C "$TMP/classes" .
[[ -s "$APP/NovaBootstrap/novacraft-bootstrap.jar" ]] || exit 1
"$JAR_TOOL" tf "$APP/NovaBootstrap/novacraft-bootstrap.jar" | grep -Fx 'dev/novacraft/GameEntrypoint.class'
# Compile-time smoke test: execute this exact class on the build runner.
# This verifies Java bytecode and the launch arguments without touching iOS JIT.
JAVA_TOOL="$(dirname "$JAVAC")/java"
if [[ ! -x "$JAVA_TOOL" ]]; then JAVA_TOOL="$(command -v java || true)"; fi
[[ -n "$JAVA_TOOL" ]] || { echo "java command not found" >&2; exit 1; }
"$JAVA_TOOL" -Dnovacraft.jvmProbeOnly=true \
    -cp "$APP/NovaBootstrap/novacraft-bootstrap.jar" \
    dev.novacraft.GameEntrypoint
echo "Bundled and smoke-tested NovaCraft Java 8-compatible diagnostic class."
