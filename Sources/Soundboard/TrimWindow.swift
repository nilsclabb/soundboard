import AVFoundation
import SwiftUI

@MainActor
enum TrimWindow {
    private static var window: NSWindow?

    static func show(_ pad: Pad, store: PadStore) {
        guard let duration = try? AVAudioPlayer(contentsOf: store.url(for: pad)).duration else { return }
        window?.close()
        let peaks = peaks(of: store.url(for: pad), count: 240)
        let view = TrimView(pad: pad, duration: duration, peaks: peaks, store: store, start: pad.start ?? 0, end: pad.end ?? duration)
        let newWindow = NSWindow(contentViewController: NSHostingController(rootView: view))
        newWindow.title = "Trim “\(pad.name)”"
        newWindow.styleMask = [.titled, .closable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        NSApp.activate()
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
    }

    static func importLink(_ link: URL, to slot: Int, store: PadStore) {
        Task {
            do {
                if let pad = try await store.download(link, to: slot) { show(pad, store: store) }
            } catch {
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Loudest sample per bin, normalised so the loudest bin fills the height.
    private static func peaks(of url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        let binSize = max(frames / count, 1)
        let peaks = stride(from: 0, to: frames, by: binSize).map { first in
            (first..<min(first + binSize, frames)).reduce(Float(0)) { max($0, abs(samples[$1])) }
        }
        let loudest = peaks.max() ?? 0
        return loudest > 0 ? peaks.map { $0 / loudest } : peaks
    }
}

private struct TrimView: View {
    let pad: Pad
    let duration: Double
    let peaks: [Float]
    let store: PadStore
    @State var start: Double
    @State var end: Double
    private let minimumLength = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Timeline(peaks: peaks, duration: duration, start: $start, end: $end,
                     isPlaying: store.playing.contains(pad.id), playhead: { store.currentTime(id: pad.id) })
            HStack(spacing: 16) {
                label("Start", start)
                label("End", end)
                label("Length", end - start)
                Spacer()
                Button("Reset") { (start, end) = (0, duration) }
                Button("Preview") { store.play(id: pad.id) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: start) {
            if start > end - minimumLength { start = max(end - minimumLength, 0) }
            store.setTrim(id: pad.id, start: start, end: end)
        }
        .onChange(of: end) {
            if end < start + minimumLength { end = min(start + minimumLength, duration) }
            store.setTrim(id: pad.id, start: start, end: end)
        }
    }

    private func label(_ title: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatTime(seconds)).monospacedDigit()
        }
    }
}

private func formatTime(_ seconds: Double) -> String {
    String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
}

/// Ruler, waveform region and draggable start/end handles, laid out like a DAW timeline.
private struct Timeline: View {
    let peaks: [Float]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    let isPlaying: Bool
    let playhead: () -> Double?
    @State private var draggingStart: Bool?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (time: Double) in CGFloat(time / duration) * width }
            VStack(spacing: 4) {
                Ruler(duration: duration)
                    .frame(height: 16)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.22))
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                        .frame(width: x(end) - x(start))
                        .offset(x: x(start))
                    Waveform(peaks: peaks, selection: start / duration...end / duration)
                        .padding(.vertical, 6)
                    handle.offset(x: x(start) - 1)
                    handle.offset(x: x(end) - 1)
                    TimelineView(.animation(paused: !isPlaying)) { _ in
                        if isPlaying, let time = playhead() {
                            Rectangle().fill(.primary).frame(width: 1.5).offset(x: x(time))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    // Grabs whichever edge is nearer, so clicking anywhere moves the closest one.
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let time = min(max(Double(drag.location.x / width) * duration, 0), duration)
                            let movesStart = draggingStart ?? (abs(time - start) < abs(time - end))
                            draggingStart = movesStart
                            if movesStart { start = time } else { end = time }
                        }
                        .onEnded { _ in draggingStart = nil }
                )
            }
        }
        .frame(height: 110)
    }

    private var handle: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 8, height: 12)
            Rectangle().fill(Color.accentColor).frame(width: 2)
        }
        .frame(width: 2)
    }
}

private struct Ruler: View {
    let duration: Double

    var body: some View {
        Canvas { context, size in
            let step = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60].first { duration / $0 <= 8 } ?? 120
            for time in stride(from: 0, through: duration, by: step) {
                let x = CGFloat(time / duration) * size.width
                context.fill(Path(CGRect(x: x, y: size.height - 5, width: 1, height: 5)), with: .color(.secondary))
                if x < size.width - 24 {
                    context.draw(Text(formatTime(time)).font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 2, y: 0), anchor: .topLeading)
                }
            }
        }
    }
}

private struct Waveform: View {
    let peaks: [Float]
    let selection: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(max(peaks.count, 1))
            for (index, peak) in peaks.enumerated() {
                let height = max(CGFloat(peak) * size.height, 1)
                let bar = CGRect(x: CGFloat(index) * barWidth, y: (size.height - height) / 2,
                                 width: max(barWidth - 0.5, 0.5), height: height)
                let isKept = selection.contains((Double(index) + 0.5) / Double(peaks.count))
                context.fill(Path(bar), with: .color(isKept ? .primary.opacity(0.85) : .secondary.opacity(0.3)))
            }
        }
    }
}
