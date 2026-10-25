import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CircleIconButton(symbol: "chevron.left", help: "Back (Esc)") { model.page = .zones }
                    .keyboardShortcut(.cancelAction)
                Text("Settings").font(Theme.title(15, .bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 10) {
                section("Appearance") {
                    row("Theme", symbol: "paintpalette.fill", tint: .pink) {
                        Picker("", selection: $model.appearance) {
                            ForEach(AppAppearance.allCases) { Image(systemName: $0.symbol).help($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }
                    row("Glass", symbol: "drop.fill", tint: .cyan) {
                        Picker("", selection: $model.glassStyle) {
                            ForEach(GlassStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                }

                section("Clock") {
                    toggle("24-Hour Time", symbol: "clock.fill", tint: .orange, isOn: $model.use24Hour)
                    toggle("Show Seconds", symbol: "stopwatch.fill", tint: .red, isOn: $model.showSeconds)
                    toggle("Show Timeline", symbol: "chart.bar.xaxis", tint: .green, isOn: $model.showTimeline)
                }

                section("Menu Bar") {
                    row("Shows", symbol: "menubar.rectangle", tint: .blue) {
                        Picker("", selection: $model.menuBarStyle) {
                            ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    row("City", symbol: "mappin.circle.fill", tint: .purple) {
                        zonePicker(selection: Binding(
                            get: { model.menuBarZone?.id },
                            set: { id in
                                if let zone = model.zones.first(where: { $0.id == id }) { model.showInMenuBar(zone) }
                            }
                        ), allowNone: false)
                    }
                    row("Second City", symbol: "rectangle.split.2x1.fill", tint: .indigo) {
                        zonePicker(selection: Binding(
                            get: { model.menuBarSecondZone?.id },
                            set: { id in
                                model.menuBarSecondZoneID = id
                                if id != nil && model.menuBarStyle == .icon { model.menuBarStyle = .flagTime }
                            }
                        ), allowNone: true)
                    }
                    toggle("Blink Time Separator", symbol: "light.beacon.max.fill", tint: .yellow, isOn: $model.blinkSeparator)
                }

                section("General") {
                    toggle("Launch at Login", symbol: "power", tint: .gray, isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    HStack {
                        Button { model.copyAll() } label: { Label("Copy All Times", systemImage: "doc.on.doc") }
                        Spacer()
                        Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
                            Label("Quit WorldZones", systemImage: "power.circle")
                        }
                        .keyboardShortcut("q")
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 8) { content() }
                .padding(10)
                .glassCard(radius: 12)
        }
    }

    private func row<Content: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
            Text(title).font(.system(size: 12.5))
            Spacer(minLength: 8)
            content()
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private func toggle(_ title: String, symbol: String, tint: Color, isOn: Binding<Bool>) -> some View {
        row(title, symbol: symbol, tint: tint) {
            Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.mini)
        }
    }

    private func zonePicker(selection: Binding<UUID?>, allowNone: Bool) -> some View {
        Picker("", selection: selection) {
            if allowNone {
                Text("None").tag(UUID?.none)
                Divider()
            }
            ForEach(model.zones) { zone in
                Text([zone.flag, zone.displayName].compactMap { $0 }.joined(separator: " ")).tag(Optional(zone.id))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}
