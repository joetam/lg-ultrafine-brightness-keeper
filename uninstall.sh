#!/bin/bash
set -euo pipefail

label="com.joetam.lg-ultrafine-brightness-keeper"
app_directory="$HOME/Library/Application Support/LGUtraFineBrightnessKeeper"
binary_path="$app_directory/lg-ultrafine-brightness-keeper"
agent_path="$HOME/Library/LaunchAgents/$label.plist"
log_path="$HOME/Library/Logs/LGUtraFineBrightnessKeeper.log"

launchctl bootout "gui/$UID/$label" >/dev/null 2>&1 || true
rm -f "$agent_path" "$binary_path" "$log_path"
rmdir "$app_directory" 2>/dev/null || true

printf 'Removed %s\n' "$label"
