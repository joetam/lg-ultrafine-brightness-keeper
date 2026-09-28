#!/bin/bash
set -euo pipefail

label="com.joetam.lg-ultrafine-brightness-keeper"
app_directory="$HOME/Library/Application Support/LGUtraFineBrightnessKeeper"
binary_path="$app_directory/lg-ultrafine-brightness-keeper"
agent_path="$HOME/Library/LaunchAgents/$label.plist"
log_path="$HOME/Library/Logs/LGUtraFineBrightnessKeeper.log"
project_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
temporary_plist="$(mktemp -t lg-ultrafine-brightness-keeper)"

cleanup() {
    rm -f "$temporary_plist"
}
trap cleanup EXIT

make -C "$project_directory"
mkdir -p "$app_directory" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

plutil -create xml1 "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :Label string $label" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $binary_path" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :ProcessType string Interactive" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :ThrottleInterval integer 10" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $log_path" "$temporary_plist"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $log_path" "$temporary_plist"
plutil -convert xml1 "$temporary_plist"

if launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$label"
    # bootout can return before the old process and job have been removed.
    for ((attempt = 0; attempt < 50; attempt++)); do
        if ! launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
    if launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
        printf 'Timed out waiting for the previous helper to stop. Run installer again.\n' >&2
        exit 1
    fi
fi
install -m 755 "$project_directory/build/lg-ultrafine-brightness-keeper" "$binary_path"
install -m 644 "$temporary_plist" "$agent_path"
launchctl bootstrap "gui/$UID" "$agent_path"

printf 'Installed %s\n' "$label"
