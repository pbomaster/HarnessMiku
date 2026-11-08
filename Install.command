#!/bin/bash
set -eu
cd "$(dirname "$0")"
if [[ $# -eq 0 && -f "$PWD/New1007-RetrynowMiku.zip" ]]; then set -- "$PWD/New1007-RetrynowMiku.zip"; fi
exec /bin/bash "macos/Install.command" "$@"
