import Foundation

struct SimklPin: Decodable {
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int
}

/// Simkl watch history. Sign-in uses a code you enter at simkl.com/pin, like Trakt.
@MainActor
final class SimklAuth: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var pin: SimklPin?
    @Published var error: String?

    private let keychainKey = "simkl.token"
    var isSignedIn: Bool { token != nil }
    var isConfigured: Bool { Config.isSet(Config.simklClientID) }

    init() {
        token = Keychain.load(key: keychainKey).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Shows `pin` for the user to enter, then polls until approved. Cancel the surrounding Task to abort.
    func signIn() async {
        error = nil
        guard isConfigured else { error = "Add your Simkl Client ID in Config.swift first."; return }
        let clientID = Config.simklClientID
        do {
            guard let url = HTTP.url("https://api.simkl.com/oauth/pin", query: ["client_id": clientID]) else { return }
            let (status, data) = try await HTTP.send(url)
            guard status == 200, let p = try? JSONDecoder().decode(SimklPin.self, from: data) else {
                error = "Simkl returned \(status)."
                return
            }
            pin = p
            let deadline = Date().addingTimeInterval(TimeInterval(p.expires_in))
            while Date() < deadline {
                try await Task.sleep(for: .seconds(max(p.interval, 3)))
                guard let poll = HTTP.url("https://api.simkl.com/oauth/pin/\(p.user_code)", query: ["client_id": clientID]) else { return }
                let (_, body) = try await HTTP.send(poll)
                if let obj = HTTP.object(body), obj["result"] as? String == "OK", let t = obj["access_token"] as? String {
                    token = t
                    Keychain.save(Data(t.utf8), key: keychainKey)
                    pin = nil
                    return
                }
            }
            error = "The code expired. Try again."
            pin = nil
        } catch is CancellationError {
            pin = nil
        } catch {
            self.error = error.localizedDescription
            pin = nil
        }
    }

    func signOut() {
        token = nil; pin = nil
        Keychain.delete(key: keychainKey)
    }

    /// Adds a finished movie or episode to your Simkl history (IMDb-style ids only).
    func markWatched(_ ctx: PlaybackContext) async {
        guard let token, let ref = TitleRef(ctx) else { return }
        let body: [String: Any]
        if ctx.item.type == "series", let s = ref.season, let e = ref.episode {
            body = ["shows": [["ids": ["imdb": ref.imdb],
                               "seasons": [["number": s, "episodes": [["number": e]]]]]]]
        } else {
            body = ["movies": [["ids": ["imdb": ref.imdb]]]]
        }
        guard let url = URL(string: "https://api.simkl.com/sync/history") else { return }
        _ = try? await HTTP.send(url, method: "POST", headers: [
            "Content-Type": "application/json",
            "simkl-api-key": Config.simklClientID,
            "Authorization": "Bearer \(token)",
        ], body: HTTP.json(body))
    }
}
