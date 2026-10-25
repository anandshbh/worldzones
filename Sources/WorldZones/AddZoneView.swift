import SwiftUI

final class SearchState: ObservableObject {
    /// Results are computed once per keystroke here, not on every render (the clock re-renders
    /// the view every second, which used to re-run the search and stutter while typing).
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            results = ZoneCatalog.search(query)
            selection = 0
            scrollTarget = AddZoneView.topID
        }
    }
    @Published private(set) var results = ZoneCatalog.search("")
    @Published var selection = 0
    /// Browsing the region-grouped "All Cities" list instead of Popular (ignored while searching).
    @Published var showAll = false {
        didSet { scrollTarget = AddZoneView.topID }
    }
    /// Set only by keyboard navigation and new queries; hovering never scrolls, so the list
    /// can't chase the mouse.
    @Published var scrollTarget: String?

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
        scrollTarget = results[selection].id
    }
}

struct AddZoneView: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    @StateObject private var state = SearchState()
    @FocusState private var searchFocused: Bool

    static let topID = "top"
    private let listHeight: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CircleIconButton(symbol: "chevron.left", help: "Back (Esc)") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search city, country or PST, CET…", text: $state.query)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 13.5))
                        .focused($searchFocused)
                        .onSubmit(addSelection)
                        .onKeyPress(.downArrow) { state.moveSelection(by: 1); return .handled }
                        .onKeyPress(.upArrow) { state.moveSelection(by: -1); return .handled }
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassCard(radius: 10)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Always shown (just dimmed while searching) so the page height never changes as you type.
            Picker("", selection: $state.showAll) {
                Text("Popular").tag(false)
                Text("All Cities").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .disabled(!state.query.isEmpty)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    if state.showAll && state.query.isEmpty {
                        allCities
                    } else {
                        // A plain VStack: at most 60 rows, and it avoids LazyVStack's height re-estimation jumps.
                        VStack(spacing: 2) {
                            Text(state.query.isEmpty ? "POPULAR" : "\(state.results.count) RESULT\(state.results.count == 1 ? "" : "S")")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .id(Self.topID)
                            ForEach(Array(state.results.enumerated()), id: \.element.id) { index, candidate in
                                CandidateRow(candidate: candidate, highlighted: index == state.selection)
                                    .id(candidate.id)
                                    .onTapGesture { add(candidate) }
                                    .onHover { if $0 && state.selection != index { state.selection = index } }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                .scrollIndicators(.automatic)
                .overlay {
                    if state.results.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "mappin.slash").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text("No matches for “\(state.query)”").font(Theme.title(12.5, .medium)).foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: state.scrollTarget) {
                    guard let target = state.scrollTarget else { return }
                    proxy.scrollTo(target)
                    state.scrollTarget = nil
                }
            }
            // Fixed height so the panel doesn't resize as results come and go.
            .frame(height: listHeight)
        }
        .transaction { $0.animation = nil }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    /// Every major city by region; clicking toggles it in place so several can be picked in a row.
    private var allCities: some View {
        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
            Color.clear.frame(height: 0).id(Self.topID)
            ForEach(ZoneCatalog.majorCities, id: \.region) { group in
                Section {
                    ForEach(group.cities) { city in
                        CandidateRow(candidate: city, highlighted: false, checked: model.contains(city))
                            .onTapGesture { model.toggle(city) }
                    }
                } header: {
                    let allAdded = group.cities.allSatisfy(model.contains)
                    HStack {
                        Text(group.region.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(allAdded ? "All Added" : "Add All") { model.addAll(group.cities) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .disabled(allAdded)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func addSelection() {
        if state.showAll && state.query.isEmpty { return }
        if state.results.indices.contains(state.selection) { add(state.results[state.selection]) }
    }

    private func add(_ candidate: ZoneCandidate) {
        model.add(identifier: candidate.identifier, label: candidate.name)
        isPresented = false
    }
}

private struct CandidateRow: View {
    let candidate: ZoneCandidate
    let highlighted: Bool
    /// Shows a checkmark toggle when set (All Cities browser).
    var checked: Bool? = nil
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tz = TimeZone(identifier: candidate.identifier) ?? .current
        HStack(spacing: 10) {
            Text(ZoneCatalog.flag(for: candidate.identifier) ?? "🌐")
                .font(.system(size: 18))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.name).font(Theme.title(13, .semibold))
                Text(candidate.detail).font(.system(size: 11)).foregroundStyle(highlighted ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.time(model.now, tz, use24Hour: model.use24Hour, seconds: false, withPeriod: true))
                    .font(Theme.title(13, .semibold))
                    .monospacedDigit()
                Text("\(Fmt.abbreviation(tz, at: model.now)) · \(Fmt.relativeOffset(tz, at: model.now))")
                    .font(.system(size: 11))
                    .foregroundStyle(highlighted ? Color.white.opacity(0.8) : Color.secondary)
            }
            if let checked {
                Image(systemName: checked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(checked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .frame(width: 22)
            }
        }
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear))
        )
        .contentShape(Rectangle())
    }
}
