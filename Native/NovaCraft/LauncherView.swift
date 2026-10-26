import SwiftUI
import GameController

struct LauncherView: View {
    @EnvironmentObject private var state: LauncherState
    @AppStorage("show-snapshots") private var showSnapshots = false
    @State private var selectedTab = 0
    @AppStorage("version-filter") private var versionFilter = "all"
    @AppStorage("download-wifi-reminder") private var wifiReminder = true
    @AppStorage("prefer-dark-interface") private var preferDarkInterface = true
    @State private var offlineNickname = ""
    @State private var serverName = ""
    @State private var serverAddress = ""
    @State private var versionSearch = ""
    @State private var showDeleteConfirmation = false

    private var filteredVersions: [MinecraftVersion] {
        state.versions.filter { version in
            (showSnapshots || version.type == "release") &&
            (versionFilter != "installed" || state.installed.contains(version.id)) &&
            (versionSearch.isEmpty || version.id.localizedCaseInsensitiveContains(versionSearch))
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        overview
                        versionPanel
                        installPanel
                        hardwarePanel
                        noticePanel
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("NovaCraft")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await state.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(state.refreshing || state.busy)
                        .accessibilityLabel("Odśwież wersje")
                    }
                }
                .refreshable { await state.refresh() }
                .confirmationDialog("Usunąć pobrane pliki?", isPresented: $showDeleteConfirmation) {
                    Button("Usuń pliki \(state.selectedVersion)", role: .destructive) {
                        state.removeSelected()
                    }
                } message: {
                    Text("Usunie tylko lokalne pliki tej wersji, nie konto ani zapisane serwery.")
                }
            }
            .tabItem { Label("Start", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                List {
                    Section("Konto Minecraft") {
                        if let account = state.account {
                            Label(account.username, systemImage: "person.crop.circle.fill")
                                .font(.headline)
                            Label("Profil Minecraft Java zweryfikowany", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Nie zalogowano", systemImage: "person.crop.circle.badge.questionmark")
                            Button {
                                Task { await state.signIn() }
                            } label: {
                                Label("Zaloguj przez Microsoft", systemImage: "person.badge.key.fill")
                            }
                            Text("Logowanie wymaga skonfigurowanego identyfikatora aplikacji Microsoft Entra. Hasło podajesz wyłącznie na stronie Microsoft.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Profil offline (bez premium)") {
                        TextField("Nick, np. Gracz123", text: $offlineNickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Dodaj profil offline") {
                            state.addOfflineProfile(offlineNickname)
                            if state.activeOfflineProfile?.nickname == offlineNickname { offlineNickname = "" }
                        }
                        .disabled(offlineNickname.isEmpty)
                        if !state.offlineProfiles.isEmpty {
                            Picker("Aktywny profil", selection: $state.selectedOfflineID) {
                                Text("Brak").tag(nil as UUID?)
                                ForEach(state.offlineProfiles) { profile in
                                    Text(profile.nickname).tag(Optional(profile.id))
                                }
                            }
                            ForEach(state.offlineProfiles) { profile in
                                Label(profile.nickname, systemImage: "person.crop.circle")
                            }
                            .onDelete(perform: state.removeOfflineProfiles)
                        }
                        Text("Profil offline to tylko lokalny nick. Nie omija weryfikacji Microsoft i nie działa na serwerach wymagających konta premium. Uruchamianie gry nadal wymaga JVM i renderera.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Status") {
                        Text(state.message).font(.footnote)
                    }
                }
                .navigationTitle("Konto")
            }
            .tabItem { Label("Konto", systemImage: "person.crop.circle") }
            .tag(1)

            NavigationStack {
                List {
                    Section("Nowy serwer") {
                        TextField("Nazwa serwera", text: $serverName)
                            .textInputAutocapitalization(.sentences)
                        TextField("Adres, np. example.org:25565", text: $serverAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button {
                            if state.addServer(name: serverName, address: serverAddress) {
                                serverName = ""
                                serverAddress = ""
                            }
                        } label: {
                            Label("Dodaj do ulubionych", systemImage: "plus.circle.fill")
                        }
                        .disabled(serverName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Section("Ulubione (\(state.servers.count))") {
                        if state.servers.isEmpty {
                            ContentUnavailableView("Brak serwerów", systemImage: "server.rack",
                                                   description: Text("Dodaj adres, aby mieć go pod ręką."))
                        } else {
                            ForEach(state.servers) { server in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.name).font(.headline)
                                    Text(server.address)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                                Button("Sprawdź dostępność TCP") {
                                    Task { await state.probeServer(server.address) }
                                }
                                .font(.caption)
                            }
                            .onDelete { state.servers.remove(atOffsets: $0) }
                        }
                    }
                    Section("Diagnostyka serwera") {
                        Text(state.serverProbeStatus).font(.footnote)
                        Label("Test TCP nie sprawdza protokołu Minecraft ani logowania. Multiplayer nadal wymaga działającego silnika gry.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Serwery")
            }
            .tabItem { Label("Serwery", systemImage: "network") }
            .tag(2)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Edytor sterowania", systemImage: "hand.draw.fill")
                            .font(.title2.bold())
                        Text("Przeciągaj przyciski, aby ustawić własny układ. Zmiany zapisują się na urządzeniu.")
                            .foregroundStyle(.secondary)
                        TouchOverlayView()
                            .frame(height: 390)
                            .padding(10)
                            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                        Label("Wykryte kontrolery: \(GCController.controllers().count)", systemImage: "gamecontroller.fill")
                            .font(.subheadline)
                        Text("Podgląd testuje wejścia. Sterowanie nie jest jeszcze połączone z silnikiem gry.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .navigationTitle("Sterowanie")
            }
            .tabItem { Label("Sterowanie", systemImage: "gamecontroller.fill") }
            .tag(3)

            NavigationStack {
                Form {
                    Section("Wygląd") {
                        Toggle("Ciemny wygląd", isOn: $preferDarkInterface)
                    }
                    Section("Wersje i pobieranie") {
                        Picker("Widoczne wersje", selection: $versionFilter) {
                            Text("Wszystkie").tag("all")
                            Text("Tylko pobrane").tag("installed")
                        }
                        Toggle("Przypomnienie o Wi-Fi", isOn: $wifiReminder)
                        Text("Pliki Minecraft mogą zajmować dużo miejsca. Pobieranie wykorzystuje aktywne połączenie internetowe.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("NovaEngine") {
                        Text(NovaHardwareDiagnostics.metalStatus())
                        Text(NovaHardwareDiagnostics.javaStatus())
                        Text("To test sprzętu, nie grywalny silnik Minecraft Java.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Ustawienia")
            }
            .tabItem { Label("Ustawienia", systemImage: "gearshape.fill") }
            .tag(4)
        }
        .tint(.cyan)
        .preferredColorScheme(preferDarkInterface ? .dark : .light)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .font(.title)
                    .foregroundStyle(.cyan)
                Spacer()
                Text("PREVIEW")
                    .font(.caption2.bold())
                    .tracking(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            Text("TWÓJ ŚWIAT.\nTWOJE ZASADY.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-1)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("NovaCraft • launcher Minecraft Java")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                Text("Rozwój silnika trwa")
            }
            .font(.caption.bold())
            .foregroundStyle(.cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.29),
                                    Color(red: 0.03, green: 0.07, blue: 0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var overview: some View {
        HStack(spacing: 12) {
            statTile(title: "Wersje online", value: "\(state.versions.count)", symbol: "square.stack.3d.up.fill")
            statTile(title: "Pobrane", value: "\(state.installed.count)", symbol: "checkmark.circle.fill")
            statTile(title: "Serwery", value: "\(state.servers.count)", symbol: "server.rack")
        }
    }

    private func statTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(.cyan)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var versionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wybierz wersję", systemImage: "square.stack.fill")
                .font(.headline)
            TextField("Szukaj, np. 1.21", text: $versionSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle("Pokaż snapshoty", isOn: $showSnapshots)
            Picker("Filtr", selection: $versionFilter) {
                Text("Wszystkie").tag("all")
                Text("Pobrane").tag("installed")
            }
            .pickerStyle(.segmented)
                .font(.subheadline)
            if filteredVersions.isEmpty {
                Text(state.refreshing ? "Ładowanie wersji…" : "Brak pasujących wersji. Odśwież listę lub zmień filtr.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Wersja Minecraft", selection: Binding(
                    get: { state.selectedVersion },
                    set: { state.select($0) }
                )) {
                    if !filteredVersions.contains(where: { $0.id == state.selectedVersion }) {
                        Text("Wybierz wersję").tag(state.selectedVersion)
                    }
                    ForEach(filteredVersions) { version in
                        Text("\(version.id)\(state.installed.contains(version.id) ? " ✓" : "")")
                            .tag(version.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Circle().fill(state.selectedInstalled ? .green : .orange).frame(width: 8, height: 8)
                Text(state.selectedInstalled ? "Pliki tej wersji pobrane" : "Pliki tej wersji niepobrane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private var installPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Menedżer plików", systemImage: "internaldrive.fill")
                .font(.headline)
            if state.busy {
                ProgressView(value: state.downloadProgress)
                Text("Pobieranie: \(Int(state.downloadProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if wifiReminder && !state.selectedInstalled {
                Label("Zalecane Wi-Fi — pliki mogą być duże.", systemImage: "wifi")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await state.installSelected() }
            } label: {
                Label(state.selectedInstalled ? "Pobierz ponownie" : "Pobierz pliki wersji",
                      systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.busy || state.selectedVersion.isEmpty)
            if state.selectedInstalled {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Usuń pobrane pliki", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.busy)
            }
            if state.selectedInstalled {
                Button {
                    state.inspectEngine()
                } label: {
                    Label("Sprawdź zgodność NovaEngine", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await state.launch() }
                } label: {
                    Label("Uruchom Minecraft (test silnika)", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.busy)
                Text("NovaEngine 0.1 analizuje wersję i biblioteki. Nie zawiera jeszcze JVM ani renderera, więc nie uruchamia gry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(state.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private var hardwarePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NovaEngine • diagnostyka sprzętu", systemImage: "cpu.fill")
                .font(.headline)
            Text(NovaHardwareDiagnostics.metalStatus())
            Text(NovaHardwareDiagnostics.javaStatus())
            Text("Obsługa OpenGL/LWJGL i wykonywanie Minecraft Java nadal wymagają implementacji.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var noticePanel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text("Wersja rozwojowa").font(.subheadline.bold())
                Text("NovaCraft pobiera zweryfikowane pliki klienta z serwerów Mojang. Nie ma jeszcze środowiska Java, LWJGL ani działającego multiplayer. To nie jest grywalny Minecraft.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20))
    }
}
