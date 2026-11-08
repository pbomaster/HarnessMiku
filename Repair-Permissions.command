#!/bin/bash
set -eu
cd "$(dirname "$0")"
exec /bin/bash "macos/Repair-Permissions.command" "$@"
