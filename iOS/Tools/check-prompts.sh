#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /private/tmp/miku-prompt-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
mkdir "$check_dir/Stage"
cp HarnessMiku/Stage/persona.txt HarnessMiku/Stage/august-persona.txt HarnessMiku/Stage/bonsai-persona.txt "$check_dir/Stage/"
swiftc HarnessMiku/Services.swift HarnessMiku/FishSpeech.swift HarnessMiku/LipSync.swift HarnessMiku/LocalMiku.swift Tools/Tests/PromptChecks.swift -o "$check_dir/check"
"$check_dir/check"
