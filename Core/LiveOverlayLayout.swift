import Foundation

public enum LiveOverlayWidget: String, CaseIterable, Codable, Sendable {
    case heartRate, strain, recovery, sleep, calories, timer, heartRateGraph
    public var title: String {
        switch self {
        case .heartRate: return "Live HR"
        case .strain: return "Strain"
        case .recovery: return "Recovery"
        case .sleep: return "Sleep"
        case .calories: return "Calories"
        case .timer: return "Timer"
        case .heartRateGraph: return "HR Graph"
        }
    }
}
public enum LiveCanvasAspect: String, CaseIterable, Codable, Sendable {
    case full, condensed
    public var ratio: Double { self == .full ? 9.0 / 16 : 4.0 / 5 }
}
public struct LiveOverlayPlacement: Codable, Equatable, Sendable {
    public var scale: Double = 1
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.scale = scale; self.offsetX = offsetX; self.offsetY = offsetY
    }
}
public struct LiveOverlayRect: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// One normalized layout drives gestures, camera preview, photos, transparent
/// images and video. Editing presentation never changes measured values.
public struct LiveOverlayLayout: Codable, Equatable, Sendable {
    public var aspect: LiveCanvasAspect = .full
    public var photoScale: Double = 1
    public var photoOffsetX: Double = 0
    public var photoOffsetY: Double = 0
    public var placements: [String: LiveOverlayPlacement] = [:]
    public var hidden: Set<String> = ["live.heartRateGraph"]
    public init() { }
    public var boundedPhotoScale: Double { photoScale.isFinite ? min(8, max(0.6, photoScale)) : 1 }
    public mutating func resetPhoto() { photoScale = 1; photoOffsetX = 0; photoOffsetY = 0 }
    public static func widgets(for mode: CameraOverlayMode) -> [LiveOverlayWidget] {
        switch mode {
        case .overview: return [.strain, .recovery, .sleep]
        case .strain: return [.strain]
        case .recovery: return [.recovery]
        case .sleep: return [.sleep]
        case .live: return [.heartRate, .strain, .calories, .timer, .heartRateGraph]
        }
    }
    public func key(_ widget: LiveOverlayWidget, mode: CameraOverlayMode) -> String { mode.rawValue + "." + widget.rawValue }
    public func isVisible(_ widget: LiveOverlayWidget, mode: CameraOverlayMode) -> Bool {
        Self.widgets(for: mode).contains(widget) && !hidden.contains(key(widget, mode: mode))
    }
    public mutating func setVisible(_ visible: Bool, widget: LiveOverlayWidget, mode: CameraOverlayMode) {
        if visible { hidden.remove(key(widget, mode: mode)) } else { hidden.insert(key(widget, mode: mode)) }
    }
    public func placement(_ widget: LiveOverlayWidget, mode: CameraOverlayMode) -> LiveOverlayPlacement {
        placements[key(widget, mode: mode)] ?? .init()
    }
    public mutating func reset(mode: CameraOverlayMode) {
        placements = placements.filter { !$0.key.hasPrefix(mode.rawValue + ".") }
        hidden = hidden.filter { !$0.hasPrefix(mode.rawValue + ".") }
        if mode == .live { hidden.insert(key(.heartRateGraph, mode: mode)) }
    }
    public mutating func setPlacement(_ proposed: LiveOverlayPlacement, widget: LiveOverlayWidget, mode: CameraOverlayMode, width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        placements[key(widget, mode: mode)] = proposed
        let base = baseFrame(widget, mode: mode, width: width, height: height)
        let visible = frame(widget, mode: mode, width: width, height: height)
        placements[key(widget, mode: mode)] = .init(scale: visible.width / base.width,
            offsetX: (visible.midX - base.midX) / width, offsetY: (visible.midY - base.midY) / height)
    }
    public func baseFrame(_ widget: LiveOverlayWidget, mode: CameraOverlayMode, width w: Double, height h: Double) -> LiveOverlayRect {
        if mode == .overview {
            let index = Self.widgets(for: mode).firstIndex(of: widget) ?? 0
            return .init(x: w * (0.06 + Double(index) * 0.295), y: min(h * 0.713, h - w * 0.474) - w * 0.111, width: w * 0.29, height: w * 0.36)
        }
        if mode != .live { return .init(x: w * 0.125, y: h / 2 - w * 0.375, width: w * 0.75, height: w * 0.75) }
        switch widget {
        case .heartRate: return .init(x: w * 0.358, y: h * 0.718 - w * 0.142, width: w * 0.284, height: w * 0.284)
        case .strain: return .init(x: w * 0.71, y: h * 0.066, width: w * 0.255, height: h * 0.156)
        case .calories: return .init(x: w * 0.71, y: h * 0.236, width: w * 0.255, height: h * 0.156)
        case .timer: return .init(x: w * 0.71, y: h * 0.406, width: w * 0.255, height: h * 0.06)
        case .heartRateGraph: return .init(x: w * 0.04, y: min(h * 0.82, h - w * 0.25 - h * 0.075), width: w * 0.92, height: h * 0.075)
        default: return .init(x: 0, y: 0, width: w, height: h)
        }
    }
    public func frame(_ widget: LiveOverlayWidget, mode: CameraOverlayMode, width w: Double, height h: Double) -> LiveOverlayRect {
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return .init(x: 0, y: 0, width: 0, height: 0) }
        let base = baseFrame(widget, mode: mode, width: w, height: h)
        let p = placement(widget, mode: mode)
        let scale = min(min(w / base.width, h / base.height), max(0.35, min(1.65, p.scale.isFinite ? p.scale : 1)))
        let width = base.width * scale, height = base.height * scale
        let dx = p.offsetX.isFinite ? p.offsetX * w : 0, dy = p.offsetY.isFinite ? p.offsetY * h : 0
        let x = min(w - width, max(0, base.midX + dx - width / 2))
        let y = min(h - height, max(0, base.midY + dy - height / 2))
        return .init(x: x, y: y, width: width, height: height)
    }
}
