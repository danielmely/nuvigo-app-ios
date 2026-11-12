import SwiftUI
import Combine

/// The "NuviGo account" block at the top of the Account tab.
struct NuviAccountSection: View {
    @EnvironmentObject var account: NuviAccount
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var progress: ProgressStore

    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var deletePassword = ""

    var body: some View {
        CollapsibleSection("NuviGo account", startOpen: true) {
            if !account.isConfigured {
                Label("Add your server address in Config.swift to turn on accounts.", systemImage: "server.rack")
                    .font(.footnote)
            } else if let email = account.email {
                LabeledContent("Signed in as", value: email)
                Button {
                    Task { await account.sync(store: store, progress: progress, force: true) }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if account.busy { ProgressView() }
                        else if let t = account.lastSync {
                            Text(t, style: .relative).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if account.needsRestart {
                    Label("Your synced logins are saved. Close and reopen NuviGo to load them.", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                if let e = account.error { Text(e).font(.footnote).foregroundStyle(.red) }
                Button("Sign out", role: .destructive) { account.signOut() }
                Button("Delete account…", role: .destructive) { deletePassword = ""; confirmDelete = true }
            } else {
                Text("Sign in to keep your addons, watch progress, settings and linked logins on every device.")
                    .font(.footnote)
                Button {
                    showSignIn = true
                } label: {
                    Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } footer: {
            if account.isSignedIn {
                Text("Syncs your addon list, watch progress, appearance and playback settings, and your linked logins. Your Trakt watchlist travels with your Trakt login.")
            }
        }
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            SecureField("Password", text: $deletePassword)
            Button("Delete", role: .destructive) {
                Task { _ = await account.deleteAccount(password: deletePassword) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your NuviGo account and the synced copy on the server. What's on this device stays. Enter your password to confirm.")
        }
    }
}

struct SignInSheet: View {
    @EnvironmentObject var account: NuviAccount
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var showReset = false

    private var canSubmit: Bool { email.contains("@") && password.count >= (creating ? 8 : 1) && !account.busy }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $creating) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField(creating ? "Password (8+ characters)" : "Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                } footer: {
                    if let e = account.error { Text(e).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task {
                            let ok = creating ? await account.signUp(email: email, password: password)
                                              : await account.signIn(email: email, password: password)
                            if ok {
                                await account.sync(store: store, progress: progress, force: true)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if account.busy { ProgressView() } else { Text(creating ? "Create account" : "Sign in").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)

                    if !creating {
                        Button("Forgot password?") { showReset = true }
                            .font(.footnote)
                    }
                }
            }
            .sheet(isPresented: $showReset) {
                ForgotPasswordSheet(email: email) { dismiss() }
            }
            .navigationTitle(creating ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { account.error = nil }
            .onChange(of: creating) { _, _ in account.error = nil }
        }
    }
}

/// Shown under the sign-in box until a NuviGo account exists.
struct AccountPerksSection: View {
    var body: some View {
        Section("With a NuviGo account you can") {
            Label("Sync addons, progress and settings on every device", systemImage: "arrow.triangle.2.circlepath")
                .padding(.vertical, 8)
            Label("Link Trakt, Simkl, AniList, MyAnimeList, Jellyfin, Plex, debrid, subtitles and more", systemImage: "link")
                .padding(.vertical, 8)
            Label("Keep your watched list, ratings and picks", systemImage: "checkmark.circle")
                .padding(.vertical, 8)
            Label("Restore everything on a new phone", systemImage: "iphone")
                .padding(.vertical, 8)
        }
        .font(.footnote)
        .lineSpacing(3)
    }
}


/// Two steps: ask for a code by email, then enter the code and a new password.
struct ForgotPasswordSheet: View {
    @EnvironmentObject var account: NuviAccount
    @EnvironmentObject var store: AddonStore
    @EnvironmentObject var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    let onSignedIn: () -> Void
    @State private var codeSent = false
    @State private var code = ""
    @State private var password = ""

    init(email: String, onSignedIn: @escaping () -> Void) {
        _email = State(initialValue: email)
        self.onSignedIn = onSignedIn
    }

    private var canSend: Bool { email.contains("@") && !account.busy }
    private var canReset: Bool { code.count == 6 && password.count >= 8 && !account.busy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .disabled(codeSent)
                } footer: {
                    if !codeSent { Text("We'll email you a 6-digit code. It works for 15 minutes.") }
                }

                if !codeSent {
                    Section {
                        Button {
                            Task { if await account.requestPasswordReset(email: email) { codeSent = true } }
                        } label: {
                            HStack {
                                Spacer()
                                if account.busy { ProgressView() } else { Text("Send code").bold() }
                                Spacer()
                            }
                        }
                        .disabled(!canSend)
                    } footer: {
                        if let e = account.error { Text(e).foregroundStyle(.red) }
                    }
                } else {
                    Section {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                        SecureField("New password (8+ characters)", text: $password)
                            .textContentType(.newPassword)
                    } footer: {
                        if let e = account.error { Text(e).foregroundStyle(.red) }
                        else { Text("If an account exists for that email, a code is on its way. Check your spam folder too.") }
                    }
                    Section {
                        Button {
                            Task {
                                if await account.resetPassword(email: email, code: code, password: password) {
                                    await account.sync(store: store, progress: progress, force: true)
                                    dismiss()
                                    onSignedIn()
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if account.busy { ProgressView() } else { Text("Set new password").bold() }
                                Spacer()
                            }
                        }
                        .disabled(!canReset)
                        Button("Send a new code") {
                            Task { _ = await account.requestPasswordReset(email: email) }
                        }
                        .disabled(account.busy)
                    }
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { account.error = nil }
        }
    }
}
