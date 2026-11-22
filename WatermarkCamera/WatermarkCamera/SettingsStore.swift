import Foundation

enum TimeMode: String {
    case current
    case custom
}

struct TorchPreset: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let level: Float
}

/// 使用 UserDefaults 持久化备注、时间模式、自定义时间与手电筒强度。
final class SettingsStore: ObservableObject {
    private enum Key {
        static let note = "wm.note"
        static let timeMode = "wm.timeMode"
        static let customDate = "wm.customDate"
        static let torchLevel = "wm.torchLevel"
    }

    /// 兼顾夜间照明、发热与续航的三档强度；实际亮度由 AVCaptureDevice 限制。
    static let torchPresets: [TorchPreset] = [
        TorchPreset(name: "低亮 · 省电", level: 0.35),
        TorchPreset(name: "标准 · 推荐", level: 0.65),
        TorchPreset(name: "高亮 · 更亮", level: 1.00)
    ]

    @Published var note: String {
        didSet { defaults.set(note, forKey: Key.note) }
    }

    @Published var timeMode: TimeMode {
        didSet { defaults.set(timeMode.rawValue, forKey: Key.timeMode) }
    }

    @Published var customDate: Date {
        didSet { defaults.set(customDate.timeIntervalSince1970, forKey: Key.customDate) }
    }

    @Published var torchLevel: Float {
        didSet { defaults.set(torchLevel, forKey: Key.torchLevel) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.note = defaults.string(forKey: Key.note) ?? ""
        self.timeMode = TimeMode(rawValue: defaults.string(forKey: Key.timeMode) ?? "") ?? .current
        let timestamp = defaults.double(forKey: Key.customDate)
        self.customDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
        let storedLevel = defaults.float(forKey: Key.torchLevel)
        self.torchLevel = storedLevel > 0 ? storedLevel : 0.65
    }

    func resetToCurrentTime() {
        timeMode = .current
    }
}
