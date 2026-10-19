import AVFoundation
import Observation

struct Pad: Codable, Identifiable {
    var name: String
    var fileName: String
    /// Relative to the system volume. Optional so files saved before it existed still decode.
    var volume: Float?
    var start: Double?
    var end: Double?

    var id: String { fileName }
}

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var pads: [Pad?] = Array(repeating: nil, count: PadStore.slotCount)
}

struct DownloadError: LocalizedError {
    var errorDescription: String?
}

private struct SlotRef: Hashable {
    var presetID: UUID
    var slot: Int
}

private struct Library: Codable {
    var presets: [Preset]
    var selectedID: UUID
}

@MainActor
@Observable
final class PadStore: NSObject {
    nonisolated static let slotCount = 8

    private(set) var presets: [Preset]
    private(set) var selectedID: UUID
    private(set) var playing: Set<String> = []
    private var downloads: Set<SlotRef> = []

    var pads: [Pad?] { presets[selectedIndex].pads }

    private let directory = URL.applicationSupportDirectory.appending(path: "Soundboard")
    private var players: [String: AVAudioPlayer] = [:]
    private var pendingStops: [String: Task<Void, Never>] = [:]

    private var indexURL: URL { directory.appending(path: "presets.json") }
    private var selectedIndex: Int { presets.firstIndex { $0.id == selectedID } ?? 0 }

