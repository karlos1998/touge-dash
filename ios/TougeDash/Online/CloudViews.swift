import AuthenticationServices
import SwiftUI

struct CloudSyncCard: View {
    @ObservedObject var account: CloudAccountService
    @ObservedObject var sync: CloudSyncManager
    @State private var showingAuthentication = false
    @State private var vehicleName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeCyan.opacity(0.12))
                    Image(systemName: account.isAuthenticated ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(account.isAuthenticated ? Color.tougeCyan : .secondary)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("TOUGE DASH CLOUD")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(sync.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            if let account = account.account {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.subheadline.weight(.bold))
                        Text(account.email)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wyloguj") {
                        Task {
                            await self.account.logout()
                            await sync.accountDidChange()
                        }
                    }
                    .font(.caption.weight(.bold))
                }

                if sync.state == .waitingForVehicleName {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("NAZWA NOWEGO AUTA")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1)
                            .foregroundStyle(Color.tougeCyan)
                        HStack {
                            TextField("np. Impreza STI", text: $vehicleName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                            Button("Dodaj") {
                                let name = vehicleName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                Task { await sync.confirmVehicle(name: name) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.tougeCyan)
                            .foregroundStyle(.black)
                        }
                        Text("To EMULOGGER będzie od teraz rozpoznawany automatycznie.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if let vehicle = sync.activeVehicle {
                    HStack {
                        Label(vehicle.displayName, systemImage: "car.side.fill")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(sync.pendingSessions) OCZEKUJE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(sync.pendingSessions == 0 ? Color.tougeMint : Color.tougeOrange)
                        Button {
                            Task { await sync.syncNow() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sync.state == .syncing)
                    }
                } else {
                    Text("Połącz się z EMULOGGER, aby przypisać pierwsze auto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showingAuthentication = true
                } label: {
                    HStack {
                        Text("Włącz synchronizację online")
                            .font(.subheadline.weight(.black))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.tougeCyan)
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .cardSurface(accent: account.isAuthenticated ? .tougeCyan : .gray)
        .sheet(isPresented: $showingAuthentication) {
            CloudAuthenticationView(account: account) {
                showingAuthentication = false
                Task { await sync.accountDidChange() }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let active = account.isAuthenticated && sync.state != .offline
        HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.tougeMint : Color.secondary)
                .frame(width: 6, height: 6)
            Text(active ? "ONLINE" : "LOCAL")
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
        }
        .foregroundStyle(active ? Color.tougeMint : .secondary)
    }
}

private struct CloudAuthenticationView: View {
    enum Mode { case login, register }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: CloudAccountService
    let onAuthenticated: () -> Void
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var formError: String?
    @State private var showingServer = false
    @StateObject private var webAuthentication = CloudWebAuthenticationSession()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.tougeCyan)
                        Text("TOUGE DASH")
                            .font(.title2.weight(.black))
                            .tracking(2)
                        Text(mode == .login ? "Zaloguj się do swojego garażu" : "Utwórz konto")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)

                    Picker("Tryb", selection: $mode) {
                        Text("Logowanie").tag(Mode.login)
                        Text("Nowe konto").tag(Mode.register)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 11) {
                        if mode == .register {
                            TextField("Imię lub nazwa", text: $displayName)
                                .textContentType(.name)
                        }
                        TextField("E-mail", text: $email)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        SecureField(mode == .login ? "Hasło" : "Hasło · minimum 10 znaków", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                    }
                    .textFieldStyle(CloudTextFieldStyle())

                    if mode == .register, !password.isEmpty {
                        passwordStatus
                    }

                    if let formError {
                        Text(formError)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.tougeOrange)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        if let validationMessage {
                            formError = validationMessage
                            return
                        }
                        formError = nil
                        Task {
                            let success = if mode == .login {
                                await account.login(email: email, password: password)
                            } else {
                                await account.register(email: email, password: password, displayName: displayName)
                            }
                            if success { onAuthenticated() }
                        }
                    } label: {
                        Text(account.isWorking ? "ŁĄCZĘ…" : mode == .login ? "ZALOGUJ" : "UTWÓRZ KONTO")
                            .font(.system(size: 12, weight: .black))
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.tougeCyan)
                    .foregroundStyle(.black)
                    .disabled(account.isWorking)

                    HStack {
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                        Text("LUB").font(.caption2.weight(.black)).foregroundStyle(.tertiary)
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                    }

                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        ProviderButton(title: "Google", icon: "G") {
                            Task { await handleWebAuthentication(provider: "google") }
                        }
                        ProviderButton(title: "Facebook", icon: "f") {
                            Task { await handleWebAuthentication(provider: "facebook") }
                        }
                    }

                    if let error = account.lastError {
                        Text(error)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.tougeOrange)
                            .multilineTextAlignment(.center)
                    }

                    DisclosureGroup("Adres serwera", isExpanded: $showingServer) {
                        VStack(spacing: 8) {
                            TextField("API · https://api.example.com", text: $account.serverAddress)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .textFieldStyle(CloudTextFieldStyle())
                            TextField("Web · https://app.example.com", text: $account.webAddress)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .textFieldStyle(CloudTextFieldStyle())
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(DashboardBackground())
            .navigationTitle("Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { account.clearError() }
        .onChange(of: mode) {
            password = ""
            formError = nil
            account.clearError()
        }
    }

    private var validationMessage: String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
            return "Podaj poprawny adres e-mail."
        }
        if password.isEmpty {
            return "Podaj hasło."
        }
        if mode == .register {
            if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Podaj nazwę wyświetlaną."
            }
            if !CloudPasswordPolicy.isValid(password) {
                return "Hasło musi mieć 10–72 znaki oraz zawierać literę i cyfrę."
            }
        }
        return nil
    }

    private var passwordStatus: some View {
        let strength = CloudPasswordPolicy.strength(password)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Siła hasła")
                Spacer()
                Text(strength.label).fontWeight(.bold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(strength.score), total: 4)
                .tint(CloudPasswordPolicy.isValid(password) ? Color.tougeMint : Color.tougeOrange)
            HStack(spacing: 12) {
                passwordRequirement("10–72 znaki", password.count >= 10 && password.count <= 72)
                passwordRequirement("litera", password.rangeOfCharacter(from: .letters) != nil)
                passwordRequirement("cyfra", password.rangeOfCharacter(from: .decimalDigits) != nil)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func passwordRequirement(_ title: String, _ met: Bool) -> some View {
        Label(title, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(met ? Color.tougeMint : .secondary)
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        do {
            guard case .success(let authorization) = result,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw CloudAPIError.invalidResponse
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            if await account.signInWithApple(identityToken: token, displayName: name), account.isAuthenticated {
                onAuthenticated()
            }
        } catch {
            account.clearError()
        }
    }

    private func handleWebAuthentication(provider: String) async {
        do {
            let code = try await webAuthentication.authenticate(webAddress: account.webAddress, provider: provider)
            if await account.exchangeMobileHandoff(code: code) {
                onAuthenticated()
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            account.report(error)
        }
    }
}

private struct CloudTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }
}

private struct ProviderButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(icon).font(.headline.weight(.black))
                Text(title).font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.bordered)
    }
}
