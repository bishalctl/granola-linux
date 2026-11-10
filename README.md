# granola-linux

This fork maintains Linux meeting capture and detection alongside the official
Granola application. Google Calendar, sign-in, sync, and integrations continue
to use Granola's own application and services. Account access and integration
permissions still belong to the signed-in user.

`granola-linux` installs [Granola](https://www.granola.ai), the AI meeting
notepad, on a Linux desktop. Granola publishes builds for macOS and Windows
only. Its macOS disk image, however, is an Electron bundle: the app itself is
JavaScript, and the only parts tied to macOS are the Electron runtime it is
packed with and one native SQLite module. This script downloads that image
from Granola's own release endpoint, pairs the JavaScript with the Linux
Electron release of the same version, builds the SQLite module for Linux from
the sources in the image, applies a few small fixes, and installs the result
under your home directory with a desktop entry and a launcher.

This is an unofficial compatibility project. It is not affiliated with
Granola and it redistributes none of Granola's files: every install fetches
the image from Granola, and you sign in with your own account.

## Install

Requirements: x86-64 Linux, `curl`, `python3` 3.9 or newer, `node` 22.22.2
or a later 22, 24.15.0 or a later 24, or 26 and newer, `npm`, `make`, and
`g++` 11 or newer. The Python and Node versions are what the pinned node-gyp
needs to build the native module, and the script checks them before it
starts. Reading the disk image needs 7-Zip 21.02 or newer (the
`7zip` package on Arch, Debian 13 and Ubuntu 24.04 or later). Without one,
the script fetches the static build from 7-zip.org and checks it against a
checksum pinned in the script. The `p7zip` most distributions still ship
cannot read the image's compression.

```sh
git clone https://github.com/bishalctl/granola-linux
cd granola-linux
make install DRY_RUN=1   # prints what would happen, changes nothing
make install             # installs the current release
```

Start Granola from the application menu or with `~/.local/bin/granola`.
Sign-in opens in your browser and returns to the app through a `granola://`
link; the install registers the handler for it.

## Day to day

- `make status` shows the installed version and whether Granola has released
  a newer one.
- `make install` again updates. It stops early when the installed version is
  current; `./granola-linux install --force` rebuilds it anyway.
- `./granola-linux install --version 7.668.3` installs a specific release, and
  `--dmg FILE` builds from an image you already have.
- `make uninstall` removes the app and keeps your notes.
  `./granola-linux uninstall --purge` removes Granola's data too.

For reproducible distribution builds, `sources.json` pins Granola, its matching
Electron runtime and headers, and the SQLite binding metadata by URL and
SHA-256. Run `./granola-linux pin sources.json` to refresh that manifest from
Granola's current full release. This verifies Electron's published checksums
and npm's integrity metadata; Granola publishes no image checksum, so the
manifest records the downloaded image's digest. Review and commit the updated
manifest, then update the distribution's pinned revision of this repository.
The app does not replace a package-managed installation from inside Electron.

Everything is written as your user: the app under
`~/.local/share/granola-linux`, downloads under `~/.cache/granola-linux`, and
Granola's own data under `~/.config/Granola`, where the official app keeps it.
The `GRANOLA_LINUX_HOME`, `GRANOLA_LINUX_CACHE` and `GRANOLA_LINUX_BIN_DIR`
variables move the install root, the download cache and the launcher link.

## What to expect

Granola runs as the real app, not a development build: notes, sync, the AI
features, search and sign-in behave as they do on macOS, and the local
database is encrypted the same way. Microphone recording and transcription
work. The app runs natively on Wayland as well as X11, including the floating
meeting indicator, which on an unpatched build aborts the whole app under
Wayland.

Some things are different from the macOS build:

- Meeting capture uses two PulseAudio PCM streams (including PipeWire's
  PulseAudio compatibility service): the default microphone and the default
  output's monitor. Both feed the app's existing transcription pipeline.
  Install `pactl` and `parec` from your distribution's PulseAudio tools package.
  Capture starts only when Granola requests a recording, stops both streams
  when it ends, and follows default device changes while recording. Use
  `GRANOLA_LINUX_MIC_SOURCE` or `GRANOLA_LINUX_SYSTEM_SOURCE` to select explicit
  PulseAudio source names. This avoids Electron's Windows-only loopback path.
- Meeting detection observes active microphone streams and recognizes common
  browsers (including Helium), Zoom, Teams, Slack, and Discord. It publishes
  meeting evidence to Granola's observer; it does not itself start recordings.
- Granola's auto-update is off. The installed version is pinned; `make
  status` tells you when a new release is out and `make install` brings it
  in.
- Features that call macOS frameworks directly, such as the Apple Calendar
  integration, do not exist on Linux. Google and Microsoft calendars are
  unaffected because they are handled on Granola's servers.
- System-wide keyboard shortcuts have not been tested here. Electron
  registers them through the window system, and Wayland compositors do not
  offer that to applications.

## Under the hood

Every step has a comment in the script that says what breaks without it,
so the conversion can be redone by hand from the comments alone. In outline:

**The image.** Granola's download page serves a small stub that fetches the
app at first launch on macOS, which is useless here. The script follows
Granola's release endpoint to the full image instead, and refuses the stub
with an explanation if one is passed with `--dmg`. The Electron version and
the app version are read from the image's property lists.

**The runtime.** The Linux build of that exact Electron version comes from
Electron's GitHub releases and is verified against the `SHASUMS256.txt`
published beside it. The app archive, its unpacked native modules and the
icons are copied from the image into the runtime; the macOS binaries stay
behind, since the app only loads them on macOS. The Electron binary is
renamed `granola`, because an Electron binary called `electron` reports the
app as unpackaged and Granola then runs with developer tooling and a "Not
packaged" tray menu.

**The SQLite module.** Granola uses `better-sqlite3-multiple-ciphers` with an
additional `updateHook` method. Older images include that fork's C++ sources;
newer images omit them. When they are absent, the matching public module is
built with a small adapter over SQLite's `sqlite3_update_hook` API. It reports
operation, database, table, and row ID, unregisters on close, and propagates
callback errors through the executing statement. Encryption and queries stay
in the upstream library. `prepare-sqlite DIR` adds the adapter to an unpacked
public source tree for distribution builds. The module is compiled against
the exact Electron headers used by the app.

**The patches.**

- The platform label. Granola's API returns an error for `platform=linux`,
  which blocks sign-in. The app's fallback for unknown platforms is rewritten
  to say `Windows`, with the same byte length, since the archive header
  records every file's offset. This is what the API sees, so Granola's own
  device list may show the install as Windows.
- The echo-cancellation notice. Granola cancels echo through Core Audio on
  macOS and treats every other platform as Windows, so the transcript view
  would say the feature is in beta on Windows. The notice stays, since it is
  true here as well, and names Linux instead.
- The click-and-drag module. The meeting indicator window is moved with a
  native module whose Linux build calls Xlib. Under Wayland that aborts the
  process. Its entry point is replaced with one that uses the native module on
  X11 and does nothing on Wayland.
- The tray icons. The macOS tray images are black template shapes that only
  macOS tints; on a dark Linux panel they are invisible. The coloured app icon
  takes their place.
- Tiled window geometry on Hyprland. Granola requests a fixed size when it
  changes views. Electron applies that size to its page even when the tile
  stays larger, leaving empty space until focus changes. The primary window
  checks `hyprctl` before unmaximizing or applying fixed bounds and lets
  the compositor control its size. Floating windows, hidden-window opening,
  XWayland, other desktops and notification windows keep their native APIs.

**The safety net.** The rebuilt module and the drag stub are run inside the
installed Electron before anything is installed: the test opens an encrypted
database, checks that `updateHook` fires, and calls the stub under a Wayland
display. Only then is the new app swapped into place, so a failed build never
replaces a working one. If the system restricts unprivileged user namespaces,
which Chromium's sandbox needs, the script prints the root command that
enables the setuid sandbox helper rather than running anything as root.

Distribution packages can assemble the matching Electron runtime and rebuild
SQLite with their own toolchain, then run `./granola-linux prepare APPDIR`.
This applies the same compatibility changes without network access or writing
launchers into a user's home directory. The Linux audio adapter is generated
from this script; there is no vendored copy of Granola's application code.
`make check` also tests PCM framing, independent sources, cancellation during
device discovery, stream cleanup, device changes, and meeting detection with
isolated process fixtures. It does not open the microphone or contact Granola.

## Safety and terms

The script is one file; read it before running it. It never runs as root. It
downloads from Granola's release host, Electron's GitHub releases,
electronjs.org, the npm registry and, when needed, 7-zip.org. Every download
except Granola's own image is checked against a published or pinned checksum;
Granola publishes none for its image.

Granola's terms of use forbid reverse engineering its software. This project
changes one string and one module's entry point in a copy you downloaded
yourself. Whether that is acceptable to you is your decision.

## Acknowledgements

Running the macOS bundle on the Linux Electron runtime, patching the platform
label and rebuilding the SQLite module from the sources in the image was
worked out and documented by
[tirtha4/Granola-for-Linux](https://github.com/tirtha4/Granola-for-Linux).
The stub-installer check, checksum verification of the Electron download,
the binary rename and the Wayland fix for the click-and-drag module were
first proposed in that repository's pull requests by regrog, jason-c-dev and
shawnyeager. This project is a fresh implementation of those ideas and shares
no code with them.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
