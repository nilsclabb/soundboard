APP = build/Soundboard.app
SOUNDS = $(HOME)/Downloads/Soundboard

.PHONY: build run clean sound cut

build:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Soundboard $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)

run: build
	pkill -x Soundboard || true
	open $(APP)

clean:
	rm -rf .build build

# make sound URL=<youtube link> [START=0:05 END=0:08]
sound:
	yt-dlp -x --audio-format mp3 -o "$(SOUNDS)/%(title)s.%(ext)s" \
		$(if $(START),--download-sections "*$(START)-$(END)" --force-keyframes-at-cuts) "$(URL)"
	open "$(SOUNDS)"

# make cut FILE=<audio file> START=0:05 END=0:08  →  "<name> (cut).mp3" next to it
cut:
	f="$(FILE)"; ffmpeg -hide_banner -loglevel error -y -i "$$f" -ss $(START) -to $(END) "$${f%.*} (cut).mp3"
