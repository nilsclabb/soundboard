import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchView: View {
    let controller: NotchController
    let store: PadStore

    var body: some View {
        let state = controller.state
        let size = controller.size(for: state)
        let (earRadius, cornerRadius): (CGFloat, CGFloat) = switch state {
        case .closed: (0, 10)
        case .hovered: (8, 14)
        case .open: (14, 24)
        }

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                NotchShape(earRadius: earRadius, cornerRadius: cornerRadius)
                    .fill(.black)
                    .shadow(color: .black.opacity(state == .open ? 0.45 : 0), radius: 14, y: 6)

                switch state {
                case .closed:
                    EmptyView()
                case .hovered:
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                case .open:
                    VStack(spacing: 10) {
                        PresetBar(store: store)
                        PadGrid(store: store)
                    }
                    .padding(.bottom, 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                }
            }
            .frame(width: size.width + 2 * earRadius, height: size.height)
            .opacity(state == .closed && !controller.hasNotch ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if state == .hovered { controller.open() }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Black body whose top corners flare outward so it reads as part of the menu bar.
private struct NotchShape: Shape {
    var earRadius: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, cornerRadius) }
        set { (earRadius, cornerRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let ear = earRadius, corner = cornerRadius
        let left = rect.minX + ear, right = rect.maxX - ear
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: left + corner, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - corner), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct PresetBar: View {
    let store: PadStore
    @State private var editingID: UUID?
    @State private var draftName = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.presets) { preset in
                    chip(for: preset)
                }
                Button {
                    startEditing(store.addPreset())
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("New preset")
            }
        }
        .frame(width: 392, height: 22)
        .onDisappear(perform: commitRename)
    }

    private func chip(for preset: Preset) -> some View {
        let isSelected = preset.id == store.selectedID
        return Group {
            if editingID == preset.id {
                TextField("Preset name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onAppear { isEditing = true }
                    .onSubmit(commitRename)
                    .onExitCommand { editingID = nil }
                    .onChange(of: isEditing) { if !isEditing { commitRename() } }
                    .frame(width: 90)
            } else {
                Text(preset.name)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.6))
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Capsule().fill(.white.opacity(isSelected ? 0.18 : 0.06)))
        .contentShape(Capsule())
        .onTapGesture { store.selectPreset(preset.id) }
        .contextMenu {
            Button("Rename") { startEditing(preset) }
            Button("Delete", role: .destructive) { confirmDelete(preset) }
                .disabled(store.presets.count == 1)
        }
    }

    private func startEditing(_ preset: Preset) {
        draftName = preset.name
        editingID = preset.id
    }

    private func commitRename() {
        guard let id = editingID else { return }
        store.renamePreset(id, to: draftName)
        editingID = nil
    }

    private func confirmDelete(_ preset: Preset) {
        guard preset.pads.contains(where: { $0 != nil }) else { return store.deletePreset(preset.id) }
        let alert = NSAlert()
        alert.messageText = "Delete “\(preset.name)”?"
        alert.informativeText = "Its sounds will be deleted too."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.deletePreset(preset.id)
        }
    }
}

private struct PadGrid: View {
    let store: PadStore
    private let columns = 4

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<PadStore.slotCount / columns, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        PadButton(slot: row * columns + column, store: store)
                    }
                }
            }
        }
    }
}

private struct PadButton: View {
    let slot: Int
    let store: PadStore
    @State private var isDropTargeted = false

    var body: some View {
        let pad = store.pads[slot]
        let isPlaying = pad.map { store.playing.contains($0.id) } ?? false

        ZStack(alignment: .topTrailing) {
            let button = Button {
                if pad == nil { chooseFile() } else { store.play(slot) }
            } label: {
                VStack(spacing: 4) {
                    Text("\(slot + 1)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                    if let pad {
                        Text(pad.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    } else if store.isDownloading(slot) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(width: 92, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPlaying ? Color.accentColor : .white.opacity(isDropTargeted ? 0.3 : pad == nil ? 0.05 : 0.12))
                )
                .scaleEffect(isPlaying ? 0.96 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPlaying)
            }
            .buttonStyle(.plain)

            if let pad {
                button.draggable(store.url(for: pad))
            } else {
                button
            }

            if let pad {
                Button {
                    showEditMenu(for: pad)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Edit sound")
            }
        }
        .help(pad?.name ?? "Drop audio files or a YouTube link here, or click to browse")
        .dropDestination(for: URL.self) { urls, _ in
            if let link = urls.first(where: { !$0.isFileURL }) {
                TrimWindow.importLink(link, to: slot, store: store)
            } else {
                store.assign(urls, startingAt: slot)
            }
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            if pad != nil { editActions }
        }
    }

    @ViewBuilder private var editActions: some View {
        let others = store.presets.filter { $0.id != store.selectedID }
        Menu("Move to") {
            ForEach(others) { preset in
                Button(preset.name) { store.move(slot, to: preset.id) }
                    .disabled(!preset.pads.contains { $0 == nil })
            }
        }
        .disabled(others.isEmpty)
        Divider()
        Button("Delete", role: .destructive) { store.remove(slot) }
    }

    // An AppKit menu, because SwiftUI menus can't hold a slider.
    private func showEditMenu(for pad: Pad) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let volume = NSMenuItem()
        let slider = NSHostingView(rootView: VolumeSlider(volume: pad.volume ?? 1) { store.setVolume($0, for: slot) })
        slider.frame.size = slider.fittingSize
        volume.view = slider
        menu.addItem(volume)
        menu.addItem(.separator())

        menu.addItem(ActionMenuItem("Trim…") { TrimWindow.show(pad, store: store) })

        let others = store.presets.filter { $0.id != store.selectedID }
        let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        moveTo.submenu = NSMenu()
        moveTo.submenu?.autoenablesItems = false
        for preset in others {
            let item = ActionMenuItem(preset.name) { store.move(slot, to: preset.id) }
            item.isEnabled = preset.pads.contains { $0 == nil }
            moveTo.submenu?.addItem(item)
        }
        moveTo.isEnabled = !others.isEmpty
        menu.addItem(moveTo)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Delete") { store.remove(slot) })

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            store.assign(panel.urls, startingAt: slot)
        }
    }
}

private struct VolumeSlider: View {
    @State var volume: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            Slider(value: $volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(width: 210)
        .onChange(of: volume) { onChange(volume) }
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used from nibs") }

    @objc private func run() { handler() }
}
