import SwiftUI
import StoreKit
import CryptoKit

/// Everything you need to change about the subscription lives here.
enum SubscriptionConfig {
    /// Must match the product ID you create in App Store Connect (and in NuviGo.storekit for testing).
    static let productID = "com.nuvigo.app.monthly"
    /// The app is free right now, so this is off: no paywall, and the subscription sections are hidden.
    /// Everything for subscriptions is still here. Set to true (and create the product in App Store Connect) to bring it back.
    static let required = false
    /// The legal pages are served by the NuviGo server (legal.js). When nuvigo.app is live, put its address here instead.
    static var siteBase: String { Config.isSet(Config.serverURL) ? Config.serverURL : "https://nuvigo.app" }
    static var termsURL: URL { URL(string: siteBase + "/terms")! }
    static var privacyURL: URL { URL(string: siteBase + "/privacy")! }
    static var supportURL: URL { URL(string: siteBase + "/support")! }
    static var acknowledgementsURL: URL { URL(string: siteBase + "/acknowledgements")! }
}

/// Monthly auto-renewing subscription, handled with StoreKit 2. The App Store is the source of truth:
/// on every launch the app asks it which subscriptions are active, so nothing is stored on a server.
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isSubscribed = false
    @Published private(set) var inTrial = false
    @Published private(set) var renews: Date?
    @Published private(set) var checking = true          // the first entitlement check hasn't finished
    @Published private(set) var busy = false
    @Published var error: String?

    private var updates: Task<Void, Never>?

    /// True when the paywall should cover the app.
    /// True while the subscription page is on screen. Browsing and search are free; anything else opens it.
    @Published var showPaywall = false
    var locked: Bool { SubscriptionConfig.required && !checking && !isSubscribed && !demoActive }

    // MARK: Demo access (hidden: five fast taps in the top right corner of the paywall)

    private static let demoKey = "demoUntil"
    private static let demoHash = SHA256.hash(data: Data("admin420".utf8)).map { String(format: "%02x", $0) }.joined()
    @Published private var demoUntil: Date? = {
        let t = UserDefaults.standard.double(forKey: "demoUntil")
        return t > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: t) : nil
    }()
    private var demoTimer: Task<Void, Never>?

    var demoActive: Bool { (demoUntil ?? .distantPast) > Date() }

    /// Returns true and unlocks everything for one hour if the password is right.
    func startDemo(password: String) -> Bool {
        let h = SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
        guard h == Self.demoHash else { return false }
        let end = Date().addingTimeInterval(3600)
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.demoKey)
        demoUntil = end
        showPaywall = false
        scheduleDemoEnd(end)
        return true
    }

    private func scheduleDemoEnd(_ end: Date) {
        demoTimer?.cancel()
        demoTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, end.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.demoUntil = nil
            UserDefaults.standard.removeObject(forKey: Self.demoKey)
        }
    }

    /// Call before any feature beyond browsing and search. Returns false (and opens the page) if not subscribed.
    func allow() -> Bool {
        if !locked { return true }
        showPaywall = true
        return false
    }

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        if let end = demoUntil { scheduleDemoEnd(end) }
        Task { await load() }
    }

    deinit { updates?.cancel() }

    func load() async {
        do { product = try await Product.products(for: [SubscriptionConfig.productID]).first }
        catch { self.error = "Couldn't reach the App Store. Check your connection and try again." }
        await refresh()
    }

    /// Asks the App Store which subscriptions are active right now.
    func refresh() async {
        var active = false, trial = false
        var end: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.productID == SubscriptionConfig.productID,
                  t.revocationDate == nil else { continue }
            if let exp = t.expirationDate, exp < Date() { continue }
            active = true
            end = t.expirationDate
            if t.offerType == .introductory { trial = true }
        }
        isSubscribed = active
        inTrial = trial
        renews = end
        checking = false
    }

    func purchase() async {
        guard let product else { await load(); return }
        busy = true; error = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish(); await refresh() }
                else { error = "The purchase couldn't be verified. Please try again." }
            case .pending:
                error = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            self.error = "The purchase didn't go through. Please try again."
        }
    }

    func restore() async {
        busy = true; error = nil
        defer { busy = false }
        do { try await AppStore.sync() } catch { self.error = "Couldn't restore purchases. Please try again." }
        await refresh()
        if !isSubscribed && error == nil { error = "No active subscription was found for this Apple ID." }
    }

    /// "7 days free, then $4.99 per month", built from what the App Store reports.
    var priceLine: String {
        guard let p = product else { return "Loading price…" }
        let per = p.displayPrice + " per month"
        if let offer = p.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return "\(Self.periodText(offer.period)) free, then \(per)"
        }
        return per
    }

    /// Paywall headline. The price comes from the App Store so it always matches what is charged.
    var launchLine: String {
        guard let p = product else { return "Loading price…" }
        if hasTrialOffer { return "1 Week Free Trial, then only \(p.displayPrice) a month!" }
        return "Only \(p.displayPrice) a month!"
    }

    var hasTrialOffer: Bool { product?.subscription?.introductoryOffer?.paymentMode == .freeTrial }

    private static func periodText(_ p: Product.SubscriptionPeriod) -> String {
        let n = p.value
        switch p.unit {
        case .day: return n == 7 ? "1 week" : "\(n) day\(n == 1 ? "" : "s")"
        case .week: return "\(n) week\(n == 1 ? "" : "s")"
        case .month: return "\(n) month\(n == 1 ? "" : "s")"
        case .year: return "\(n) year\(n == 1 ? "" : "s")"
        @unknown default: return "\(n)"
        }
    }
}

