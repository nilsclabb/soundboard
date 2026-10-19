# Soundboard

A tiny soundboard that lives in the MacBook notch.

## Run

```sh
make run     # build, bundle into build/Soundboard.app, launch
make clean
```

Requires macOS 14+ and Xcode command line tools.

## Use

- Hover the notch → it swells. Click → the 8-pad board opens.
- Drop audio files on a pad (or click an empty pad to browse). Extra files fill the next empty pads.
- Drop a YouTube link on a pad, or press `⌘V` with one copied (fills the first empty pad). It downloads, then the trim window opens.
- Drag a pad onto another to swap them (or move it to an empty one).
- Click a pad or press `1`–`8` to play. `Space` or `Enter` stops whatever is playing. `Esc`, clicking elsewhere, or moving away closes it.
- `•••` on a pad → volume slider (relative to system volume), Trim… (start/end, the file is untouched), Move to another preset, or Delete. Right-click has Move to and Delete.
- Presets: the row above the pads. Click to switch (or `←`/`→`), `+` to add, right-click to rename or delete.
- Menu bar icon → Enabled (turns the notch off/on), Launch at Login, About, Quit.

Sounds are copied to `~/Library/Application Support/Soundboard/`.

## Grab a sound from YouTube

Needs `brew install yt-dlp ffmpeg`.

```sh
make sound URL="https://youtu.be/..."                      # whole video as mp3
make sound URL="https://youtu.be/..." START=0:05 END=0:08  # just that clip
```

Files land in `~/Downloads/Soundboard/` (Finder opens it), ready to drop on a pad.

## Cut a sound

```sh
make cut FILE=~/Downloads/Soundboard/name.mp3 START=0:05 END=0:08
```

Writes `name (cut).mp3` next to the original. Times can be `0:05`, `5`, or `5.5`.
