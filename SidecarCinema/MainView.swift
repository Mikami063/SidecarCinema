import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var cinema: CinemaController
    @AppStorage("leftDisplayID") private var leftDisplayID = 0
    @AppStorage("rightDisplayID") private var rightDisplayID = 0
    @AppStorage("gapMillimeters") private var gapMillimeters = 0.0
    @State private var displays: [DisplayChoice] = []
    @State private var isDropTargeted = false

    private var selectedIDsValid: Bool {
        displays.count >= 2 && leftDisplayID != rightDisplayID && displays.contains { $0.id == UInt32(leftDisplayID) } && displays.contains { $0.id == UInt32(rightDisplayID) }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("SidecarCinema").font(.system(size: 25, weight: .semibold))
                Text("One video, shared across two displays").foregroundStyle(.secondary)
            }
            .padding(.top, 22)

            videoPicker

            if let url = cinema.videoURL {
                HStack(spacing: 10) {
                    Button(cinema.isPlaying ? "Pause" : "Play") { cinema.togglePlayback() }
                    Button("−10 sec") { cinema.seek(by: -10) }
                    Button("+10 sec") { cinema.seek(by: 10) }
                    Text("\(cinema.formatTime(cinema.currentTime)) / \(cinema.formatTime(cinema.duration))")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Text(url.lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 24)
            }

            settings

            if let error = cinema.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .onAppear(perform: refreshDisplays)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: acceptDrop)
    }

    private var videoPicker: some View {
        VStack(spacing: 8) {
            Image(systemName: "film").font(.system(size: 30)).foregroundStyle(.secondary)
            Text(cinema.videoURL == nil ? "Drop an MP4 here" : "Drop another video here")
                .font(.headline)
            Button("Open Video…", action: openVideo)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(isDropTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Display assignment").font(.headline)
                Spacer()
                Button("Refresh") { refreshDisplays() }
            }
            HStack {
                Text("Left screen").frame(width: 100, alignment: .leading)
                displayPicker(selection: $leftDisplayID)
            }
            HStack {
                Text("Right screen").frame(width: 100, alignment: .leading)
                displayPicker(selection: $rightDisplayID)
            }
            HStack {
                Text("Bezel / gap")
                Slider(value: $gapMillimeters, in: 0...80, step: 1)
                Text("\(Int(gapMillimeters)) mm").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            Text("Choose Mac on the left and Sidecar iPad on the right. Gap compensation hides the part of the image behind the physical bezel.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(cinema.dualScreenActive ? "Dual Screen Active" : "Start Dual Screen") {
                    cinema.startDualScreen(leftID: UInt32(leftDisplayID), rightID: UInt32(rightDisplayID), gapMillimeters: gapMillimeters)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectedIDsValid || cinema.videoURL == nil || cinema.dualScreenActive)
                if cinema.dualScreenActive {
                    Button("Exit (Esc)") { cinema.exitDualScreen() }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private func displayPicker(selection: Binding<Int>) -> some View {
        Picker("Display", selection: selection) {
            ForEach(displays) { display in
                Text(display.label).tag(Int(display.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(displays.isEmpty)
    }

    private func refreshDisplays() {
        displays = DisplayChoice.connected()
        if displays.count >= 2 {
            let ids = displays.map(\.id)
            if !ids.contains(UInt32(leftDisplayID)) { leftDisplayID = Int(ids[0]) }
            if !ids.contains(UInt32(rightDisplayID)) || rightDisplayID == leftDisplayID { rightDisplayID = Int(ids[1]) }
        } else if let only = displays.first {
            leftDisplayID = Int(only.id)
        }
    }

    private func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { cinema.open(url) }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in cinema.open(url) }
        }
        return true
    }
}
