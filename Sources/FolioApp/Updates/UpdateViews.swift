import AppKit
import FolioCore
import SwiftUI

/// Окно «Доступна новая версия».
struct UpdateWindowView: View {
    @Environment(Updater.self) private var updater
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let release = updater.presentedRelease ?? updater.availableRelease {
                UpdatePanel(release: release) {
                    dismissWindow(id: WindowID.update)
                }
            } else {
                ContentUnavailableView(
                    "Установлена последняя версия",
                    systemImage: "checkmark.circle",
                    description: Text("Folio \(updater.currentVersion?.description ?? "")")
                )
                .frame(width: 420, height: 220)
            }
        }
        .onDisappear { updater.dismissPresentation() }
    }
}

private struct UpdatePanel: View {
    let release: ReleaseInfo
    let close: () -> Void

    @Environment(Updater.self) private var updater

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Доступна версия \(release.version.description)")
                        .font(.title2.weight(.semibold))
                    Text("Сейчас установлена \(updater.currentVersion?.description ?? "сборка для разработки")")
                        .foregroundStyle(.secondary)
                    Link("Страница выпуска", destination: release.pageURL)
                        .font(.callout)
                }
            }

            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 100, maxHeight: 220)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))

            UpdateStatus(phase: updater.phase)

            HStack {
                Button("Пропустить версию") {
                    updater.skip(release)
                    close()
                }
                .disabled(updater.isBusy)
                Spacer()
                Button("Позже") {
                    if case .downloading = updater.phase {
                        updater.cancelDownload()
                    }
                    close()
                }
                Button(updater.isReadyToInstall ? "Перезапустить" : "Установить") {
                    updater.install(release)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(updater.isBusy)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var notes: AttributedString {
        let text = ReleaseFeed.displayNotes(release.notes)
        guard !text.isEmpty else { return AttributedString("Описание изменений — на странице выпуска.") }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct UpdateStatus: View {
    let phase: Updater.Phase

    var body: some View {
        switch phase {
        case .downloading(_, let fraction):
            ProgressView(value: fraction) {
                Text("Загрузка обновления…")
            }
        case .readyToInstall:
            Label("Обновление скачано и установится при выходе из Folio.", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .installing:
            ProgressView {
                Text("Перезапуск…")
            }
            .progressViewStyle(.linear)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}

/// Строка внизу боковой панели, когда есть новая версия.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if case .readyToInstall(let release) = updater.phase {
            bannerButton("Перезапустить для версии \(release.version.description)", systemImage: "arrow.clockwise.circle.fill") {
                updater.install(release)
            }
            .help("Обновление уже скачано и само установится при выходе из Folio")
        } else if let release = updater.availableRelease {
            bannerButton("Доступна версия \(release.version.description)", systemImage: "arrow.down.circle.fill") {
                updater.present(release)
                openWindow(id: WindowID.update)
            }
        }
    }

    private func bannerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Открывает окно обновления, когда проверка нашла версию, о которой нужно спросить.
struct UpdatePresenter: ViewModifier {
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: updater.presentedRelease) { _, release in
            if release != nil {
                openWindow(id: WindowID.update)
            }
        }
    }
}

struct CheckForUpdatesButton: View {
    var title = "Проверить обновления…"

    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            Task {
                await updater.check(userInitiated: true)
                if updater.presentedRelease != nil {
                    openWindow(id: WindowID.update)
                }
            }
        }
        .disabled(!updater.canUpdate || updater.isBusy)
    }
}

struct UpdateSettings: View {
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                LabeledContent("Установленная версия", value: updater.currentVersion?.description ?? "сборка для разработки")
                Toggle(
                    "Проверять обновления автоматически",
                    isOn: Binding(get: { updater.checksAutomatically }, set: { updater.setChecksAutomatically($0) })
                )
                .disabled(!updater.canUpdate)
                Toggle(isOn: Binding(get: { updater.installsAutomatically }, set: { updater.setInstallsAutomatically($0) })) {
                    Text("Устанавливать обновления автоматически")
                    Text("Новая версия скачивается в фоне и ставится, когда вы закрываете Folio")
                }
                .disabled(!updater.canUpdate || !updater.checksAutomatically)
                LabeledContent {
                    if case .readyToInstall(let release) = updater.phase {
                        Button("Перезапустить сейчас") { updater.install(release) }
                    } else if let release = updater.availableRelease {
                        Button("Установить \(release.version.description)…") {
                            updater.present(release)
                            openWindow(id: WindowID.update)
                        }
                    } else {
                        CheckForUpdatesButton(title: "Проверить сейчас")
                    }
                } label: {
                    Text("Состояние")
                    Text(statusText)
                }
            } footer: {
                Link("Все выпуски на GitHub", destination: ReleaseFeed.releasesPage)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updater.phase {
        case .idle:
            updater.lastCheck.map { "Проверено \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Ещё не проверялись"
        case .checking:
            "Проверяю…"
        case .upToDate:
            "Установлена последняя версия"
        case .available(let release):
            "Доступна версия \(release.version.description)"
        case .downloading(_, let fraction):
            "Загрузка: \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .readyToInstall(let release):
            "Версия \(release.version.description) скачана и установится при выходе"
        case .installing:
            "Перезапуск…"
        case .failed(let message):
            message
        }
    }
}
