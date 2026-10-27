import SwiftUI
import GameController

struct LauncherView: View {
    @EnvironmentObject private var state: LauncherState
    @EnvironmentObject private var backgroundDownloads: NovaBackgroundDownloads
    @AppStorage("show-snapshots") private var showSnapshots = false
    @State private var selectedTab = 0
    @AppStorage("version-filter") private var versionFilter = "all"
    @AppStorage("download-wifi-reminder") private var wifiReminder = true
    @AppStorage("prefer-dark-interface") private var preferDarkInterface = true
    @AppStorage("novacraft-jvm-probe-only") private var jvmProbeOnly = false
    @State private var offlineNickname = ""
    @State private var serverName = ""
    @State private var serverAddress = ""
    @State private var versionSearch = ""
    @State private var showDeleteConfirmation = false
    @State private var showAdvancedTools = false

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
                        quickActions
                        versionPanel
                        installPanel

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
                                Button("Pobierz status Minecraft") {
                                    Task { await state.probeServer(server.address) }
                                }
                                .font(.caption)
                            }
                            .onDelete { state.servers.remove(atOffsets: $0) }
                        }
                    }
                    Section("Diagnostyka serwera") {
                        Text(state.serverProbeStatus).font(.footnote)
                        Label("Status pobiera wersję, liczbę graczy i opis serwera. Dołączenie do gry nadal wymaga działającego silnika i odpowiedniego logowania.", systemImage: "info.circle")
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
                    Section("O aplikacji") {
                        LabeledContent("Projekt i marka", value: "mickey3211")
                        LabeledContent("Silnik 3D", value: "NovaEngine / Metal")
                        Text("Autorski kod NovaCraft nie korzysta z implementacji Amethyst. Zewnętrzne środowisko OpenJDK, biblioteki LWJGL i Minecraft pozostają własnością ich autorów i podlegają własnym licencjom.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Pliki, dodatki i pamięć") {
                        NavigationLink {
                            NovaLibraryDashboard()
                        } label: {
                            Label("Biblioteka plików i resource packi", systemImage: "folder.badge.gearshape")
                        }
                        NavigationLink {
                            NovaPerformanceSettingsView()
                        } label: {
                            Label("Ustawienia wydajności Java i Metal", systemImage: "speedometer")
                        }
                        Text("Zarządzaj plikami wersji, zajętością pamięci, paczkami zasobów i dziennikami. Nie usuwamy światów bez Twojego polecenia.")
                            .font(.footnote).foregroundStyle(.secondary)
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
                    Section("OpenJDK Zero — bez JIT (integracja testowa)") {
                        NavigationLink {
                            NovaZeroIntegratedScreen()
                        } label: {
                            Label("Uruchom test Java Zero w NovaCraft", systemImage: "cpu.fill")
                                .foregroundStyle(.green)
                        }
                        Text("To osobny wariant deweloperski NovaCraft. Pokazuje, czy bez-JIT Java działa w Twoim prawdziwym launcherze SwiftUI. Nie uruchamia jeszcze Minecraft Java.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("NovaEngine — autorski silnik 3D") {
                        NavigationLink {
                            NovaVoxelEngineScreen()
                        } label: {
                            Label("Uruchom autorski świat NovaEngine", systemImage: "square.3.layers.3d.top.filled")
                                .foregroundStyle(.cyan)
                        }
                        Text("Własny renderer Metal, siatka voxel, widoczne ściany, perspektywa 3D, sterowanie dotykiem. To oddzielny prototyp, nie działający jeszcze Minecraft Java.")
                            .font(.footnote).foregroundStyle(.secondary)
                        NavigationLink {
                            NovaMetalTestScreen()
                        } label: {
                            Label("Test renderowania Metal", systemImage: "cube.transparent.fill")
                        }
                        NavigationLink {
                            NovaBlockTestScreen()
                        } label: {
                            Label("Test grafiki 3D — obracający się blok", systemImage: "cube.fill")
                        }
                        Text(NovaHardwareDiagnostics.metalStatus())
                        Text(NovaHardwareDiagnostics.javaStatus())
                        Text(NovaJVMProbe.report())
                        Button {
                            Task { await state.testJVMStartup() }
                        } label: {
                            Label("Sprawdź biblioteki Java 21", systemImage: "cpu")
                        }
                        Text("Bezpieczny test ładowania libjli i libjvm. Nie uruchamia drugiej maszyny Java ani gry. Wynik znajdziesz na karcie Start.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Toggle("Testuj tylko JVM (bez Minecrafta)", isOn: $jvmProbeOnly)
                            .disabled(state.busy)
                        Button {
                            jvmProbeOnly = true
                            Task { await state.launch() }
                        } label: {
                            Label("Uruchom samą Java 21 (test)", systemImage: "play.circle")
                        }
                        .disabled(state.busy)
                        Text("Test nie wymaga pobranego Minecrafta ani konta. Sprawdza, czy JVM potrafi uruchomić jedną małą klasę Java; test może zamknąć aplikację, jeśli problem leży w natywnym HotSpot.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Tryb diagnostyczny sprawdza, czy Java uruchomi kod JVM_PROBE_OK. Po teście wyłącz przełącznik i ponownie uruchom aplikację, bo JVM nie może wystartować drugi raz w tym samym procesie.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Label("Start Java 21 przez JNI — diagnostyka iOS", systemImage: "cpu")
                            .foregroundStyle(.orange)
                        Text("Błąd ponownego wejścia do SwiftUI przez JLI został ominięty, ale najnowsze logi pokazują nadal możliwą awarię HotSpot podczas tworzenia maszyny Java. Nowy test JVM i opcje pamięci mają zawęzić przyczynę, a nie gwarantować uruchomienie Minecrafta.")
                            .font(.footnote).foregroundStyle(.secondary)
                        NavigationLink {
                            NovaJVMDiagnosticsScreen()
                        } label: {
                            Label("Pełny raport awarii Java 21", systemImage: "doc.text.magnifyingglass")
                        }
                        Text("Jeżeli gra znika podczas JNI_CreateJavaVM, eksportuj raport HotSpot hs_err_pid i dziennik Java. Bez raportu nie da się rozróżnić błędu pamięci, podpisu bibliotek i ograniczeń JIT.")
                            .font(.footnote).foregroundStyle(.secondary)
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
        .onReceive(NotificationCenter.default.publisher(for: .novaBackgroundDownloadFinished)) { notification in
            if let version = notification.object as? String {
                state.reflectBackgroundInstall(version)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .font(.title)
                    .foregroundStyle(.cyan)
                Spacer()
                Text("NOVAENGINE")
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
            Text("Projekt i marka: mickey3211  •  NovaEngine: własny kod")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
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

    private var quickActions: some View {
        HStack(spacing: 10) {
            NavigationLink {
                NovaVoxelEngineScreen()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "cube.transparent.fill").font(.title3)
                    Text("NovaEngine 3D").font(.subheadline.bold())
                    Text("Własny świat voxel").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            }
            NavigationLink {
                NovaLibraryDashboard()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "folder.fill").font(.title3)
                    Text("Biblioteka").font(.subheadline.bold())
                    Text("Pliki i paczki").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 15))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
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
        VStack(alignment: .leading, spacing: 14) {
            Label("Minecraft Java", systemImage: "gamecontroller.fill")
                .font(.headline)

            if state.busy {
                ProgressView()
                Text(state.selectedInstalled
                     ? "Uruchamianie Java 21…"
                     : "Przygotowywanie listy plików do pobierania w tle…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let versionID = backgroundDownloads.snapshot.versionID {
                let transfer = backgroundDownloads.snapshot
                VStack(alignment: .leading, spacing: 9) {
                    Label(transfer.finished ? "Pobieranie zakończone"
                          : (transfer.isPaused ? "Pobieranie wymaga wznowienia"
                             : "Pobieranie działa w tle"),
                          systemImage: transfer.finished ? "checkmark.circle.fill"
                            : transfer.isPaused ? "exclamationmark.triangle.fill"
                            : "arrow.down.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(transfer.finished ? Color.green : Color.cyan)
                    Text("Minecraft \(versionID) • \(transfer.completed) z \(transfer.total) plików")
                        .font(.caption.monospacedDigit())
                    ProgressView(value: transfer.progress)
                    Text("\(Int(transfer.progress * 100))% plików sprawdzonych (SHA-1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = transfer.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    if transfer.isPaused {
                        Button("Wznów pobieranie") {
                            backgroundDownloads.retryFailed()
                        }
                        .buttonStyle(.bordered)
                    }
                    if transfer.isRunning {
                        Text("Możesz zablokować ekran albo przejść do innej aplikacji. iOS sam zarządza transferami; po ponownym otwarciu zobaczysz aktualny stan.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            // The user's crash log showed a full Minecraft launch, not the
            // independent low-memory Java probe. Keep test and game separate.
            Button {
                jvmProbeOnly = true
                Task { await state.launch() }
            } label: {
                Label("Test Java 21 — bez Minecrafta", systemImage: "cpu")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(state.busy)
            Text("Najpierw uruchom ten test. Użyje wyłącznie małej klasy Java i 256 MB pamięci. Jeśli aplikacja się wyłączy, otwórz Ustawienia → Pełny raport awarii Java 21.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                // Launching Minecraft must never silently inherit a JVM-test
                // toggle from the preceding diagnostic attempt.
                jvmProbeOnly = false
                Task {
                    if state.selectedInstalled {
                        await state.launch()
                    } else {
                        await state.installSelected()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: state.selectedInstalled ? "play.fill" : "arrow.down.circle.fill")
                    Text(state.selectedInstalled ? "Graj" : "Pobierz w tle")
                        .font(.title3.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.busy || state.selectedVersion.isEmpty ||
                      (!state.selectedInstalled && backgroundDownloads.snapshot.isRunning))
            .accessibilityHint(state.selectedInstalled
                ? "Próbuje uruchomić wybraną wersję Minecraft"
                : "Najpierw pobiera pliki wybranej wersji Minecraft")

            if !state.selectedInstalled {
                Text("Pobieranie plików działa w tle po przygotowaniu listy. Po pobraniu i sprawdzeniu wszystkich plików przycisk zmieni się na Graj.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !state.message.isEmpty {
                Label(state.message, systemImage: state.lastCrashStage != nil ? "exclamationmark.triangle" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(state.lastCrashStage != nil ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup(isExpanded: $showAdvancedTools) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task { await state.installSelected() }
                    } label: {
                        Label("Pobierz ponownie", systemImage: "arrow.down.circle")
                    }
                    .disabled(state.busy || state.selectedVersion.isEmpty)

                    if state.selectedInstalled {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Usuń pobrane pliki", systemImage: "trash")
                        }
                        .disabled(state.busy)

                        Button {
                            state.inspectEngine()
                        } label: {
                            Label("Sprawdź zgodność NovaEngine", systemImage: "checkmark.shield")
                        }

                        Button {
                            state.prepareOfflineLaunch()
                        } label: {
                            Label("Przygotuj start Java", systemImage: "terminal")
                        }
                        .disabled(state.activeOfflineProfile == nil)
                    }
                    Divider()
                    Label("Diagnostyka JVM i grafiki", systemImage: "cpu")
                        .font(.subheadline.bold())
                    Text(NovaHardwareDiagnostics.javaStatus())
                    Text(NovaHardwareDiagnostics.metalStatus())
                    Text("Minecraft Java wymaga kompletnej Java 21 oraz zgodnej grafiki LWJGL na iOS. Udana kompilacja IPA nie potwierdza działania gry.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.top, 8)
            } label: {
                Label("Narzędzia zaawansowane", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline)
            }

            if let stage = state.lastCrashStage {
                Label("Ostatni etap JVM: \(stage)", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    UIPasteboard.general.string = "NovaCraft JNI: \(stage)"
                } label: {
                    Label("Kopiuj etap JVM", systemImage: "doc.on.doc")
                }
                .font(.footnote)
            }
            if let report = state.lastHotSpotReport {
                Label("Zapisano raport awarii JVM (HotSpot)", systemImage: "doc.text.magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    // Export is explicit: reports may contain device paths.
                    UIPasteboard.general.string = report
                } label: {
                    Label("Kopiuj raport JVM", systemImage: "doc.on.doc")
                }
                .font(.footnote)
            }
            if let output = state.lastHotspotBootLog, !output.isEmpty {
                DisclosureGroup("Dziennik startowy JVM (HotSpot)") {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = output
                    } label: {
                        Label("Kopiuj dziennik HotSpot", systemImage: "doc.on.doc")
                    }
                    Text("Sprawdź i usuń prywatne dane przed przesłaniem logu.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            if let output = state.lastJavaOutput, !output.isEmpty {
                DisclosureGroup("Dziennik uruchomienia Java") {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        // JVM logs can contain account information or paths.
                        // The user explicitly chooses whether to export them.
                        UIPasteboard.general.string = output
                    } label: {
                        Label("Kopiuj dziennik Java", systemImage: "doc.on.doc")
                    }
                    Text("Przed wysłaniem usuń z logu tokeny konta, adresy prywatnych serwerów i dane osobowe.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
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
