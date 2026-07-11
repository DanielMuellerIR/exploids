#!/bin/bash
# Generiert das iOS-Xcode-Projekt aus project.yml — IMMER über dieses Skript statt
# `xcodegen generate` direkt: es zieht vorher die MARKETING_VERSION aus der zentralen
# VERSION-Datei im Repo-Root nach (Single Source of Truth). Vorher driftete die
# iOS-Version von der macOS-Version weg (stand noch auf 0.9.0, als macOS 0.14.0 war).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat ../VERSION)"

# MARKETING_VERSION in project.yml auf den VERSION-Stand bringen (in-place).
# project.yml bleibt damit die lesbare Wahrheit und der Sync ist im git-Diff sichtbar.
sed -i '' "s/^\\( *MARKETING_VERSION:\\).*/\\1 \"${VERSION}\"/" project.yml

xcodegen generate
