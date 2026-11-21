#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
export SDKROOT="$(xcrun --show-sdk-path)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/checks-module-cache"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devnotes-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT

common=(Sources/DevNotes/AppConfiguration.swift Sources/DevNotes/Models.swift Sources/DevNotes/LabelColor.swift Sources/DevNotes/NotesVault.swift)
swiftc -swift-version 5 -parse-as-library "${common[@]}" Checks/NotesVaultChecks/main.swift -o "$CHECK_DIR/vault"
"$CHECK_DIR/vault"
swiftc -swift-version 5 -parse-as-library "${common[@]}" Sources/DevNotes/LaunchAccess.swift Checks/LaunchAccessChecks/main.swift -o "$CHECK_DIR/access"
"$CHECK_DIR/access"
swiftc -swift-version 5 Sources/DevNotes/Models.swift Sources/DevNotes/StableBindings.swift Checks/BindingChecks/main.swift -o "$CHECK_DIR/bindings"
"$CHECK_DIR/bindings"
swiftc -swift-version 5 Sources/DevNotes/DictationTranscript.swift Checks/DictationTranscriptChecks/main.swift -o "$CHECK_DIR/dictation"
"$CHECK_DIR/dictation"
swiftc -swift-version 5 Sources/DevNotes/TableExporter.swift Checks/TableExportChecks/main.swift -o "$CHECK_DIR/export"
"$CHECK_DIR/export"