// MARK: - Paywall

/// Covers the app until there's an active subscription.
struct PaywallView: View {
    @EnvironmentObject var subs: SubscriptionStore
    @Environment(\.colorScheme) private var scheme
    @State private var taps: [Date] = []
    @State private var askDemo = false
    @State private var demoPassword = ""
    @State private var demoWrong = false

    private let perks: [(String, String)] = [
        ("play.rectangle.on.rectangle.fill", "Stream from every addon you install"),
        ("arrow.down.circle.fill", "Download movies and shows to watch offline"),
        ("sparkles", "Movie and show suggestions customized to you"),
        ("captions.bubble.fill", "Subtitles in your language"),
        ("lock.shield.fill", "Profiles, app lock and private mode"),
        ("arrow.triangle.2.circlepath", "Sync across all your devices"),
        ("slider.horizontal.3", "Ratings filter, languages and sleep timer")
    ]

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 54/255, green: 58/255, blue: 67/255) : Color.white).ignoresSafeArea()
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 22) {
                    if let mark = LogoData.mark {
                        Image(uiImage: mark).resizable().scaledToFit().frame(width: 84, height: 84).padding(.top, 36)
                    }
                    VStack(spacing: 6) {
                        Text("NuviGo Premium").font(.largeTitle.bold())
                        Text("Everything unlocked. Cancel anytime.").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(perks, id: \.1) { p in
                            Label { Text(p.1) } icon: { Image(systemName: p.0).foregroundStyle(Theme.accent).frame(width: 28) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 28).padding(.horizontal, 18)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))

                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Text("Payment is charged to your Apple ID at confirmation. The subscription renews automatically each month unless it is cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings › Apple ID › Subscriptions.")
                            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Link("Terms of Use", destination: SubscriptionConfig.termsURL)
                            Link("Privacy Policy", destination: SubscriptionConfig.privacyURL)
                        }
                        .font(.caption)
                    }
                    VStack(spacing: 10) {
                        Text("🎬 Launch Week Special 🍿").font(.headline)
                        Text(subs.launchLine).font(.headline).multilineTextAlignment(.center)
                        Button {
                            Task { await subs.purchase() }
                        } label: {
                            Group {
                                if subs.busy { ProgressView().tint(.white) }
                                else { Text(subs.hasTrialOffer ? "Start free trial" : "Subscribe").font(.headline) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(subs.busy || subs.product == nil)

                        if let e = subs.error { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }

                        Button("Restore purchases") { Task { await subs.restore() } }
                            .font(.subheadline)
                            .disabled(subs.busy)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 22)
                .frame(minHeight: geo.size.height)
            }
            }
            Button { withAnimation { subs.showPaywall = false } } label: {
                Label("Home", systemImage: "house.fill").font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 22).padding(.top, 12)
            // Invisible hit area. Five quick taps open the demo box.
            Color.clear
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture {
                    let now = Date()
                    taps = taps.filter { now.timeIntervalSince($0) < 2 } + [now]
                    if taps.count >= 5 { taps = []; demoPassword = ""; demoWrong = false; askDemo = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .alert("Demo Use?", isPresented: $askDemo) {
            SecureField("Password", text: $demoPassword)
            Button("Start demo") { if !subs.startDemo(password: demoPassword) { demoWrong = true } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Enter the demo password for 1 hour of full access.") }
        .alert("Wrong password", isPresented: $demoWrong) { Button("OK", role: .cancel) {} }
    }
}

// MARK: - Account section

struct SubscriptionSection: View {
    @EnvironmentObject var subs: SubscriptionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        CollapsibleSection("Subscription") {
            LabeledContent("Plan", value: subs.isSubscribed ? (subs.inTrial ? "NuviGo Premium (free trial)" : "NuviGo Premium") : "None")
            if let d = subs.renews, subs.isSubscribed {
                LabeledContent(subs.inTrial ? "Trial ends" : "Renews", value: d.formatted(date: .abbreviated, time: .omitted))
            }
            if let e = subs.error { Text(e).font(.footnote).foregroundStyle(.red) }
        }
    }
}

/// VPNs suggested on the Add-ons page. No prices are shown (they change often); people check the site.
/// If you ever earn money from these links, say so in your Privacy Policy and App Store notes.
struct VPNPick: Identifiable {
    let name: String, tag: String, blurb: String, icon: String, url: URL
    var id: String { name }
}

enum RecommendedVPN {
    static let picks: [VPNPick] = [
        VPNPick(name: "Surfshark", tag: "Cheapest", blurb: "Low long-term pricing and unlimited devices.",
                icon: "dollarsign.circle", url: URL(string: "https://surfshark.com")!),
        VPNPick(name: "ExpressVPN", tag: "Most expensive", blurb: "Premium pricing, known for speed and easy-to-use apps.",
                icon: "crown", url: URL(string: "https://www.expressvpn.com")!),
        VPNPick(name: "Windscribe", tag: "Most customizable", blurb: "Build your own plan, choose your protocol and fine-tune the built-in ad and tracker blocker.",
                icon: "slider.horizontal.3", url: URL(string: "https://windscribe.com")!),
    ]
}

/// One tidy row: tinted icon, title, optional small caption underneath.
struct BottomRowLabel: View {
    let icon: String
    let title: LocalizedStringKey
    var caption: LocalizedStringKey? = nil
    var tint: Color = .accentColor
    var external = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(tint == .red ? Color.red : Color.primary)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if external {
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Always at the very bottom of the Account page, never collapsed.
struct AccountBottomSection: View {
    @EnvironmentObject var subs: SubscriptionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            ClearCacheSection()
            ClearDataSection()
            ResetDefaultsSection()
        } header: {
            Text("Storage & data").font(.headline).textCase(nil)
        }

        if SubscriptionConfig.required {
            Section {
                Button { Task { await subs.restore() } } label: {
                    BottomRowLabel(icon: "arrow.clockwise.circle", title: "Restore purchases",
                                   caption: "Already subscribed on another device? Get it back here.")
                }
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                } label: {
                    BottomRowLabel(icon: "xmark.circle", title: "Cancel subscription", tint: .red,
                                   caption: "Opens your Apple ID subscriptions, where you can turn off renewal.", external: true)
                }
            } header: {
                Text("Subscription").font(.headline).textCase(nil)
            }
        }

        Section {
            Button {
                if let url = BugReport.mailURL { openURL(url) }
            } label: {
                BottomRowLabel(icon: "ladybug", title: "Report a bug",
                               caption: "Opens an email to \(SupportContact.email) with your app and iOS version filled in.", external: true)
            }
        } header: {
            Text("Help").font(.headline).textCase(nil)
        }

        Section {
            Link(destination: SubscriptionConfig.termsURL) {
                BottomRowLabel(icon: "doc.text", title: "Terms of Use", external: true)
            }
            Link(destination: SubscriptionConfig.privacyURL) {
                BottomRowLabel(icon: "hand.raised", title: "Privacy Policy", external: true)
            }
            Link(destination: SubscriptionConfig.acknowledgementsURL) {
                BottomRowLabel(icon: "heart.text.square", title: "Acknowledgements", external: true)
            }
        } header: {
            Text("Legal").font(.headline).textCase(nil)
        }
    }
}
