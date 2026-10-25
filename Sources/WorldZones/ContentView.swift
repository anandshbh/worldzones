import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var geometry: PanelGeometry
    @StateObject private var reorder = ReorderState()

    private let maxVisibleRows = 6
    private static let listSpace = "zoneList"
    private static let settle = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// Custom drag-to-reorder: the card follows the cursor and the others spring aside. (System
    /// drag-and-drop drew a translucent snapshot over the card, which looked doubled and lagged.)
    private func reorderGesture(for zone: Zone) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if model.draggingZoneID == nil {
                    model.draggingZoneID = zone.id
                    NSCursor.closedHand.push()
                }
                guard model.draggingZoneID == zone.id else { return }
                // The dragged card tracks the cursor 1:1; only the cards around it animate.
                reorder.translation = value.translation.height
                let target = reorder.targetIndex(for: zone, in: model.zones)
                if target != reorder.target {
                    withAnimation(Self.settle) { reorder.target = target }
                }
            }
            .onEnded { _ in
                guard model.draggingZoneID == zone.id else { return }
                NSCursor.pop()
                let target = reorder.target ?? model.zones.firstIndex(of: zone) ?? 0
                // Glide into the slot, then commit the new order with no animation: the
                // committed layout matches what's on screen, so nothing jumps.
                withAnimation(Self.settle) {
                    reorder.translation = reorder.restingTranslation(for: zone, to: target, in: model.zones)
                } completion: {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        model.moveZone(zone, to: target)
                        reorder.reset()
                        model.draggingZoneID = nil
                    }
                }
            }
    }

    var body: some View {
        Group {
            switch model.page {
            case .add:
                AddZoneView(isPresented: Binding(get: { model.page == .add }, set: { if !$0 { model.page = .zones } }))
            case .settings:
                SettingsView()
            case .zones:
                VStack(spacing: 0) {
                    Header()
                    zoneList
                    Footer()
                }
                .background {
                    // Keeps ⌘Q working now that Quit lives on the Settings page.
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                        .opacity(0)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: StatusPanelController.width)
        .padding(.top, PopoverShape.arrowHeight)
        .background(PanelBackground(style: model.glassStyle))
        .clipShape(PopoverShape(arrowX: geometry.arrowX))
    }

    @ViewBuilder
    private var zoneList: some View {
        let rows = VStack(spacing: 6) {
            ForEach(model.zones) { zone in
                let dragging = model.draggingZoneID == zone.id
                ZoneRow(zone: zone)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: RowFramesKey.self, value: [zone.id: geo.frame(in: .named(Self.listSpace))])
                    })
                    // Cards are translucent glass; the lifted one gets a solid backing so the card
                    // it passes over doesn't show through and mix the two cards' text.
                    .background {
                        if dragging {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                    .scaleEffect(dragging ? 1.03 : 1)
                    .shadow(color: .black.opacity(dragging ? 0.3 : 0), radius: 12, y: 6)
                    .offset(y: reorder.offset(for: zone, in: model.zones, dragging: model.draggingZoneID))
                    .zIndex(dragging ? 1 : 0)
                    .gesture(reorderGesture(for: zone))
            }
        }
        .padding(.horizontal, 10)
        .coordinateSpace(name: Self.listSpace)
        // Measured frames include the drag offsets, so freeze them while a drag is in progress;
        // otherwise the dragged card counts its own movement twice and the target slot jitters.
        .onPreferenceChange(RowFramesKey.self) { if model.draggingZoneID == nil { reorder.frames = $0 } }
        // The panel closing mid-drag clears draggingZoneID; drop the half-done drag with it.
        .onChange(of: model.draggingZoneID) { if model.draggingZoneID == nil { reorder.reset() } }

        if model.zones.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text("No time zones yet").font(Theme.title(13, .medium)).foregroundStyle(.secondary)
                Button("Add a City…") { model.page = .add }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if model.zones.count > maxVisibleRows {
            ScrollView { rows.padding(.vertical, 2) }
                .scrollIndicators(.never)
                .frame(height: CGFloat(maxVisibleRows) * (model.showTimeline ? 88 : 62))
        } else {
            rows
        }
    }
}

private struct Header: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("World Zones").font(Theme.title(15, .bold))
                Text(Fmt.string(model.now, "EEEE, MMMM d", .current))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CircleIconButton(symbol: "plus", help: "Add City (⌘N)") { model.page = .add }
                .keyboardShortcut("n")
            CircleIconButton(symbol: "slider.horizontal.3", help: "Settings (⌘,)") { model.page = .settings }
                .keyboardShortcut(",")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// Per-row UI state (`@State` needs a macro plugin the Command Line Tools don't ship).
final class RowState: ObservableObject {
    @Published var hovering = false
    @Published var renaming = false
    @Published var draft = ""
    @Published var copied = false
}

