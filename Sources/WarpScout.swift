import AppKit
import SwiftUI

private enum Page: String, CaseIterable, Identifiable {
  case scanner = "Сканер"
  case advanced = "Расширенный сканер"
  case servers = "Серверы"
  case settings = "Настройки"

  var id: Self { self }
  var symbol: String {
    switch self {
    case .scanner: "scope"
    case .advanced: "slider.horizontal.3"
    case .servers: "server.rack"
    case .settings: "gearshape"
    }
  }
}

@main
struct WarpScoutApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  // MenuBarExtra uses the NSImage's intrinsic size for its status button.
  private static let menuIcon: NSImage = {
    let size = NSSize(width: 24, height: 18)
    let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
    let cloud = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)!
    let icon = NSImage(size: size, flipped: false) { rect in
      symbol.draw(in: NSRect(x: 0, y: 0, width: rect.height, height: rect.height))
      let badge = NSRect(x: 9, y: 0, width: 15, height: 10)
      cloud.draw(
        in: badge.insetBy(dx: -1.5, dy: -1.5), from: .zero, operation: .destinationOut, fraction: 1)
      cloud.draw(in: badge)
      return true
    }
    icon.isTemplate = true
    return icon
  }()
  var body: some Scene {
    Window("WarpScout", id: "main") {
      Workspace()
        .frame(minWidth: 920, minHeight: 650)

    }
    .defaultSize(width: 1060, height: 720)
    .commands {
      CommandGroup(replacing: .help) {
        Button(tr("Первый запуск WarpScout")) {
          if let guide = Bundle.main.url(forResource: "FirstLaunch", withExtension: "html") {
            NSWorkspace.shared.open(guide)
          }
        }
      }
    }
    MenuBarExtra {
      Tray()
    } label: {
      Image(nsImage: Self.menuIcon).accessibilityLabel("WarpScout")
    }
  }
}

// Use the property wrapper on Command Line Tools, which lack the SwiftUI macro plugin.
private typealias PreviewState<Value> = SwiftUI.State<Value>

private struct RowDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        configuration.isExpanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold)).accessibilityHidden(true)
          configuration.label
        }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityValue(
        configuration.isExpanded ? tr("Развёрнуто") : tr("Свёрнуто"))
      if configuration.isExpanded { configuration.content }
    }
  }
}

private struct Workspace: View {
  @ObservedObject private var engine = Engine.shared
  @PreviewState private var lastScanner = Page.scanner
  @PreviewState private var copiedEndpoint = ""
  @PreviewState private var dismissedUpdate = ""
  @PreviewState private var history: [Release] = []
  @PreviewState private var pending: Release?
  @PreviewState private var confirmRegister = false
  @PreviewState private var download: Task<Void, Never>?
  private static let githubMark = NSImage(
    contentsOf: Bundle.main.url(forResource: "GitHubMark", withExtension: "png")!)!
  private let repository = "HattabbI4/warpscout-gui-macos"
  @AppStorage("autoUpdate") private var autoUpdate = true
  @PreviewState private var version = ""
  @PreviewState private var updateNote = ""
  @PreviewState private var coreTask: Task<Void, Never>?
  @PreviewState private var coreStatus = ""
  @PreviewState private var choosingCore = false
  @PreviewState private var validatingCore = false
  @PreviewState private var pathError = ""
  @PreviewState private var checkingApp = false
  @PreviewState private var page = Page?.some(.scanner)
  @PreviewState private var protocolName =
    UserDefaults.standard.string(forKey: "protocolName") ?? "AmneziaWG"
  @AppStorage("excluded") private var excluded = true
  @AppStorage("ping") private var ping = true
  @AppStorage("full") private var full = false
  @AppStorage("speed") private var speed = false
  @PreviewState private var socksPopover = false
  @PreviewState private var scannerLogExpanded = false
  @PreviewState private var advancedLogExpanded = true
  @AppStorage("language") private var language = "Русский"
  @AppStorage("minimizeToMenuBar") private var minimizeToMenuBar = false
  @AppStorage("keepProxy") private var keepProxy = true
  @PreviewState private var corePath = ""
  @AppStorage("confirmQuit") private var confirmQuit = false
  @AppStorage("node") private var node = "DME"
  @AppStorage("flags") private var flags = ""
  @AppStorage("trailers") private var trailers = false
  @AppStorage("cookies") private var cookies = false
  @AppStorage("padding") private var padding = ""
  @AppStorage("timing0") private var timing0 = ""
  @AppStorage("timing1") private var timing1 = ""
  @AppStorage("timing2") private var timing2 = ""
  @AppStorage("timing3") private var timing3 = ""
  @AppStorage("timing4") private var timing4 = ""

