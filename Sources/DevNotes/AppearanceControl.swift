import AppKit
import SwiftUI

/// Follows macOS until the user chooses an appearance.
struct AppearanceControl: ViewModifier {
    @AppStorage("DevNotes.appearance") private var selection = "system"
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme? {
        selection == "dark" ? .dark : selection == "light" ? .light : nil
    }
    private var isDark: Bool { (scheme ?? systemScheme) == .dark }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Toggle("Тема", isOn: Binding(
                        get: { isDark },
                        set: { selection = $0 ? "dark" : "light" }
                    ))
                    .toggleStyle(ThemeToggleStyle())
                    .help(isDark ? "Тёмная тема" : "Светлая тема")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(AppTheme.canvas)
            }
            .preferredColorScheme(scheme)
            .onAppear { applyAppearance() }
            .onChange(of: selection) { applyAppearance() }
    }

    private func applyAppearance() {
        // Native text editors and auxiliary windows use the same appearance.
        NSApp.appearance = selection == "dark" ? NSAppearance(named: .darkAqua)
            : selection == "light" ? NSAppearance(named: .aqua) : nil
    }
}

private struct ThemeToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let tint = configuration.isOn
            ? Color(red: 0.43, green: 0.40, blue: 0.78)
            : Color(red: 0.82, green: 0.43, blue: 0.16)
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.muted)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(configuration.isOn ? AppTheme.muted : tint)
                Capsule()
                    .fill(tint)
                    .frame(width: 44, height: 24)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .frame(width: 18, height: 18)
                            .offset(x: configuration.isOn ? 23 : 3)
                    }
                Image(systemName: "moon.fill")
                    .foregroundStyle(configuration.isOn ? tint : AppTheme.muted)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: configuration.isOn)
        .accessibilityLabel("Тема")
        .accessibilityValue(configuration.isOn ? "Тёмная" : "Светлая")
        .accessibilityHint("Переключить светлую и тёмную тему")
    }
}
