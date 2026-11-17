import SwiftUI

struct LaunchUnlockView: View {
    @EnvironmentObject private var access: LaunchAccess

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "touchid")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .padding(.bottom, 8)
            Text("Заметки под замком")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text(access.mode == .touchID ? "Только отпечаток пальца" : "Touch ID или пароль входа в Mac")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.muted)
            Button {
                Task { await access.unlock() }
            } label: {
                HStack(spacing: 9) {
                    if access.isAuthenticating { ProgressView().controlSize(.small) }
                    else { Image(systemName: "touchid") }
                    Text(access.isAuthenticating ? "Подтвердите вход…" : "Разблокировать")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(access.isAuthenticating)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 7)
            if let error = access.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvas)
    }
}


struct LaunchLockSettingsView: View {
    @EnvironmentObject private var access: LaunchAccess
    var isInitialSetup = false
    @State private var selected: LaunchLockMode = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isInitialSetup ? "Защитить вход в DevNotes?" : "Вход в DevNotes")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
            if !isInitialSetup && (!access.isUnlocked || access.needsSetup) {
                Text("Сначала откройте заметки и завершите настройку входа в главном окне.")
            } else {
                Text("Выберите, нужно ли подтверждать вход при запуске приложения.")
                    .foregroundStyle(.secondary)
                Picker("Способ входа", selection: $selected) {
                    ForEach(LaunchLockMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.radioGroup)
                if selected == .touchID {
                    Text("Пароль не заменяет отпечаток. Если Touch ID недоступен или заблокирован, открыть заметки не получится, пока вы не восстановите его работу в macOS.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Шифрование заметок сохраняется при любом выборе. macOS может отдельно попросить доступ к Связке ключей после обновления приложения.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = access.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    if access.isAuthenticating { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(isInitialSetup ? "Продолжить" : "Сохранить") {
                        Task { await access.selectMode(selected) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(access.isAuthenticating || (!isInitialSetup && selected == access.mode))
                }
            }
        }
        .padding(30)
        .frame(width: 460)
        .onAppear { selected = access.mode }
    }
}
