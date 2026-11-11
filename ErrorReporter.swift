import Foundation
import SwiftUI
import UIKit
import MetricKit

/// Where "Report a bug" emails go. Change this if you use a different address.
enum SupportContact {
    static let email = "support@nuvigo.app"
}

/// Sends short, anonymous error messages to your own server (POST /api/report).
/// No account, email, watch history or links are included, and web addresses are
/// cut down to just the site name before sending. Users can turn it off in Account > Privacy.
enum ErrorReporter {
    static let enabledKey = "sendErrorReports"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static var sentThisSession = 0
    private static var recent: [String: Date] = [:]

    static func report(_ message: String, kind: String = "error", context: String = "") {
        guard enabled, Config.isSet(Config.serverURL),
              let url = URL(string: Config.serverURL + "/api/report") else { return }
        let msg = scrub(message)
        guard !msg.isEmpty, sentThisSession < 15 else { return }
        let id = kind + msg
        if let last = recent[id], Date().timeIntervalSince(last) < 120 { return }   // don't repeat the same error
        recent[id] = Date()
        sentThisSession += 1

        let body: [String: String] = [
            "kind": kind, "message": msg, "context": scrub(context),
            "app": appVersion, "os": UIDevice.current.systemVersion, "device": deviceModel,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        Task.detached(priority: .background) { _ = try? await URLSession.shared.data(for: req) }
    }

    /// Keeps only the site name of any web address, and drops long token-like strings.
    static func scrub(_ text: String) -> String {
        var out = text
        if let re = try? NSRegularExpression(pattern: #"https?://([^/\s?#]+)[^\s]*"#) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
        }
        if let re = try? NSRegularExpression(pattern: #"[A-Za-z0-9_\-]{28,}"#) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "[hidden]")
        }
        return String(out.prefix(500))
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    static var deviceModel: String {
        var sys = utsname(); uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Reports crashes that iOS collected on the previous run (MetricKit). Needs no extra setup.
final class CrashListener: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashListener()
    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                let type = c.exceptionType.map { "type \($0)" } ?? ""
                let sig = c.signal.map { "signal \($0)" } ?? ""
                let why = c.terminationReason ?? ""
                ErrorReporter.report("Crash \(type) \(sig) \(why)".trimmingCharacters(in: .whitespaces), kind: "crash")
            }
            for h in p.hangDiagnostics ?? [] {
                ErrorReporter.report("App hang \(h.hangDuration.formatted())", kind: "hang")
            }
        }
    }
}

/// Builds the "Report a bug" email with useful details already filled in.
enum BugReport {
    static var mailURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = SupportContact.email
        let body = """


        Please describe what happened above this line.
        ----
        NuviGo \(ErrorReporter.appVersion)
        iOS \(UIDevice.current.systemVersion)
        Device \(ErrorReporter.deviceModel)
        """
        c.queryItems = [
            URLQueryItem(name: "subject", value: "NuviGo bug report"),
            URLQueryItem(name: "body", value: body),
        ]
        return c.url
    }
}