  private let protocols = [
    "AmneziaWG", "AmneziaWG 3.1", "WireGuard", "MASQUE (QUIC)", "MASQUE H2 (TCP)",
  ]

  var body: some View {
    NavigationSplitView {
      List(selection: $page) {
        Section(tr("Поиск серверов")) {
          entry(.scanner)
          entry(.advanced)
          entry(.servers)
        }
        Section(tr("Приложение")) {
          entry(.settings)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 205, ideal: 222)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          Link(destination: URL(string: "https://github.com/" + repository)!) {
            HStack(spacing: 8) {
              Image(nsImage: Self.githubMark).renderingMode(.template).resizable().foregroundStyle(
                .primary
              ).frame(width: 20, height: 20)
                .accessibilityHidden(true)
              Text(tr("Поставить звезду"))
            }
          }.help(tr("Поставить звезду на GitHub")).padding(.horizontal, 8)
          Button {
            page = .settings
          } label: {
            HStack(spacing: 9) {
              Image(
                systemName: version.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill"
              ).foregroundStyle(version.isEmpty ? Color.secondary : .green)
              VStack(alignment: .leading, spacing: 2) {
                Text(version.isEmpty ? tr("Ядро недоступно") : tr("Ядро готово")).font(
                  .callout.weight(.medium))
                Text(version.isEmpty ? coreStatus : "warpscout " + version).font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(14)
            .background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 13))
            .contentShape(Rectangle())
          }.buttonStyle(.plain).help(tr("Открыть настройки ядра"))
        }.padding(12)
      }
    } detail: {
      Group {
        switch page ?? .scanner {
        case .scanner: scanner
        case .advanced: advanced
        case .servers: servers
        case .settings: settings
        }
      }
      .safeAreaInset(edge: .top) {
        if version.isEmpty && page != .settings {
          HStack {
            if coreTask != nil { ProgressView().controlSize(.small) }
            Text(coreStatus.isEmpty ? tr("Для поиска требуется ядро warpscout.") : coreStatus)
            Spacer()
            Button(tr("Настройки")) { page = .settings }
          }.padding(.horizontal, 20).padding(.vertical, 8)
        }
      }
      .navigationTitle(tr((page ?? .scanner).rawValue))
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            socksPopover.toggle()
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "point.3.connected.trianglepath.dotted")
              Text(verbatim: "SOCKS5")
              if !engine.proxy.isEmpty {
                Circle().fill(engine.ready ? Color.green : Color.orange).frame(width: 7, height: 7)
              }
            }.fixedSize().padding(.horizontal, 8).padding(.vertical, 3)
          }
          .popover(isPresented: $socksPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
              Text(tr("Локальный SOCKS5-прокси")).font(.headline)
              if !engine.proxy.isEmpty {
                Text(engine.proxy)
                Button(tr("Остановить")) { engine.stopProxy() }
              }
              Text(
                engine.proxy.isEmpty
                  ? tr("Выключен") : (engine.ready ? "127.0.0.1:1080" : tr("Подключение…"))
              ).foregroundStyle(.secondary)
            }
            .padding()
          }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .onChange(of: page) { _, target in
      if target == .advanced || target == .scanner { lastScanner = target ?? .scanner }
    }

    .environment(\.locale, Locale(identifier: language == "English" ? "en" : "ru"))
    .task {
      if let data = try? Data(contentsOf: releaseCache),
        let cached = try? JSONDecoder().decode([Release].self, from: data)
      {
        history = cached
      }
      if engine.needsCoreDownload { checkCore() } else { await refreshVersion() }
      if autoUpdate { await checkHistory(silent: true) }
    }
    .alert(
      "WarpScout",
      isPresented: Binding(get: { !engine.error.isEmpty }, set: { if !$0 { engine.error = "" } })
    ) {
      Button("OK") { engine.error = "" }
    } message: {
      Text(engine.error)
    }
    .sheet(isPresented: $choosingCore) {
      VStack(alignment: .leading, spacing: 16) {
        Text(tr("Исполняемый файл ядра")).font(.headline)
        HStack {
          TextField(tr("Путь к ядру"), text: $corePath).textFieldStyle(.roundedBorder).onSubmit {
            saveSelectedCore()
          }
          Button(tr("Выбрать…")) {
            let panel = NSOpenPanel()
            if panel.runModal() == .OK, let url = panel.url { corePath = url.path }
          }
        }
        if !pathError.isEmpty { Text(pathError).foregroundStyle(.red) }
        HStack {
          Button(tr("Использовать загруженное ядро")) {
            corePath =
              engine.managed.path
          }
          Spacer()
          Button(tr("Отмена")) { choosingCore = false }.keyboardShortcut(.cancelAction)
          Button(tr("Применить")) { saveSelectedCore() }.keyboardShortcut(.defaultAction)
        }
      }.padding(20).frame(minWidth: 560).disabled(validatingCore).interactiveDismissDisabled(
        validatingCore)
    }
    .confirmationDialog(tr("Пересоздать ключ устройства?"), isPresented: $confirmRegister) {
      Button(tr("Пересоздать"), role: .destructive) { Task { await engine.renew() } }
    }
    .confirmationDialog(
      tr("Установить версию и перезапустить приложение?"),
      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
      presenting: pending
    ) { rel in
      Button(rel.tag_name) {
        if let asset = rel.gui {
          installApp(
            asset, signature: rel.signature,
            rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v")))
        }
      }
    }
  }
  private func refreshVersion() async {
    let candidate = engine.binary
    corePath = candidate.path
    do {
      let current = try await coreVersion(candidate)
      if engine.binary == candidate { version = current }
    } catch {
      guard engine.binary == candidate else { return }
      engine.error = error.localizedDescription
      version = ""
    }
  }
  private var releaseCache: URL { engine.dir.appendingPathComponent("mac-releases.json") }
  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
  }
  private var newest: Release? {
    history.first {
      $0.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v")).compare(
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "1.0.0", options: .numeric) == .orderedDescending
    }
  }
  private func checkHistory(silent: Bool = false) async {
    guard !checkingApp else { return }
    checkingApp = true
    defer { checkingApp = false }
    do {
      history = try await engine.releases(repository).filter { $0.gui != nil }
      if let data = try? JSONEncoder().encode(history) {
        try? data.write(to: releaseCache, options: .atomic)
      }
      updateNote =
        history.first.map { tr("Последний релиз") + " · " + $0.tag_name } ?? tr("Нет сборок macOS")
      if silent, let release = newest, let asset = release.gui, download == nil {
        download = Task {
          defer { download = nil }
          do {
            guard let signature = release.signature, signature.size == 64 else {
              throw Failure(tr("Отсутствует подпись издателя обновления"))
            }
            let url = try await engine.archive(asset) {
              updateNote = tr($0) + " · " + release.tag_name
            }
            try await engine.checkPublisher(asset: asset, archiveURL: url, signature: signature)
            updateNote = tr("Готово к установке") + " · " + release.tag_name
          } catch {
            updateNote = Task.isCancelled ? tr("Загрузка отменена") : tr("Ошибка загрузки релиза")
          }
        }
      }
    } catch {
      if !silent {
        updateNote = tr("Ошибка обновления")
        engine.error = error.localizedDescription
      }
    }
  }
  private func installApp(_ asset: Release.Asset, signature: Release.Asset?, _ tag: String) {
    guard download == nil else { return }
    download = Task {
      do {
        try await engine.install(asset, core: false, version: tag, signature: signature) {
          updateNote = tr($0) + " · " + tag
        }
      } catch {
        updateNote = Task.isCancelled ? tr("Загрузка отменена") : tr("Ошибка обновления")
        if !Task.isCancelled { engine.error = error.localizedDescription }
      }
      download = nil
    }
  }
  private func launch(_ advanced: Bool) {
    if engine.scanning {
      engine.stop()
      return
    }
    do {
      var args = [String]()
      if advanced {
        args = try splitArgs(flags)
      } else {
        let proto = ["awg", "awg31", "wg", "masque", "masque-h2"][
          protocols.firstIndex(of: protocolName) ?? 0]
        args = ["-p", proto]
        args += scanFeatures.flatMap(\.arguments)
        if proto == "awg31" {
          for (k, v) in [
            ("padding", padding), ("rekey-after", timing0), ("reject-after", timing1),
            ("rekey-timeout", timing2), ("keepalive-timeout", timing3), ("max-handshakes", timing4),
          ] where !v.isEmpty {
            let nums = v.split(separator: "-", omittingEmptySubsequences: false).compactMap {
              UInt32($0)
            }
            guard v.range(of: "^[0-9]+(-[0-9]+)?$", options: .regularExpression) != nil,
              nums.count == v.components(separatedBy: "-").count, nums.first! <= nums.last!
            else { throw Failure(tr("Некорректный диапазон: ") + k) }
            args += ["-" + k, v]
          }
          if trailers { args.append("-random-trailers") }
          if cookies { args.append("-disable-cookies") }
        }
      }
      Task { await engine.start(args) }
    } catch { engine.error = error.localizedDescription }
  }

  private func entry(_ page: Page) -> some View {
    Label(tr(page.rawValue), systemImage: page.symbol)
      .badge(page == .servers ? engine.scan.rows.count : 0)
      .tag(page)
      .disabled(engine.scanning && (page == .scanner || page == .advanced) && page != lastScanner)
  }

  private var scanFeatures: [(label: String, arguments: [String])] {
    var features: [(String, [String])] = []
    var seen = Set<String>()
    let nodes = node.split { $0.isWhitespace || $0 == "," || $0 == ";" }.map { $0.uppercased() }
      .filter { seen.insert($0).inserted }
    if excluded && !protocolName.hasPrefix("MASQUE") && !nodes.isEmpty {
      features.append(
        (
          tr("Без узлов") + " " + nodes.joined(separator: ", "),
          ["-exclude-node", nodes.joined(separator: ",")]
        ))
    }
    if ping { features.append((tr("Пинг в туннеле"), ["-P"])) }
    if full { features.append((tr("Полное сканирование"), ["-f"])) }
    if speed { features.append((tr("Тест скорости"), ["-speed"])) }
    return features
  }

  private func settingLabel(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(tr(title))
      Text(tr(detail)).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.padding(.vertical, 2)
  }
  private func parameter(
    _ name: String, _ description: String, _ binding: Binding<String>, _ example: String
  ) -> some View {
    LabeledContent {
      TextField(name, text: binding, prompt: Text(example)).labelsHidden().textFieldStyle(
        .roundedBorder
      ).frame(width: 134)
    } label: {
      settingLabel(name, description)
    }
  }
  private var scanner: some View {
    Form {
      Section {
        HStack(spacing: 15) {
          Image(systemName: Page.scanner.symbol)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.blue)
            .frame(width: 52, height: 52)
            .background(.blue.opacity(0.1), in: .rect(cornerRadius: 14))
          VStack(alignment: .leading, spacing: 5) {
            Text(tr("Поиск серверов WARP")).font(.title2.weight(.semibold))
            Text(([protocolName] + scanFeatures.map(\.label)).joined(separator: " · "))
              .foregroundStyle(.secondary).font(.callout).lineLimit(nil).fixedSize(
                horizontal: false, vertical: true)
          }
          Spacer()
          Button(
            engine.scanning ? tr("Остановить") : tr("Найти серверы"),
            systemImage: engine.scanning ? "stop.fill" : "play.fill"
          ) { launch(false) }.disabled(
            version.isEmpty || engine.updating || (engine.busy && !engine.scanning)
          )
          .buttonStyle(.glassProminent)
        }
        .padding(.vertical, 12)
      }

      scanFeedback(isExpanded: $scannerLogExpanded)
      bestServer
      updateBanner
      Group {
        Section(tr("Параметры сканирования")) {
          VStack(alignment: .leading, spacing: 6) {
            settingLabel("Протокол", "Используется для проверки серверов и создания конфигурации.")
            Picker(tr("Протокол"), selection: $protocolName) {
              ForEach(protocols, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().pickerStyle(.segmented)
              .onChange(of: protocolName) { _, value in
                UserDefaults.standard.set(value, forKey: "protocolName")
              }
          }
        }
        if protocolName == "AmneziaWG 3.1" {
          Section(tr("Параметры AmneziaWG 3.1")) {
            parameter(
              "-padding", "Сколько случайных байтов добавлять в каждый пакет данных.", $padding,
              "16-128")
            Toggle(isOn: $trailers) {
              settingLabel(
                "-random-trailers",
                "Добавляет случайный хвост к пакетам рукопожатия и нулевые байты в пакеты данных.")
            }
            Toggle(isOn: $cookies) {
              settingLabel("-disable-cookies", "Отключает отправку ответов cookie reply.")
            }
          }
          Section {
            parameter(
              "-rekey-after",
              "Через сколько секунд начать новое рукопожатие для обновления ключей.",
              $timing0, "120")
            parameter(
              "-reject-after",
              "Через сколько секунд перестать принимать старые ключи. Значение должно быть не меньше rekey-after.",
              $timing1, "180")
            parameter(
              "-rekey-timeout", "Сколько секунд ждать ответа перед повторной попыткой рукопожатия.",
              $timing2, "5")
            parameter(
              "-keepalive-timeout", "После скольких секунд без трафика отправлять keepalive.",
              $timing3, "10")
            parameter("-max-handshakes", "Максимальное число попыток рукопожатия.", $timing4, "18")
          } header: {
            Text(tr("Рукопожатие"))
          } footer: {
            Text(
              tr("Введите число или диапазон через дефис. Пустое поле использует значение ядра."))
          }
        }
        Section {
          LabeledContent {
            HStack(spacing: 10) {
              TextField(tr("Код узла"), text: $node, prompt: Text("DME, FRA"))
                .labelsHidden()
                .monospaced()
                .textFieldStyle(.roundedBorder).frame(width: 134)
                .disabled(!excluded)
              Toggle(tr("Исключить узел"), isOn: $excluded).labelsHidden()
            }
          } label: {
            settingLabel(
              "Исключить узел",
              protocolName.hasPrefix("MASQUE")
                ? "Фильтр узлов недоступен в этом режиме."
                : "Пропускает серверы выбранных узлов Cloudflare. Введите коды узлов через запятую."
            )
          }
          .disabled(protocolName.hasPrefix("MASQUE")).help(
            tr("Недоступно для MASQUE: в этом протоколе все эндпоинты выходят через один узел"))
          Toggle(isOn: $ping) {
            settingLabel(
              "Измерять задержку внутри туннеля",
              "Измеряет задержку и потери пакетов до 1.1.1.1 через туннель каждого сервера.")
          }
          Toggle(isOn: $full) {
            settingLabel(
              "Полное сканирование подсетей",
              "Проверяет подсеть целиком. Для IPv4 /24 это все 256 адресов, поэтому поиск занимает больше времени."
            )
          }
          Toggle(isOn: $speed) {
            settingLabel(
              "Проверять скорость",
              "После сканирования измеряет скорость скачивания через лучшие найденные серверы.")
          }
        }

      }.disabled(engine.scanning)
    }
    .formStyle(.grouped)
    .disclosureGroupStyle(RowDisclosureStyle())
    .toggleStyle(.switch)
  }

  @ViewBuilder private var updateBanner: some View {
    if let rel = newest, dismissedUpdate != rel.tag_name {
      HStack {
        Button(tr("Доступно обновление") + " · " + rel.tag_name) { page = .settings }
        Spacer()
        Button(tr("Скрыть")) { dismissedUpdate = rel.tag_name }
      }
    }
  }
  @ViewBuilder private var bestServer: some View {
    if let ep = engine.scan.rows.first(where: { $0.id == engine.scan.best })
      ?? engine.scan.rows.first
    {
      Section(tr("Последний результат")) {
        VStack(alignment: .leading, spacing: 11) {
          HStack {
            Label(tr("Лучший сервер"), systemImage: "bolt.circle.fill").foregroundStyle(.blue)
            Spacer()
            Text(ep.latency).font(.headline.monospacedDigit()).foregroundStyle(.green)
          }
          HStack {
            Text(ep.city + " · " + ep.colo).font(.headline)
            Text(ep.id).monospaced().foregroundStyle(.secondary)
          }
          HStack {
            Button(tr("Сохранить конфиг"), systemImage: "arrow.down.to.line") {
              engine.export(ep)
            }
            Button(
              engine.isActiveProxy(ep) ? tr("Остановить") : tr("Включить SOCKS5"),
              systemImage: engine.isActiveProxy(ep) ? "stop.circle.fill" : "power"
            ) { Task { await engine.connect(ep) } }.disabled(version.isEmpty || engine.updating)
            Spacer()
            Button(tr("Все серверы")) { page = .servers }
          }
        }
        .padding(.vertical, 8)
      }
    }
  }

  @ViewBuilder private func scanFeedback(isExpanded: Binding<Bool>) -> some View {
    if !engine.phase.isEmpty {
      Section {
        ProgressView(value: engine.progress) { Text(engine.phase) }
      }
    }
    Section {
      DisclosureGroup(tr("Лог"), isExpanded: isExpanded) {
        // Measure ten lines in the same font as the selectable output.
        Text(verbatim: Array(repeating: "0", count: 10).joined(separator: "\n"))
          .fixedSize().hidden().accessibilityHidden(true).frame(maxWidth: .infinity)
          .overlay {
            ScrollView(.vertical) {
              Text(
                verbatim: engine.log.isEmpty
                  ? tr("Здесь появится вывод сканера.")
                  : String(engine.log.dropLast(engine.log.hasSuffix("\n") ? 1 : 0))
              )
              .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.defaultScrollAnchor(.bottom, for: .initialOffset).defaultScrollAnchor(
              .top, for: .alignment)
          }
          .font(.system(.callout, design: .monospaced))
          .padding(8).background(.background, in: .rect(cornerRadius: 6))
      }
    }
  }

  private var advanced: some View {
    Form {
      Section(tr("Аргументы запуска")) {
        LabeledContent(tr("Аргументы для warpscout scan")) {
          TextField(
            tr("Флаги CLI"), text: $flags,
            prompt: Text(tr("Например: -p awg -P -exclude-node DME -jt 20"))
          ).labelsHidden().disabled(engine.scanning)
            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
        }
        Button(
          engine.scanning ? tr("Остановить") : tr("Запустить сканирование"),
          systemImage: "play.fill"
        ) { launch(true) }.disabled(
          version.isEmpty || engine.updating || (engine.busy && !engine.scanning)
        )
        .buttonStyle(.glassProminent)
      }
      Text(
        tr(
          "Эти аргументы заменяют параметры обычного сканера. Путь к аккаунту и потоковый вывод добавляются автоматически."
        )
      ).font(.callout).foregroundStyle(.secondary)
      DisclosureGroup(tr("Примеры команд")) {
        ForEach(
          [
            "-p awg -P -exclude-node DME", "-p awg31 -P -padding 16-128", "-p masque -P",
            "-p wg -f -speed -t 3",
          ], id: \.self
        ) { example in
          Button(example) { flags = example }.font(.system(.callout, design: .monospaced))
            .buttonStyle(.link)
        }
      }
      .disabled(engine.scanning)
      scanFeedback(isExpanded: $advancedLogExpanded)
      bestServer
      updateBanner
    }
    .formStyle(.grouped)
    .disclosureGroupStyle(RowDisclosureStyle())
  }

  private var serverSummary: String {
    if !copiedEndpoint.isEmpty { return tr("Скопировано") + " · " + copiedEndpoint }
    let scan = engine.scan
    let date = scan.date?.formatted() ?? "—"
    return "\(scan.rows.count) · \(scan.proto) · \(date)"
  }

  private var servers: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(tr("Рабочие серверы")).font(.title2.weight(.semibold))
          Text(serverSummary).foregroundStyle(.secondary)
        }
        Spacer()
        Button(
          engine.scanning ? tr("Остановить") : tr("Новый поиск"),
          systemImage: engine.scanning ? "stop.fill" : "arrow.clockwise"
        ) { launch(lastScanner == .advanced) }.disabled(
          version.isEmpty || engine.updating || (engine.busy && !engine.scanning))
      }
      Table(engine.scan.rows) {
        TableColumn(tr("Расположение")) { ep in
          HStack {
            if ep.id == engine.scan.best { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            Text([ep.node_country, ep.city].compactMap { $0 }.joined(separator: " · "))
          }
        }
        TableColumn(tr("Узел"), value: \.colo).width(54)
        TableColumn(tr("Адрес")) { endpoint in
          Button(endpoint.endpoint) {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(endpoint.id, forType: .string) {
              copiedEndpoint = endpoint.id
            }
          }.buttonStyle(.plain).monospaced().help(tr("Скопировать адрес сервера"))
        }
        TableColumn(tr("Задержка"), value: \.latency).width(75)
        TableColumn(tr("Потери")) { Text($0.loss_pct.map { String(format: "%.0f%%", $0) } ?? "—") }
          .width(50)
        TableColumn(tr("Мбит/с")) { Text($0.speed_mbps.map { String(format: "%.1f", $0) } ?? "—") }
          .width(55)
        TableColumn(tr("Действия")) { ep in
          HStack {
            Button(tr("Сохранить конфиг"), systemImage: "arrow.down.to.line") { engine.export(ep) }
            Button(
              engine.isActiveProxy(ep) ? tr("Остановить") : tr("Включить SOCKS5"),
              systemImage: engine.isActiveProxy(ep) ? "stop.circle.fill" : "power"
            ) { Task { await engine.connect(ep) } }.disabled(version.isEmpty || engine.updating)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
        }
        .width(80)
      }.overlay {
        if engine.scan.rows.isEmpty {
          ContentUnavailableView {
            Label(tr("Нет найденных серверов"), systemImage: "server.rack")
          } actions: {
            Button(tr("Открыть сканер")) { page = lastScanner }
          }

        }
      }
    }
    .padding(24)
    .onDisappear { copiedEndpoint = "" }.onChange(of: engine.busy) { copiedEndpoint = "" }
  }

  private func saveSelectedCore() {
    let path = (corePath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
      .expandingTildeInPath
    guard !validatingCore else { return }
    validatingCore = true
    Task {
      defer { validatingCore = false }
      do {
        version = try await engine.selectCore(path)
        corePath = engine.binary.path
        choosingCore = false
        coreStatus = ""
      } catch { pathError = error.localizedDescription }
    }
  }
  private func checkCore() {
    guard coreTask == nil else { return }
    coreStatus = tr("Проверяем релизы…")
    coreTask = Task {
      defer { coreTask = nil }
      do {
        try await engine.updateCore(currentVersion: version) { coreStatus = $0 }
        await refreshVersion()
      } catch {
        coreStatus = Task.isCancelled ? tr("Проверка отменена") : tr("Ошибка обновления")
        if !Task.isCancelled { engine.error = error.localizedDescription }
      }
    }
  }
  private var settings: some View {
    Form {
      Section(tr("Ядро сканера")) {
        HStack(spacing: 12) {
          Image(systemName: "cpu").font(.title).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 3) {
            Text(version.isEmpty ? "warpscout" : "warpscout " + version).font(.headline)
            Text(coreStatus.isEmpty ? tr("Готово к проверке обновлений") : coreStatus)
              .font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
          if coreTask != nil {
            ProgressView().controlSize(.small)
            Button(tr("Отмена")) { coreTask?.cancel() }
          } else {
            Button(version.isEmpty ? tr("Загрузить ядро") : tr("Проверить обновления")) {
              checkCore()
            }
            .disabled(engine.busy || !engine.proxy.isEmpty || engine.updating)
          }
        }.padding(.vertical, 4)
        LabeledContent(tr("Исполняемый файл ядра")) {
          HStack {
            Text((engine.binary.path as NSString).abbreviatingWithTildeInPath)
              .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(
                engine.binary.path)
            Button(tr("Изменить…")) {
              corePath = engine.binary.path
              pathError = ""
              choosingCore = true
            }
          }
        }.disabled(coreTask != nil || engine.updating || engine.busy || !engine.proxy.isEmpty)
      }
      Section(tr("Аккаунт Cloudflare WARP")) {

        if let data = try? Data(contentsOf: engine.account),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let id = obj["id"] as? String
        {
          LabeledContent(tr("ID устройства"), value: id)
          if let ip = obj["ipv4"] as? String { LabeledContent("IPv4", value: ip) }
        } else {
          Text(tr("Аккаунт будет зарегистрирован при первом сканировании.")).foregroundStyle(
            .secondary)
        }
        if !engine.accountNotice.isEmpty { Text(engine.accountNotice).foregroundStyle(.secondary) }
        LabeledContent(tr("Ключ устройства WARP")) {
          Button(
            FileManager.default.fileExists(atPath: engine.account.path)
              ? tr("Пересоздать ключ…") : tr("Зарегистрировать")
          ) {
            if FileManager.default.fileExists(atPath: engine.account.path) {
              confirmRegister = true
            } else {
              Task { await engine.renew() }
            }
          }.disabled(version.isEmpty || engine.busy || engine.updating || !engine.proxy.isEmpty)
        }
      }
      Section(tr("Приложение")) {
        Picker(tr("Язык"), selection: $language) {
          Text("Русский").tag("Русский")
          Text("English").tag("English")
        }
        Toggle(tr("При закрытии окна оставлять WarpScout в строке меню"), isOn: $minimizeToMenuBar)
        Toggle(tr("Оставлять приложение в строке меню при активном SOCKS5"), isOn: $keepProxy)
          .disabled(minimizeToMenuBar)
        Toggle(tr("Предупреждать при выходе с активным прокси"), isOn: $confirmQuit)
      }
      Section(tr("Обновления приложения")) {
        LabeledContent(
          tr("Версия приложения"),
          value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—")
        Toggle(tr("Проверять при запуске"), isOn: $autoUpdate)
        HStack {
          Text(checkingApp ? tr("Проверяем релизы…") : updateNote).font(.callout).foregroundStyle(
            .secondary)
          Spacer()
          if checkingApp || download != nil { ProgressView().controlSize(.small) }
          if download != nil {
            Button(tr("Отмена")) { download?.cancel() }
          } else {
            Button(tr("Проверить обновления")) { Task { await checkHistory() } }.disabled(
              checkingApp)
          }
        }
        ForEach(history) { rel in
          DisclosureGroup(rel.tag_name) {
            Text(rel.notes(english: language == "English")).textSelection(.enabled)
            Button(
              tr(
                rel.tag_name == "v" + appVersion || rel.tag_name == appVersion
                  ? "Установленная версия" : "Установить")
            ) { pending = rel }.disabled(
              download != nil || engine.updating || rel.tag_name == "v" + appVersion
                || rel.tag_name == appVersion)
          }
        }
      }
    }
    .formStyle(.grouped)
    .disclosureGroupStyle(RowDisclosureStyle())
    .toggleStyle(.switch)
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NotificationCenter.default.addObserver(
      self, selector: #selector(minimized(_:)), name: NSWindow.didMiniaturizeNotification,
      object: nil)
  }
  @objc func minimized(_ notification: Notification) {
    if UserDefaults.standard.bool(forKey: "minimizeToMenuBar") {
      NSApp.hide(nil)
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    let prefs = UserDefaults.standard
    if !Engine.shared.proxy.isEmpty && prefs.bool(forKey: "confirmQuit") {
      return true
    }
    return !prefs.bool(forKey: "minimizeToMenuBar")
      && (Engine.shared.proxy.isEmpty || prefs.object(forKey: "keepProxy") as? Bool == false)
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let e = Engine.shared
    if !e.proxy.isEmpty && UserDefaults.standard.bool(forKey: "confirmQuit") {
      let alert = NSAlert()
      alert.messageText = tr("Остановить SOCKS5 и выйти?")
      alert.addButton(withTitle: tr("Выйти"))
      alert.addButton(withTitle: tr("Отмена"))
      alert.addButton(withTitle: tr("Свернуть"))
      alert.showsSuppressionButton = true
      let reply = alert.runModal()
      if reply == .alertThirdButtonReturn {
        if alert.suppressionButton?.state == .on {
          UserDefaults.standard.set(false, forKey: "confirmQuit")
          UserDefaults.standard.set(true, forKey: "keepProxy")
        }
        NSApp.hide(nil)
      }
      guard reply == .alertFirstButtonReturn else { return .terminateCancel }
      if alert.suppressionButton?.state == .on {
        UserDefaults.standard.set(false, forKey: "confirmQuit")
        UserDefaults.standard.set(false, forKey: "minimizeToMenuBar")
        UserDefaults.standard.set(false, forKey: "keepProxy")
      }
    }
    e.stop()
    e.stopProxy()
    return .terminateNow
  }
}
private struct Tray: View {
  @AppStorage("minimizeToMenuBar") private var minimize = false
  @Environment(\.openWindow) var openWindow
  @ObservedObject var engine = Engine.shared
  var body: some View {
    Button(tr("Открыть WarpScout")) {
      openWindow(id: "main")
      NSApp.unhide(nil)
      for window in NSApp.windows where window.isMiniaturized { window.deminiaturize(nil) }
      NSApp.activate()
    }
    if !engine.proxy.isEmpty {
      Text(engine.proxy)
      Button(tr("Остановить SOCKS5")) { engine.stopProxy() }
    }
    Toggle(tr("Сворачивать в строку меню"), isOn: $minimize)
    Divider()
    Button(tr("Выйти")) { NSApp.terminate(nil) }
  }
}
