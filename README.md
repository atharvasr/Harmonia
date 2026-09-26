# Harmonia
# HARMONIA IS INCOMPLETE HENCE IS UNDER MAINTAINANCE DO NOT RUN/ DONLOADED HARMONIA RIGHT NOW UNDER PROCESS NEW PROJECT IS UNDER CONSTRUCTION
under contributions lightweight offline Linux music player with broad audio-format support,
metadata handling, playlists, queue management, library scanning, artwork,
search, and a desktop-oriented web interface.

Harmonia has **no Python dependencies**. It needs Python 3.10+ and `ffmpeg`,
both already present on most Linux systems. Everything else — tag parsing, the
database, the HTTP layer, ALSA output, filesystem watching — is written against
the standard library.

```bash
./build.sh          # check environment, compile, run tests
./scripts/run.sh    # start the player
```

> **Independent project.** Harmonia is inspired by the usability and
> information density of desktop music players such as
> [Tauon Music Box](https://github.com/Taiko2k/Tauon). It is **not** Tauon, not
> an official fork, and shares no code, assets or branding with it. All code
> here is original.

---

## Screenshots

| Albums (dark) | Album detail |
|---|---|
| ![Album grid](docs/screenshots/albums.png) | ![Album detail](docs/screenshots/album-detail.png) |

| Playing, with queue | Track list |
|---|---|
| ![Queue](docs/screenshots/queue.png) | ![Tracks](docs/screenshots/tracks.png) |

| Metadata inspector | Light theme |
|---|---|
| ![Metadata](docs/screenshots/metadata.png) | ![Light theme](docs/screenshots/light.png) |

---

## Features

**Playback**
- Play, pause, next, previous, seek, volume, mute
- Shuffle and repeat (off / all / one)
- Gapless playback when consecutive tracks share a format
- Per-track ReplayGain
- Resume position and queue restored across restarts
- Corrupt, missing or unsupported files are skipped, never fatal

**Library**
- Add, remove and rescan folders; nested directories
- Incremental scanning — unchanged files are never re-parsed
- Detects new, modified and deleted files
- Automatic change detection via inotify, with a polling fallback
- SQLite database with a versioned schema

**Search**
- SQLite FTS5 across title, artist, album, album artist, genre and filename
- Prefix matching, debounced search-as-you-type
- Malformed input falls back to a substring search rather than erroring

**Metadata**
- Title, artist, album, album artist, track/disc numbers, genre, date,
  composer, comment, compilation flag, ReplayGain tags, MusicBrainz ID
- Embedded file metadata is kept strictly separate from library metadata
- **Audio files are opened read-only and never written to**

**Artwork**
- Embedded artwork first, then folder art (`cover`/`folder`/`album`/`front`)
- Content-hashed disk cache so images are decoded once

**Interface**
- Album grid, album detail, artists, tracks, genres
- Favorites, recently played, recently added, playlists, queue panel
- Persistent player bar with artwork, seek, times and a format badge
- Right-click context menus that do real work
- Keyboard shortcuts throughout
- Dark and light themes, each designed separately rather than inverted
- Virtualized lists plus server-side paging for large libraries

**Desktop integration**
- MPRIS2 over D-Bus (media keys, `playerctl`, panel widgets)
- `.desktop` launcher entry

---

## Supported formats

Every format below was verified by decoding a real file end-to-end and checking
the PCM output length against the expected duration, plus a tag-parsing test.

| Format | Container | Tags read | Decode verified |
|---|---|---|---|
| MP3 (CBR & VBR) | MPEG | ID3v2.2/2.3/2.4, ID3v1 | yes |
| FLAC | FLAC | Vorbis comments, STREAMINFO, PICTURE | yes |
| WAV | RIFF | `LIST`/`INFO`, embedded `id3 ` chunk | yes |
| Ogg Vorbis | Ogg | Vorbis comments | yes |
| Opus | Ogg | Vorbis comments (`OpusTags`) | yes |
| AAC / M4A | MP4 | iTunes-style `ilst` atoms | yes |
| AIFF / AIFC | IFF | `ID3 ` chunk, `NAME`/`AUTH` | yes |
| ALAC | MP4 | iTunes-style atoms | **not tested** |

**Anything else your ffmpeg build decodes will also play** — WavPack, Musepack,
WMA, APE, DSF and so on. Harmonia delegates decoding to ffmpeg, so the playable
set follows your system. What it won't do for those is read their native tags:
the hand-written parsers cover the table above, and other formats fall back to
ffprobe for audio properties with the filename as the title. Check yours with
`ffmpeg -decoders`.

**Not supported:** DRM-protected files (iTunes `.m4p`), and tracker/chiptune
formats that need a dedicated playback engine rather than a decoder.

**High-resolution audio** works: 24-bit and 96/192 kHz files decode at their
native rate and channel count rather than being forced to 44.1 kHz.

---

## Architecture

```
src/musicplayer/
├── metadata/          embedded tag parsing (read-only)
│   ├── id3.py           ID3v1, ID3v2.2/2.3/2.4
│   ├── flac.py          FLAC metadata blocks
│   ├── vorbiscomment.py shared by FLAC, Vorbis, Opus
│   ├── ogg.py           Ogg page/packet demux
│   ├── mp4.py           MP4/M4A atom walker
│   ├── riff.py          WAV and AIFF chunks
│   └── mpegaudio.py     MPEG frame headers, Xing/VBRI
├── db/                  schema.sql + all SQL in database.py
├── library/             scanner.py (threaded) + watcher.py (inotify)
├── playback/            decoder.py, sinks.py, queue.py, engine.py
├── webapp/              server.py (JSON API) + static/ (the interface)
├── coverart.py          artwork resolution + disk cache
├── mpris.py             org.mpris.MediaPlayer2
└── app.py               wires it together; the interface's only entry point
```

Three rules hold the design together:

**The interface never blocks.** Scanning, decoding and watching each run on
their own threads. The web interface polls a JSON status endpoint; the GTK port
uses a `GLib` timeout. Nothing in the view layer waits on I/O.

**File metadata and library metadata are separate.** Tags are copied from your
files into the database as a read-only mirror. Favorites, play counts, ratings
and playlists live in their own tables. Audio files are never written to.

**The view layer holds no logic.** `MusicPlayerApp` exposes everything; both
front-ends are thin. That is why the GTK port is only a few hundred lines.

Ten architecture decision records — what was chosen, the evidence, the
trade-offs, and what would justify revisiting each — are in
[`docs/architecture.md`](docs/architecture.md).

### Performance

Measured on **a single CPU core**. A normal desktop will be faster.

| Operation | Library size | Time |
|---|---|---|
| Initial scan | 20,000 tracks | 3.9 s |
| Rescan, nothing changed | 5,000 tracks | 80 ms |
| Search (FTS5) | 20,000 tracks | 1.6–5.7 ms |
| Open Tracks view | 20,000 tracks | 96 ms |
| Scroll to row ~10,000 | 20,000 tracks | 274 ms |

Two things make this hold up: files are fingerprinted by `(mtime, size)` so
unchanged files are never re-parsed, and the track view keeps ~35 rows in the
DOM regardless of library size while fetching 300-row pages on demand.

---

## Linux requirements

**Required**

- Python 3.10 or newer
- `ffmpeg` and `ffprobe`
- SQLite with FTS5 (bundled with Python on every mainstream distro)
- ALSA (`libasound`) for audio output

**Optional — each degrades gracefully and reports itself**

| Package | Gains | Without it |
|---|---|---|
| `python-dbus-next` | MPRIS, media keys, `playerctl` | MPRIS disabled, and says so |
| `numpy` | faster volume/ReplayGain scaling | falls back to stdlib `audioop` |
| `gtk4`, `libadwaita`, `python-gobject` | native GTK front-end | use the web interface |

---

## Installation

**Arch / Manjaro**
```bash
sudo pacman -S python ffmpeg
sudo pacman -S python-dbus-next python-numpy   # optional
```

**Debian / Ubuntu / Raspberry Pi OS**
```bash
sudo apt install python3 ffmpeg
sudo apt install python3-numpy                 # optional
pip install --user dbus-next                   # optional
```

**Fedora**
```bash
sudo dnf install python3 ffmpeg
```

Then:
```bash
git clone https://github.com/<atharvasr>/Harmonia.git
cd Harmonia
./build.sh              # verifies environment and runs the test suite
./scripts/run.sh
```

Optional user install (no root), which puts `harmonia` on your `PATH` and
registers the desktop entry:
```bash
./scripts/install.sh
harmonia
```
Remove with `./scripts/uninstall.sh` (add `--purge` to also delete the library
database; your music is never touched).

---

## Running

```bash
./scripts/run.sh                          # start, open a window
./scripts/run.sh --no-window              # serve only; open the URL yourself
./scripts/run.sh --port 9000              # pick a port
./scripts/run.sh --scan ~/Music           # scan a folder and exit
./scripts/run.sh --no-mpris               # skip D-Bus entirely
./scripts/run.sh --data-dir /tmp/test     # throwaway library
./scripts/run-gtk.sh                      # native GTK front-end (untested)
```

Add your music from **Settings → Add folder**, or with `--scan`.

### Keyboard shortcuts

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Play / pause |
| <kbd>Ctrl</kbd> + <kbd>←</kbd> / <kbd>→</kbd> | Previous / next track |
| <kbd>←</kbd> / <kbd>→</kbd> | Seek 5 seconds |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Volume |
| <kbd>/</kbd> or <kbd>Ctrl</kbd>+<kbd>F</kbd> | Focus search |
| <kbd>S</kbd> | Shuffle |
| <kbd>R</kbd> | Cycle repeat (off → all → one) |
| <kbd>M</kbd> | Mute |
| <kbd>Q</kbd> | Toggle queue panel |
| <kbd>Esc</kbd> | Close menu, dialog or panel |

Shortcuts are suppressed while a text field has focus, so typing in search
behaves normally.

---

## Testing

```bash
./scripts/test.sh                 # everything
./scripts/test.sh test_metadata   # one module
./scripts/make-test-audio.sh      # regenerate fixtures
```

Tests run against **real audio files** decoded by **real ffmpeg** — not mocks.
Fixtures are synthetic sine tones, so no copyrighted material is used or
shipped.

**Current result: 77 tests, all passing, ~43 s.**

| Module | Tests | Covers |
|---|---|---|
| `test_metadata.py` | 15 | 7 formats, tags, cover art, VBR duration, corrupt files |
| `test_db.py` | 10 | CRUD, FTS search, playlists, favorites, state round-trip |
| `test_scanner.py` | 9 | add / skip-unchanged / modify / delete, nesting, bad files |
| `test_queue.py` | 22 | shuffle, repeat modes, insert/remove/move, persistence |
| `test_playback.py` | 13 | all formats decoded, pause, seek, advance, error recovery |
| `test_watcher.py` | 8 | real inotify events, polling fallback, clean shutdown |

Beyond the automated suite, every view was loaded and clicked in a real
Chromium browser with the console checked for errors (none), automatic track
advance through a full album was observed, and adding a file to a watched
folder updating the library was confirmed end-to-end.

### Bugs this process caught

Listed because they are the ones that reading the code would have missed:

1. Enabling shuffle mid-playback stranded every track ordered before the
   current one — they became unreachable.
2. MP3 scanning was 200x too slow: it shelled out to `ffprobe` per file
   (24 files/s). A real MPEG frame parser took it to 5,500 files/s.
3. `poll_error()` raced ffmpeg's exit, so a missing file reported success.
4. File descriptors leaked on every track end.
5. The test sink didn't block like real hardware, making every timing
   assertion meaningless until fixed.
6. Three interface defects, including `display:flex` overriding the `hidden`
   attribute so a toggle leaked onto views it didn't belong to.

---

## Audio-output limitations

**Read this before filing a sound bug.**

Harmonia was developed in an environment with **sound card** (`/dev/snd`
did not exist). Decoding is thoroughly verified — a 2-second FLAC produces
exactly 176,400 PCM bytes, and a VBR MP3 matches ffprobe's duration to
5.041633 s — but **no audio has ever been played through real hardware by this
program**.

`AlsaSink` is real ctypes code against `libasound`. It correctly raises a
catchable error when no device exists, and the player falls back to a silent
null sink rather than crashing. But that path to actual speakers is the least
tested part of the project and the most likely place to find a bug.

If playback is silent, the Settings page and the startup log both report
whether an audio device was found. Verify ALSA independently with
`speaker-test -c2 -twav`. Under PipeWire, ensure `pipewire-alsa` is installed;
under PulseAudio, `pulseaudio-alsa`.

---

## Raspberry Pi status

Harmonia should run well on a Pi — it is pure Python plus ffmpeg, with nothing
architecture-specific — but **this has not been tested on real Pi hardware**.
No ARM machine was available.

Expected behaviour, worth verifying yourself:

- Use Raspberry Pi OS **64-bit** for a better ffmpeg build.
- Prefer the repository `ffmpeg` over a self-compiled one.
- Scanning is I/O-bound, so an SSD over USB3 helps far more than overclocking.
- Decoding runs inside ffmpeg, not Python, so 24/96 FLAC should be comfortable
  on a Pi 4.
- A 10,000-track scan is expected to take roughly a minute, extrapolated from
  single-core x86 measurements — not measured on a Pi.

Reports from real Pi hardware are welcome.

---

## Known limitations

Stated plainly, including the awkward ones.

- **Audio output is unverified on real hardware.** See the section above.
- **MPRIS has never executed.** No session bus or `dbus-next` was available.
  The code is written against the spec and reports its own unavailability
  rather than faking success. Verify with `playerctl status`.
- **The GTK4 front-end has never run.** No GTK4/PyGObject available.
  `gtk_skeleton/harmonia_gtk.py` compiles and exits with a helpful message,
  but it is a port skeleton, not verified code. The web interface is tested.
- **Gapless is conditional.** It works when consecutive tracks share sample
  rate and channel count. A format change forces an ALSA reconfigure and a
  short gap — a hardware constraint, not a shortcut.
- **Encoder delay is not compensated.** MP3/AAC gapless is close but not
  sample-exact. FLAC, WAV and AIFF are exact.
- **ReplayGain applies track gain only.** Album gain is parsed and stored but
  not applied, so albums mastered as a whole aren't levelled as one.
- **No tag editor.** Deliberate — nothing writes to your files, so there was no
  safe path to a half-built editor.
- **ALAC is detected but not decode-tested.**
- **The interface runs over loopback HTTP.** It binds `127.0.0.1` and is not
  network-exposed, but on a shared machine another local user could reach the
  port. Don't pass `--host 0.0.0.0`.
- **Large-library figures stop at 20,000 tracks.** That is what was measured.
  Paging makes per-view cost flat, but 50,000 was not tested and isn't claimed.

---

## Roadmap

Roughly in order of usefulness, not commitment.

**Next**
- Verify real audio output on hardware; fix whatever `AlsaSink` gets wrong
- Verify MPRIS with `playerctl` and a desktop panel
- Run the GTK4 front-end and make it work
- Test on real Raspberry Pi hardware and publish honest numbers
- Add an ALAC fixture and close that gap

**After that**
- Album-gain ReplayGain in addition to track gain
- Encoder-delay compensation for sample-exact MP3/AAC gapless
- Optional tag editor with an explicit, clearly-scoped write path
- Smart/dynamic playlists and sort options in list views
- Multi-select in track lists for bulk queue and playlist operations
- Configurable audio device selection in Settings
- `.m3u` / `.pls` playlist import and export

**Maybe**
- Optional `libmpv` backend for gapless handled natively
- Lyrics display from local `.lrc` files
- Last.fm scrobbling (strictly opt-in, off by default)
- Flatpak or AUR packaging

Not planned: online metadata lookup by default, telemetry, accounts, or
anything requiring an internet connection for local playback.

---

## Data and safety

- Music files are opened read-only. Nothing writes to them, ever.
- "Remove from library" deletes a database row. It never deletes a file.
- The database and artwork cache live in `$XDG_DATA_HOME/harmonia`
  (default `~/.local/share/harmonia`). No paths are hard-coded to a home
  directory.
- No network access is required or attempted for local playback. No telemetry,
  no online lookups.
- Cover art is served only from inside the cache directory; paths outside it
  are rejected.
- Opening a containing folder uses a list-form `subprocess` call, so filenames
  containing quotes or spaces cannot be injected into a shell.

To reset everything, delete `~/.local/share/harmonia`. That removes the
database and artwork cache only — your music is untouched.

---

## Troubleshooting

**No sound, but the position counter moves.** See
[Audio-output limitations](#audio-output-limitations). Settings reports whether
a device was found.

**`ffmpeg not found`.** Install it. `build.sh` fails early on purpose rather
than at the first attempt to play.

**Media keys do nothing.** Install `python-dbus-next` and restart. Check with
`playerctl --list-all`; Harmonia appears as `harmonia`.

**Scanning missed files.** Only known audio extensions are scanned. Check the
scan summary's failure count, and run with `-v` to log per-file parse warnings.

**New files aren't detected automatically.** inotify has a per-user watch limit
(often 8192). On a deep library it may be hit — the log says so and it falls
back to polling. Raise it with:
```bash
echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/40-max-user-watches.conf
sudo sysctl -p
```

**Port already in use.** Harmonia probes upward from 8770; override with
`--port`.

**A corrupt file breaks something.** It shouldn't — that's explicitly tested —
but the metadata dialog shows per-track parse warnings and the scan summary
counts unreadable files. Please open an issue with the file's format.

---

## Contributing

Issues and pull requests are welcome, particularly from anyone who can test the
parts this project could not: real audio hardware, MPRIS on a live session bus,
GTK4, Raspberry Pi, and unusual tags from real-world music collections.

Before submitting, run `./build.sh` and make sure all 77 tests still pass.
Please don't change a test purely to make it pass — if a test fails, that's
information.

## License

MIT — see [LICENSE](LICENSE).

