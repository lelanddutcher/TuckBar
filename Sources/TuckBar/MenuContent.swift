import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.isSnoozing || model.isProtecting { snoozeCard }
            enableRow
            section("Menu bar on protected displays") { coverCard }
            section("Displays", trailing: "Tag to protect") { displaysCard }
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { model.refreshAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tileStyle)
                    .frame(width: 38, height: 38)
                Image(systemName: model.statusSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tileHasColor ? Color.white : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TuckBar").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var tileHasColor: Bool { model.isProtecting || model.isSnoozing }
    private var tileStyle: AnyShapeStyle {
        if model.isProtecting { return AnyShapeStyle(Color.accentColor.gradient) }
        if model.isSnoozing { return AnyShapeStyle(Color.orange.gradient) }
        return AnyShapeStyle(Color.secondary.opacity(0.22))
    }

    private var coverPct: Int { Int((model.coverOpacity * 100).rounded()) }

    private var statusText: String {
        if !model.isEnabled { return "Off · not protecting" }
        if !model.hasTaggedDisplay { return "Nothing tagged yet" }
        if model.isSnoozing { return "Untucked · re-tucks in \(model.snoozeRemainingText)" }
        if model.isProtecting {
            let names = model.protectedDisplaysPresent.map(\.name).joined(separator: ", ")
            if model.usingAutohideFallback { return "Tucked (auto-hide) · \(names)" }
            if model.coverOpacity >= 0.999 { return "Tucked · \(names)" }
            if model.coverOpacity <= 0.001 { return "Tagged · \(names)" }
            return "Dimmed \(coverPct)% · \(names)"
        }
        return "Out and about · \(model.taggedDisplayNames.joined(separator: ", ")) not connected"
    }

    private var statusColor: Color {
        if !model.isEnabled || !model.hasTaggedDisplay { return .secondary }
        if model.isSnoozing { return .orange }
        return model.isProtecting ? .green : .blue
    }

    // MARK: - Snooze ("Untuck")

    @ViewBuilder
    private var snoozeCard: some View {
        if model.isSnoozing {
            HStack(spacing: 10) {
                Image(systemName: "timer").font(.system(size: 16)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Menu bar untucked").font(.callout.weight(.medium))
                    Text("Re-tucks in \(model.snoozeRemainingText)")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 6)
                Button("Tuck now") { model.endSnooze() }.controlSize(.small)
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange.opacity(0.3)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "eye").font(.system(size: 16)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Need the menu bar?").font(.callout.weight(.medium))
                        Text("Untuck it for a bit — it re-tucks itself.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    Picker("", selection: $model.snoozeDurationMinutes) {
                        ForEach(AppModel.snoozeChoices, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                    Spacer()
                    Button("Untuck") { model.startSnooze() }
                        .controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
            .padding(10)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        }
    }

    // MARK: - Enable

    private var enableRow: some View {
        Toggle(isOn: $model.isEnabled) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Protect tagged displays").font(.callout.weight(.medium))
                Text("Cover the menu bar on a tagged display while it's connected; other monitors keep theirs.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch).controlSize(.small)
    }

    // MARK: - Cover intensity (hide ⟷ dim)

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(coverStateLabel).font(.callout.weight(.medium))
                Spacer()
                Text("\(coverPct)%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $model.coverOpacity, in: 0...1)
                .controlSize(.small)
                .tint(.accentColor)
            HStack {
                Text("Off").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Dim").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Hidden").font(.caption2).foregroundStyle(.tertiary)
            }

            Toggle(isOn: $model.coverUsesWallpaper) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Match desktop wallpaper").font(.callout)
                    Text(model.coverUsesWallpaper ? "Seamless — the bar just disappears" : "Solid black — pixels off, max protection")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch).controlSize(.small)

            if model.usingAutohideFallback {
                Text("Only one display connected — using native auto-hide. The slider applies with 2+ displays.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Label("Also hide the Dock", systemImage: "dock.rectangle").font(.callout)
                Spacer()
                Toggle("", isOn: $model.hideDockWhenProtected)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .disabled(!model.isEnabled)
        .opacity(model.isEnabled ? 1 : 0.45)
    }

    private var coverStateLabel: String {
        if model.coverOpacity >= 0.999 { return "Hidden (black)" }
        if model.coverOpacity <= 0.001 { return "Off" }
        return "Dimmed"
    }

    // MARK: - Displays

    private var displaysCard: some View {
        VStack(spacing: 0) {
            if model.displays.isEmpty {
                Text("No displays detected")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                displayRow(display)
                if index != model.displays.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func displayRow(_ display: DisplayInfo) -> some View {
        let isProtected = model.isProtected(display.id)
        return HStack(spacing: 11) {
            Image(systemName: isProtected ? "shield.lefthalf.filled" : "display")
                .font(.system(size: 16))
                .foregroundStyle(isProtected ? Color.accentColor : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display.name).font(.callout.weight(.medium))
                    if display.isMain { tag("MAIN") }
                }
                Text(display.resolutionText).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { isProtected },
                set: { _ in model.toggleProtected(display.id) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(isProtected ? Color.accentColor.opacity(0.09) : .clear)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                Toggle(isOn: $model.launchAtLogin) { Text("Open at login").font(.callout) }
                    .toggleStyle(.switch).controlSize(.mini)
                Spacer()
                Button { model.quit() } label: { Text("Quit") }
                    .controlSize(.small).keyboardShortcut("q")
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String, trailing: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(.caption2.weight(.semibold)).kerning(0.5).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.caption2).foregroundStyle(.tertiary) }
            }
            content()
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 8, weight: .bold)).kerning(0.4)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.secondary.opacity(0.2), in: Capsule()).foregroundStyle(.secondary)
    }
}
