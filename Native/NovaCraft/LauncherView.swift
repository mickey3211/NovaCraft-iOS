import SwiftUI
import GameController

struct LauncherView: View {
    @EnvironmentObject var state: LauncherState
    @State private var selectedTab = 0
    @State private var serverName = ""
    @State private var serverAddress = ""
    @State private var showSnapshots = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("NOVACRAFT").font(.caption.bold()).foregroundStyle(.cyan)
                        Text("Minecraft Java na iOS").font(.largeTitle.bold())
                        Text("Natywny launcher — w trakcie rozwoju. Pobieranie plików nie uruchamia gry.")
                            .foregroundStyle(.secondary)
                        Picker("Wersja", selection: Binding(
                            get: { state.selectedVersion },
                            set: { state.select($0) })) {
                            ForEach(state.versions.filter { showSnapshots || $0.type == "release" }) { version in
                                Text(version.id).tag(version.id)
                            }
                        }.pickerStyle(.menu)
                        Toggle("Pokaż snapshoty", isOn: $showSnapshots)
                        if state.busy { ProgressView(value: state.downloadProgress) }
                        Button("Pobierz pliki wybranej wersji") { Task { await state.installSelected() } }
                            .buttonStyle(.borderedProminent).disabled(state.busy || state.selectedVersion.isEmpty)
                        Button("Uruchom Minecraft (silnik niedostępny)") { Task { await state.launch() } }
                            .buttonStyle(.bordered).disabled(state.selectedVersion.isEmpty)
                        Text(state.message).font(.footnote).foregroundStyle(.secondary)
                        Text("Pliki gry pobierane są z oficjalnych adresów Mojang. Do grania wymagany jest działający runtime.")
                            .font(.footnote)
                    }.padding()
                }.navigationTitle("Start").toolbar { Button("Odśwież") { Task { await state.refresh() } } }
            }.tabItem { Label("Start", systemImage: "play.fill") }.tag(0)

            NavigationStack {
                List {
                    if let account = state.account {
                        LabeledContent("Gracz", value: account.username)
                        Text("Uprawnienia Minecraft Java zweryfikowane").foregroundStyle(.green)
                    } else {
                        Text("Zaloguj się przez Microsoft. Nie podawaj hasła w launcherze.")
                        Button("Zaloguj przez Microsoft") { Task { await state.signIn() } }
                        Text("Wymaga własnej rejestracji aplikacji Microsoft Entra i ustawienia Client ID.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(state.message).font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("Konto")
            }.tabItem { Label("Konto", systemImage: "person.crop.circle") }.tag(1)

            NavigationStack {
                List {
                    Section("Dodaj serwer") {
                        TextField("Nazwa", text: $serverName)
                        TextField("Adres, np. example.org:25565", text: $serverAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Zapisz") {
                            state.addServer(name: serverName, address: serverAddress)
                            serverName = ""; serverAddress = ""
                        }
                    }
                    Section("Ulubione — tylko zapis adresów") {
                        ForEach(state.servers) { server in
                            VStack(alignment: .leading) {
                                Text(server.name).bold()
                                Text(server.address).font(.caption).textSelection(.enabled)
                            }
                        }.onDelete { state.servers.remove(atOffsets: $0) }
                    }
                    Text("Multiplayer wymaga działającego klienta Java. Lista nie łączy z serwerami.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("Serwery")
            }.tabItem { Label("Serwery", systemImage: "network") }.tag(2)

            NavigationStack {
                VStack(spacing: 15) {
                    Text("Sterowanie dotykowe").font(.title2.bold())
                    TouchOverlayView()
                        .frame(height: 380)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                    Text("Układ przycisków można przeciągać i zapisywać. Zdarzenia wejścia nie są jeszcze podłączone do gry.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Kontrolery: \(GCController.controllers().count)")
                    Spacer()
                }.padding().navigationTitle("Sterowanie")
            }.tabItem { Label("Sterowanie", systemImage: "gamecontroller") }.tag(3)
        }.tint(.cyan)
    }
}
