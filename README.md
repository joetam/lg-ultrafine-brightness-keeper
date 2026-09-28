# LG UltraFine Brightness Keeper

`lg-ultrafine-brightness-keeper` is a small, dependency-free macOS helper for
the LG UltraFine wake bug: the panel wakes visibly dimmer (or brighter) even
though macOS still shows the saved brightness value.

On startup, screen wake, unlock, or display configuration changes, the helper:

1. waits one second for Thunderbolt displays to settle;
2. enumerates online displays whose macOS name is `LG UltraFine`;
3. reads each display's saved native brightness value;
4. nudges each panel by less than 1%; and
5. restores the saved value 120 ms later.

It repeats the repair at 3, 7, and 15 seconds to cover slow-waking panels,
reading the current brightness afresh each time. The background process runs
the AppKit event loop so display names and IDs stay current after reconnects.
The LaunchAgent starts at login and restarts the helper if it exits.

It uses the same private `DisplayServices` API macOS and popular display-control
apps use for Apple-managed displays. It does not use DDC, change resolution,
touch color profiles, or target non-UltraFine displays.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- One or more LG UltraFine displays whose macOS name contains `LG UltraFine`

## Install

```sh
git clone https://github.com/joetam/lg-ultrafine-brightness-keeper.git
cd lg-ultrafine-brightness-keeper
./install.sh
```

The installer builds a native binary, installs it in your user Library, and
starts a per-user LaunchAgent. No administrator password is needed.

## Build, test, and inspect

```sh
make
./build/lg-ultrafine-brightness-keeper --self-test
./build/lg-ultrafine-brightness-keeper --list
```

Run one repair pulse:

```sh
./build/lg-ultrafine-brightness-keeper --once
```

`make test` runs the hardware-independent target-selection test.
`make hardware-check` lists the displays macOS sees and their native brightness
values.

## Installed files

The executable is installed at:

```text
~/Library/Application Support/LGUtraFineBrightnessKeeper/lg-ultrafine-brightness-keeper
```

Its LaunchAgent is:

```text
~/Library/LaunchAgents/com.joetam.lg-ultrafine-brightness-keeper.plist
```

Logs are written to `~/Library/Logs/LGUtraFineBrightnessKeeper.log`.

## Remove

```sh
./uninstall.sh
```

Removal stops the LaunchAgent and removes only the helper's installed binary,
plist, and log. It does not alter macOS display settings or monitor firmware.

## Caveat

`DisplayServices` is a private macOS framework. Apple can change it in a future
macOS release. The helper fails closed if the expected symbols are unavailable.

## Related discussions

These are community reports of the same or closely related wake/brightness
failure; they are context for the workaround, not an official diagnosis.

- [Apple Support Community: wake changes brightness; a delayed up/down pulse on unlock restores it](https://discussions.apple.com/thread/254692744)
- [MonitorControl #874: two UltraFine 5Ks wake dimmer while macOS still shows the prior brightness](https://github.com/MonitorControl/MonitorControl/discussions/874)
- [MacRumors: 27MD5KL wakes dimmed with auto-dimming off and brightness at maximum](https://forums.macrumors.com/threads/lg-ultrafine-5k-on-mac-mini-m1-keeps-dimming.2272425/)
- [BetterDisplay #5063: a 2026 report of 10–20% dimming at 100% after sleep](https://github.com/waydabber/BetterDisplay/discussions/5063)

## License

[MIT](LICENSE)
