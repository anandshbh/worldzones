import AppKit
import ServiceManagement
import SwiftUI

struct Zone: Identifiable, Codable, Hashable {
    var id = UUID()
    var identifier: String
    var label: String
    /// Follows the system time zone instead of a fixed identifier.
    var isLocal = false

    var timeZone: TimeZone {
        if isLocal { return .current }
        return TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    var flag: String? { ZoneCatalog.flag(for: timeZone.identifier) }

    var displayName: String {
        if isLocal && label.isEmpty { return ZoneCatalog.cityName(for: TimeZone.current.identifier) }
        return label
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, time, flagTime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: return "Icon"
        case .time: return "Time"
        case .flagTime: return "Flag & Time"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// How see-through the popover is.
enum GlassStyle: String, CaseIterable, Identifiable {
    case clear, regular, frosted
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Page { case zones, add, settings }

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let zones = "zones"
        static let use24Hour = "use24Hour"
        static let showSeconds = "showSeconds"
        static let showTimeline = "showTimeline"
        static let menuBarStyle = "menuBarStyle"
        static let menuBarZoneID = "menuBarZoneID"
        static let menuBarSecondZoneID = "menuBarSecondZoneID"
        static let blinkSeparator = "blinkSeparator"
        static let appearance = "appearance"
        static let glassStyle = "glassStyle"
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    @Published var now = Date()
    @Published var page: Page = .zones
    /// The card being dragged to reorder, if any.
    @Published var draggingZoneID: UUID?
    /// Scrub offset from "now", in minutes.
    @Published var offsetMinutes: Double = 0

    @Published var zones: [Zone] { didSet { saveZones() } }
    @Published var use24Hour: Bool { didSet { defaults.set(use24Hour, forKey: Keys.use24Hour) } }
    @Published var showSeconds: Bool { didSet { defaults.set(showSeconds, forKey: Keys.showSeconds); now = Date() } }
    @Published var showTimeline: Bool { didSet { defaults.set(showTimeline, forKey: Keys.showTimeline) } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) } }
    @Published var menuBarZoneID: UUID? { didSet { defaults.set(menuBarZoneID?.uuidString, forKey: Keys.menuBarZoneID) } }
    /// Optional second city shown after a "|" in the menu bar; nil means off.
    @Published var menuBarSecondZoneID: UUID? { didSet { defaults.set(menuBarSecondZoneID?.uuidString, forKey: Keys.menuBarSecondZoneID) } }
    @Published var blinkSeparator: Bool { didSet { defaults.set(blinkSeparator, forKey: Keys.blinkSeparator); now = Date() } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); applyAppearance() } }
    @Published var glassStyle: GlassStyle { didSet { defaults.set(glassStyle.rawValue, forKey: Keys.glassStyle) } }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    init() {
        if let data = defaults.data(forKey: Keys.zones),
           let saved = try? JSONDecoder().decode([Zone].self, from: data), !saved.isEmpty {
            zones = saved
        } else {
            zones = AppModel.defaultZones()
        }
        use24Hour = defaults.object(forKey: Keys.use24Hour) as? Bool ?? false
        showSeconds = defaults.bool(forKey: Keys.showSeconds)
        showTimeline = defaults.object(forKey: Keys.showTimeline) as? Bool ?? true
        // "cityTime" was the pre-flag name of .flagTime.
        let savedStyle = defaults.string(forKey: Keys.menuBarStyle) == "cityTime" ? "flagTime" : defaults.string(forKey: Keys.menuBarStyle)
        menuBarStyle = MenuBarStyle(rawValue: savedStyle ?? "") ?? .icon
        menuBarZoneID = defaults.string(forKey: Keys.menuBarZoneID).flatMap(UUID.init(uuidString:))
        menuBarSecondZoneID = defaults.string(forKey: Keys.menuBarSecondZoneID).flatMap(UUID.init(uuidString:))
        blinkSeparator = defaults.bool(forKey: Keys.blinkSeparator)
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        glassStyle = GlassStyle(rawValue: defaults.string(forKey: Keys.glassStyle) ?? "") ?? .regular

        startTimer()
        // NSApp isn't guaranteed to exist yet while the App struct is being built.
        DispatchQueue.main.async { [weak self] in self?.applyAppearance() }
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSTimeZone.resetSystemTimeZone()
                self?.now = Date()
            }
        }
    }

    private static func defaultZones() -> [Zone] {
        let local = TimeZone.current.identifier
        let presets: [(String, String)] = [
            ("America/Los_Angeles", "San Francisco"),
            ("America/New_York", "New York"),
            ("Europe/London", "London"),
            ("Asia/Kolkata", "Bengaluru"),
            ("Asia/Tokyo", "Tokyo"),
        ]
        return [Zone(identifier: local, label: "", isLocal: true)]
            + presets.filter { $0.0 != local }.map { Zone(identifier: $0.0, label: $0.1) }
    }

    // MARK: Clock

    private func startTimer() {
        // Fire on whole seconds so the display flips in step with the system clock.
        let next = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970))
        let timer = Timer(fire: next, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let date = Date()
        let minuteChanged = Int(date.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60)
        if showSeconds || blinkSeparator || minuteChanged { now = date }
    }

    private func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    var isScrubbing: Bool { offsetMinutes != 0 }

    /// The instant every row displays: now, or the scrubbed time snapped to a quarter hour.
    var displayDate: Date {
        guard isScrubbing else { return now }
        let t = now.addingTimeInterval(offsetMinutes * 60).timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 900).rounded() * 900)
    }

    func jump(to date: Date) {
        offsetMinutes = (date.timeIntervalSince(now) / 60).rounded()
    }

    var offsetLabel: String {
        guard isScrubbing else { return "Now" }
        // Measure from now snapped to the same quarter-hour grid, so offsets read "+5h" not "+5h 5m".
        let snappedNow = (now.timeIntervalSince1970 / 900).rounded() * 900
        let total = Int(((displayDate.timeIntervalSince1970 - snappedNow) / 60).rounded())
        let sign = total >= 0 ? "+" : "−"
        let h = abs(total) / 60, m = abs(total) % 60
        if h == 0 { return "\(sign)\(m)m" }
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h \(m)m"
    }

    // MARK: Zones

    private func saveZones() {
        if let data = try? JSONEncoder().encode(zones) { defaults.set(data, forKey: Keys.zones) }
    }

    func add(identifier: String, label: String) {
        zones.append(Zone(identifier: identifier, label: label))
    }

    func remove(_ zone: Zone) {
        zones.removeAll { $0.id == zone.id }
        if menuBarZoneID == zone.id { menuBarZoneID = nil }
        if menuBarSecondZoneID == zone.id { menuBarSecondZoneID = nil }
    }

    func rename(_ zone: Zone, to name: String) {
        guard let i = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        zones[i].label = name.trimmingCharacters(in: .whitespaces)
    }

    func move(_ zone: Zone, by delta: Int) {
        guard let i = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        let j = i + delta
        guard zones.indices.contains(j) else { return }
        zones.swapAt(i, j)
    }

    /// Puts `zone` at index `target` (the end of a drag-to-reorder).
    func moveZone(_ zone: Zone, to target: Int) {
        guard let from = zones.firstIndex(where: { $0.id == zone.id }), from != target, zones.indices.contains(target) else { return }
        zones.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
    }

    // MARK: Catalog

    func contains(_ candidate: ZoneCandidate) -> Bool {
        zones.contains { !$0.isLocal && $0.identifier == candidate.identifier && $0.label == candidate.name }
    }

    /// Adds the city, or removes it if it's already in the list.
    func toggle(_ candidate: ZoneCandidate) {
        if let zone = zones.first(where: { !$0.isLocal && $0.identifier == candidate.identifier && $0.label == candidate.name }) {
            remove(zone)
        } else {
            add(identifier: candidate.identifier, label: candidate.name)
        }
    }

    func addAll(_ candidates: [ZoneCandidate]) {
        zones += candidates.filter { !contains($0) }.map { Zone(identifier: $0.identifier, label: $0.name) }
    }

    // MARK: Menu bar & clipboard

    /// The chosen menu bar city, falling back to the first row.
    var menuBarZone: Zone? {
        zones.first { $0.id == menuBarZoneID } ?? zones.first
    }

    var menuBarSecondZone: Zone? {
        guard let id = menuBarSecondZoneID, id != menuBarZone?.id else { return nil }
        return zones.first { $0.id == id }
    }

    func isInMenuBar(_ zone: Zone) -> Bool {
        menuBarStyle != .icon && (menuBarZone?.id == zone.id || menuBarSecondZone?.id == zone.id)
    }

    func showInMenuBar(_ zone: Zone) {
        menuBarZoneID = zone.id
        if menuBarStyle == .icon { menuBarStyle = .flagTime }
    }

    var menuBarText: String {
        guard let zone = menuBarZone else { return "--:--" }
        let text = [zone, menuBarSecondZone].compactMap { $0 }.map(menuBarEntry).joined(separator: "  |  ")
        // Blink by swapping ":" for a punctuation space (U+2008), which is exactly as wide in the
        // menu bar font, so the item doesn't shift.
        let colonHidden = blinkSeparator && Int(now.timeIntervalSince1970) % 2 == 1
        return colonHidden ? text.replacingOccurrences(of: ":", with: "\u{2008}") : text
    }

    private func menuBarEntry(_ zone: Zone) -> String {
        let time = Fmt.time(now, zone.timeZone, use24Hour: use24Hour, seconds: showSeconds, withPeriod: true)
        guard menuBarStyle == .flagTime else { return time }
        // Zones without a country (UTC) fall back to their name.
        return "\(zone.flag ?? zone.displayName) \(time)"
    }

    func summary(for zone: Zone, at date: Date) -> String {
        let tz = zone.timeZone
        let time = Fmt.time(date, tz, use24Hour: use24Hour, seconds: false, withPeriod: true)
        let day = Fmt.string(date, "EEE, MMM d", tz)
        return "\(zone.displayName): \(time), \(day) (\(Fmt.abbreviation(tz, at: date)))"
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyAll() {
        copy(zones.map { summary(for: $0, at: displayDate) }.joined(separator: "\n"))
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("WorldZones: launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
enum Fmt {
    private static var cache: [String: DateFormatter] = [:]

    static func string(_ date: Date, _ format: String, _ tz: TimeZone) -> String {
        let key = tz.identifier + "|" + format
        if let f = cache[key] { return f.string(from: date) }
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = tz
        cache[key] = f
        return f.string(from: date)
    }

    static func time(_ date: Date, _ tz: TimeZone, use24Hour: Bool, seconds: Bool, withPeriod: Bool = false) -> String {
        var format = use24Hour ? "HH:mm" : "h:mm"
        if seconds { format += ":ss" }
        if withPeriod && !use24Hour { format += " a" }
        return string(date, format, tz)
    }

    static func abbreviation(_ tz: TimeZone, at date: Date) -> String {
        tz.abbreviation(for: date) ?? tz.identifier
    }

    /// Offset of `tz` from the local zone, e.g. "+5:30h", "−3h", "same time".
    static func relativeOffset(_ tz: TimeZone, at date: Date) -> String {
        let diff = tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return "same time" }
        let sign = diff > 0 ? "+" : "−"
        let a = abs(diff), h = a / 3600, m = (a % 3600) / 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h):\(String(format: "%02d", m))h"
    }

    /// Calendar-day difference between `date` in `tz` and today in the local zone.
    static func dayDelta(_ tz: TimeZone, at date: Date, today: Date) -> Int {
        func dayNumber(_ d: Date, _ zone: TimeZone) -> Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = cal.dateComponents([.year, .month, .day], from: d)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            return Int((cal.date(from: c)?.timeIntervalSince1970 ?? 0) / 86400)
        }
        return dayNumber(date, tz) - dayNumber(today, .current)
    }

    static func hour(_ date: Date, _ tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }
}
