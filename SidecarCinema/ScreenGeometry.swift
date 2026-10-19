import AppKit
import CoreGraphics

struct DisplayChoice: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let resolution: String
    let millimeters: CGSize

    var label: String { "\(name) · \(resolution)" }

    static func connected() -> [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = number.uint32Value
            let mode = CGDisplayCopyDisplayMode(displayID)
            let width = mode?.pixelWidth ?? Int(screen.frame.width)
            let height = mode?.pixelHeight ?? Int(screen.frame.height)
            let measured = CGDisplayScreenSize(displayID)
            let millimeters = measured.width > 0 && measured.height > 0
                ? measured
                : CGSize(width: screen.frame.width, height: screen.frame.height)
            let name = screen.localizedName.isEmpty ? "Display \(displayID)" : screen.localizedName
            return DisplayChoice(id: displayID, name: name, resolution: "\(width) × \(height)", millimeters: millimeters)
        }
    }

    func nsScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}

struct DisplayCrop {
    let normalizedX: CGFloat
    let normalizedWidth: CGFloat
    let normalizedY: CGFloat
    let normalizedHeight: CGFloat
    let physicalAspect: CGFloat
    let canvasAspect: CGFloat

    static func pair(left: DisplayChoice, right: DisplayChoice, gapMillimeters: Double) -> (DisplayCrop, DisplayCrop) {
        let leftWidth = max(left.millimeters.width, 1)
        let rightWidth = max(right.millimeters.width, 1)
        let height = max(max(left.millimeters.height, right.millimeters.height), 1)
        let gap = max(0, gapMillimeters)
        let totalWidth = leftWidth + gap + rightWidth
        let leftHeight = min(left.millimeters.height, height)
        let rightHeight = min(right.millimeters.height, height)
        let leftCrop = DisplayCrop(normalizedX: 0, normalizedWidth: leftWidth / totalWidth,
                                  normalizedY: (height - leftHeight) / (2 * height), normalizedHeight: leftHeight / height,
                                  physicalAspect: leftWidth / leftHeight, canvasAspect: totalWidth / height)
        let rightCrop = DisplayCrop(normalizedX: (leftWidth + gap) / totalWidth, normalizedWidth: rightWidth / totalWidth,
                                   normalizedY: (height - rightHeight) / (2 * height), normalizedHeight: rightHeight / height,
                                   physicalAspect: rightWidth / rightHeight, canvasAspect: totalWidth / height)
        return (leftCrop, rightCrop)
    }
}