struct ZoneRow: View {
    let zone: Zone
    @EnvironmentObject var model: AppModel
    @StateObject private var state = RowState()
    @FocusState private var nameFocused: Bool

    var body: some View {
        let date = model.displayDate
        let tz = zone.timeZone
        let hour = Fmt.hour(date, tz)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                DayPhaseBadge(hour: hour)

                VStack(alignment: .leading, spacing: 2) {
                    if state.renaming {
                        TextField("Name", text: $state.draft)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .onSubmit(commitRename)
                            .onExitCommand { state.renaming = false }
                            .frame(maxWidth: 170)
                    } else {
                        HStack(spacing: 4) {
                            Text(zone.displayName)
                                .font(Theme.title(13.5))
                                .lineLimit(1)
                            if zone.isLocal {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            if model.isInMenuBar(zone) {
                                Image(systemName: "menubar.rectangle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accent)
                                    .help("Shown in the menu bar")
                            }
                        }
                    }
                    Text(subtitle(tz, date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Fills the free space; the hover controls float over it instead of taking room,
                // which used to squeeze the time column, wrap its text and make the cards jump.
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if state.hovering && !state.renaming && model.draggingZoneID == nil {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 18)
                                .help("Drag to reorder")
                            CircleIconButton(symbol: state.copied ? "checkmark" : "doc.on.doc", help: "Copy time", size: 22) { copyTime() }
                            CircleIconButton(symbol: "xmark", help: "Remove", size: 22) { model.remove(zone) }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                    }
                }

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(Fmt.time(date, tz, use24Hour: model.use24Hour, seconds: model.showSeconds && !model.isScrubbing))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(model.isScrubbing ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                        if !model.use24Hour {
                            Text(Fmt.string(date, "a", tz))
                                .font(Theme.title(11, .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    dayLabel(tz, date)
                }
                .fixedSize()
            }

            if model.showTimeline {
                DayStrip(timeZone: tz)
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        // While reordering, only the lifted card stays highlighted; cards sliding under the cursor don't flash.
        .glassCard(highlighted: model.draggingZoneID == nil ? state.hovering : model.draggingZoneID == zone.id)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { state.hovering = h } }
        .contextMenu {
            Button("Copy Time") { copyTime() }
            Button("Rename…") { startRename() }
            Button("Show in Menu Bar") { model.showInMenuBar(zone) }
                .disabled(model.isInMenuBar(zone))
            Divider()
            Button("Move Up") { model.move(zone, by: -1) }
                .disabled(zone.id == model.zones.first?.id)
            Button("Move Down") { model.move(zone, by: 1) }
                .disabled(zone.id == model.zones.last?.id)
            Divider()
            Button("Remove", role: .destructive) { model.remove(zone) }
        }
    }

    private func subtitle(_ tz: TimeZone, _ date: Date) -> String {
        let abbr = Fmt.abbreviation(tz, at: date)
        let prefix = zone.flag.map { "\($0) " } ?? ""
        return prefix + (zone.isLocal ? "Local · \(abbr)" : "\(abbr) · \(Fmt.relativeOffset(tz, at: date))")
    }

    @ViewBuilder
    private func dayLabel(_ tz: TimeZone, _ date: Date) -> some View {
        let delta = Fmt.dayDelta(tz, at: date, today: model.now)
        let day = Fmt.string(date, "EEE, MMM d", tz)
        switch delta {
        case 0:
            Text(day).font(.system(size: 11)).foregroundStyle(.secondary)
        default:
            let word = delta == 1 ? "Tomorrow" : delta == -1 ? "Yesterday" : (delta > 0 ? "+\(delta)d" : "\(delta)d")
            Text("\(word) · \(day)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(delta > 0 ? Color.teal : Color.pink)
        }
    }

    private func copyTime() {
        model.copy(model.summary(for: zone, at: model.displayDate))
        state.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { state.copied = false }
    }

    private func startRename() {
        state.draft = zone.displayName
        state.renaming = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        model.rename(zone, to: state.draft)
        state.renaming = false
    }
}

/// Live state of a drag-to-reorder; the zone order itself only changes when the drag ends.
final class ReorderState: ObservableObject {
    @Published var translation: CGFloat = 0
    /// Slot the dragged card would land in.
    @Published var target: Int?
    var frames: [UUID: CGRect] = [:]

    private static let spacing: CGFloat = 6

    func reset() {
        translation = 0
        target = nil
    }

    /// Nearest resting slot to the dragged card's current center.
    func targetIndex(for zone: Zone, in zones: [Zone]) -> Int? {
        guard let frame = frames[zone.id] else { return nil }
        let center = frame.midY + translation
        return zones.indices.min { abs((frames[zones[$0].id]?.midY ?? 0) - center) < abs((frames[zones[$1].id]?.midY ?? 0) - center) }
    }

    /// Translation that puts the dragged card exactly in slot `target`.
    func restingTranslation(for zone: Zone, to target: Int, in zones: [Zone]) -> CGFloat {
        guard let frame = frames[zone.id], let from = zones.firstIndex(of: zone),
              let slot = frames[zones[target].id] else { return 0 }
        return target > from ? slot.maxY - frame.maxY : slot.minY - frame.minY
    }

    /// The dragged card follows the cursor; cards between its old and new slot shift one slot over.
    func offset(for zone: Zone, in zones: [Zone], dragging: UUID?) -> CGFloat {
        guard let dragging, let from = zones.firstIndex(where: { $0.id == dragging }) else { return 0 }
        if zone.id == dragging { return translation }
        guard let target, let i = zones.firstIndex(of: zone), let height = frames[dragging]?.height else { return 0 }
        let shift = height + Self.spacing
        if from < target, i > from, i <= target { return -shift }
        if target < from, i >= target, i < from { return shift }
        return 0
    }
}

private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Round gradient badge showing whether it's day, dawn/dusk or night in a zone.
struct DayPhaseBadge: View {
    let hour: Int

    var body: some View {
        let (symbol, colors): (String, [Color]) = switch hour {
        case 6..<8: ("sunrise.fill", [Color(red: 1, green: 0.62, blue: 0.4), Color(red: 0.98, green: 0.4, blue: 0.55)])
        case 8..<17: ("sun.max.fill", [Color(red: 1, green: 0.8, blue: 0.25), Color(red: 1, green: 0.55, blue: 0.15)])
        case 17..<20: ("sunset.fill", [Color(red: 1, green: 0.5, blue: 0.35), Color(red: 0.75, green: 0.3, blue: 0.6)])
        default: ("moon.stars.fill", [Color(red: 0.35, green: 0.35, blue: 0.85), Color(red: 0.2, green: 0.15, blue: 0.45)])
        }
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: colors[1].opacity(0.35), radius: 3, y: 1)
    }
}

/// 24 aligned hour cells per zone; the same column is the same instant in every row.
struct DayStrip: View {
    let timeZone: TimeZone
    @EnvironmentObject var model: AppModel

    static let columns = 24
    static let hoursBefore = 11

    var body: some View {
        let date = model.displayDate
        let hourStart = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        let start = hourStart.addingTimeInterval(-Double(Self.hoursBefore) * 3600)
        let progress = date.timeIntervalSince(hourStart) / 3600

        GeometryReader { geo in
            let w = geo.size.width / CGFloat(Self.columns)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<Self.columns, id: \.self) { i in
                        cell(at: start.addingTimeInterval(Double(i) * 3600), width: w, height: geo.size.height)
                    }
                }
                .clipShape(Capsule(style: .continuous))

                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: geo.size.height + 6)
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
                    .offset(x: (CGFloat(Self.hoursBefore) + progress) * w - 1.5, y: -3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func cell(at colDate: Date, width: CGFloat, height: CGFloat) -> some View {
        let h = Fmt.hour(colDate, timeZone)
        let label: String
        if h == 0 {
            label = String(Fmt.string(colDate, "EEE", timeZone).prefix(2))
        } else if model.use24Hour {
            label = "\(h)"
        } else {
            label = "\(h % 12 == 0 ? 12 : h % 12)"
        }
        return Text(label)
            .font(.system(size: 8.5, weight: h == 0 ? .bold : .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Self.isNight(h) ? Color.white.opacity(0.85) : Color.primary.opacity(0.75))
            .frame(width: width, height: height)
            .background(Self.color(for: h))
            .overlay(alignment: .leading) {
                if h == 0 { Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 1) }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.jump(to: colDate) }
            .help(Fmt.string(colDate, model.use24Hour ? "EEE HH:mm" : "EEE h:mm a", timeZone))
    }

    static func isNight(_ h: Int) -> Bool { h < 6 || h >= 22 }

    static func color(for h: Int) -> Color {
        switch h {
        case 9..<18: return Color(red: 0.3, green: 0.82, blue: 0.6).opacity(0.5)
        case 6..<9, 18..<22: return Color(red: 0.4, green: 0.7, blue: 0.95).opacity(0.3)
        default: return Color(red: 0.32, green: 0.3, blue: 0.75).opacity(0.7)
        }
    }
}

private struct Footer: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.isScrubbing ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .help("Drag to see other times")
            Slider(value: Binding(
                get: { model.offsetMinutes },
                set: { model.offsetMinutes = ($0 / 15).rounded() * 15 }
            ), in: -1440...1440)
            .controlSize(.mini)
            if model.isScrubbing {
                Button { model.offsetMinutes = 0 } label: {
                    Text("\(model.offsetLabel) · Now")
                        .font(Theme.title(11, .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Back to now (Esc)")
            } else {
                Text("Now")
                    .font(Theme.title(11, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: 12)
        .padding(10)
    }
}
