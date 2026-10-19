# Soundboard

An 8-pad soundboard that swells out of the MacBook notch.

## Run

Needs macOS 14+ and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/nilsclabb/soundboard.git
cd soundboard
make run
```

`make run` builds `build/Soundboard.app` and launches it. It lives in the menu bar, with no Dock icon. On Macs without a notch, hover the top centre of the screen.

YouTube import needs `brew install yt-dlp ffmpeg`.

## Use

- Hover the notch to preview, click to open the board.
- Add sounds: drop audio files or a YouTube link on a pad, click an empty pad, or `⌘V` a copied link.
- Play: click a pad or press `1`–`8`. `Space`/`Enter` stops all, `Esc` closes.
- Drag a pad onto another to swap them.
- `•••` on a pad: volume, trim, move to another preset, delete.
- Presets: the row above the pads. `←`/`→` switches, `+` adds, right-click renames or deletes.
- Menu bar icon: enable/disable, launch at login, quit.

Sounds and presets are stored in `~/Library/Application Support/Soundboard/`.

## Terminal helpers

```sh
make sound URL="https://youtu.be/..." [START=0:05 END=0:08]  # mp3 into ~/Downloads/Soundboard/
make cut FILE=path/to/sound.mp3 START=0:05 END=0:08          # writes "sound (cut).mp3"
```
PS: this is of course 120% entirely vibe coded