    override init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = (try? Data(contentsOf: directory.appending(path: "presets.json")))
            .flatMap { try? JSONDecoder().decode(Library.self, from: $0) }
        let fallback = Preset(name: "Default")
        presets = library?.presets ?? [fallback]
        selectedID = library?.selectedID ?? fallback.id
    }

    func selectPreset(_ id: UUID) {
        selectedID = id
        save()
    }

    func selectAdjacentPreset(_ offset: Int) {
        let index = (selectedIndex + offset + presets.count) % presets.count
        selectPreset(presets[index].id)
    }

    func addPreset() -> Preset {
        let preset = Preset(name: "Preset \(presets.count + 1)")
        presets.append(preset)
        selectPreset(preset.id)
        return preset
    }

    func renamePreset(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
        save()
    }

    func deletePreset(_ id: UUID) {
        guard presets.count > 1, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].pads.compactMap { $0 }.forEach(discard)
        presets.remove(at: index)
        if selectedID == id { selectedID = presets[max(index - 1, 0)].id }
        save()
    }

    func assign(_ sources: [URL], startingAt slot: Int) {
        // A pad dragged onto another arrives as its own file URL; swap instead of importing a copy.
        if sources.count == 1, let from = pads.firstIndex(where: { $0.map(url(for:))?.path == sources[0].path }) {
            presets[selectedIndex].pads.swapAt(from, slot)
            return save()
        }
        let targets = [slot] + pads.indices.filter { $0 != slot && pads[$0] == nil }
        for (source, target) in zip(sources, targets) {
            assign(source, to: target, in: selectedID)
        }
    }

    func isDownloading(_ slot: Int) -> Bool {
        downloads.contains(SlotRef(presetID: selectedID, slot: slot))
    }

    /// Downloads a web page's audio with yt-dlp into the slot of the preset selected when it started.
    func download(_ link: URL, to slot: Int) async throws -> Pad? {
        let ref = SlotRef(presetID: selectedID, slot: slot)
        downloads.insert(ref)
        defer { downloads.remove(ref) }
        let file = try await Self.fetchAudio(link)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return assign(file, to: slot, in: ref.presetID)
    }

    private nonisolated static func fetchAudio(_ link: URL) async throws -> URL {
        // Apps launched from Finder don't get the shell's PATH, so look where Homebrew installs.
        guard let bin = ["/opt/homebrew/bin", "/usr/local/bin"]
            .first(where: { FileManager.default.isExecutableFile(atPath: "\($0)/yt-dlp") }) else {
            throw DownloadError(errorDescription: "yt-dlp isn't installed. Run: brew install yt-dlp ffmpeg")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let process = Process()
        process.executableURL = URL(filePath: "\(bin)/yt-dlp")
        process.arguments = ["-x", "--audio-format", "mp3", "--no-playlist", "--ffmpeg-location", bin,
                             "-o", folder.appending(path: "%(title)s.%(ext)s").path, link.absoluteString]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        return try await Task.detached {
            try process.run()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let file = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first else {
                throw DownloadError(errorDescription: message.split(separator: "\n").last.map(String.init) ?? "Download failed.")
            }
            return file
        }.value
    }

    @discardableResult
    private func assign(_ source: URL, to slot: Int, in presetID: UUID) -> Pad? {
        guard let index = presets.firstIndex(where: { $0.id == presetID }),
              (try? AVAudioPlayer(contentsOf: source)) != nil else { return nil }
        let pad = Pad(
            name: source.deletingPathExtension().lastPathComponent,
            fileName: "\(UUID().uuidString).\(source.pathExtension)"
        )
        guard (try? FileManager.default.copyItem(at: source, to: url(for: pad))) != nil else { return nil }
        if let old = presets[index].pads[slot] { discard(old) }
        presets[index].pads[slot] = pad
        save()
        return pad
    }

    func remove(_ slot: Int) {
        guard let pad = pads[slot] else { return }
        discard(pad)
        presets[selectedIndex].pads[slot] = nil
        save()
    }

    func setVolume(_ volume: Float, for slot: Int) {
        guard let pad = pads[slot] else { return }
        presets[selectedIndex].pads[slot]?.volume = volume
        players[pad.id]?.volume = volume
        save()
    }

    func setTrim(id: String, start: Double, end: Double) {
        for p in presets.indices {
            for slot in presets[p].pads.indices where presets[p].pads[slot]?.id == id {
                presets[p].pads[slot]?.start = start
                presets[p].pads[slot]?.end = end
            }
        }
        save()
    }

    func move(_ slot: Int, to presetID: UUID) {
        guard let pad = pads[slot],
              let target = presets.firstIndex(where: { $0.id == presetID }),
              let emptySlot = presets[target].pads.firstIndex(where: { $0 == nil }) else { return }
        presets[target].pads[emptySlot] = pad
        presets[selectedIndex].pads[slot] = nil
        save()
    }

    private func discard(_ pad: Pad) {
        players.removeValue(forKey: pad.id)?.stop()
        playing.remove(pad.id)
        try? FileManager.default.removeItem(at: url(for: pad))
    }

    func play(_ slot: Int) {
        guard pads.indices.contains(slot), let pad = pads[slot] else { return }
        play(pad)
    }

    func play(id: String) {
        guard let pad = presets.flatMap(\.pads).compactMap({ $0 }).first(where: { $0.id == id }) else { return }
        play(pad)
    }

    private func play(_ pad: Pad) {
        guard let player = player(for: pad) else { return }
        let start = pad.start ?? 0
        player.currentTime = start
        player.volume = pad.volume ?? 1
        player.play()
        playing.insert(pad.id)
        pendingStops.removeValue(forKey: pad.id)?.cancel()
        // AVAudioPlayer has no end time, so a trimmed end is enforced by stopping it.
        if let end = pad.end {
            pendingStops[pad.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end - start))
                guard !Task.isCancelled else { return }
                self?.players[pad.id]?.stop()
                self?.playing.remove(pad.id)
            }
        }
    }

    func currentTime(id: String) -> Double? {
        playing.contains(id) ? players[id]?.currentTime : nil
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
        playing.removeAll()
    }

    private func player(for pad: Pad) -> AVAudioPlayer? {
        if let player = players[pad.id] { return player }
        guard let player = try? AVAudioPlayer(contentsOf: url(for: pad)) else { return nil }
        player.delegate = self
        players[pad.id] = player
        return player
    }

    func url(for pad: Pad) -> URL {
        directory.appending(path: pad.fileName)
    }

    private func save() {
        try? JSONEncoder().encode(Library(presets: presets, selectedID: selectedID)).write(to: indexURL)
    }
}

extension PadStore: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let id = players.first(where: { $0.value === player })?.key {
            playing.remove(id)
        }
    }
}
