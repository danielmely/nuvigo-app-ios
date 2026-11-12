import SwiftUI
import Combine
import StoreKit

/// Optional tips. Create these four as Consumable in-app purchases in App Store Connect
/// (and they are already in NuviGo.storekit for testing). Pick any prices you like.
enum TipConfig {
    static let tiers: [(id: String, emoji: String, name: String)] = [
        ("com.nuvigo.tip.small",  "☕️", "A coffee"),
        ("com.nuvigo.tip.medium", "🍿", "Popcorn"),
        ("com.nuvigo.tip.large",  "🎬", "Movie night"),
        ("com.nuvigo.tip.huge",   "❤️", "Big thanks"),
    ]
}

@MainActor
final class TipStore: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var busyID: String?
    @Published var thanks = false
    @Published var error: String?

    func load() async {
        guard products.isEmpty else { return }
        do {
            let list = try await Product.products(for: TipConfig.tiers.map(\.id))
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            self.error = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    func tip(_ id: String, quantity: Int = 1) async {
        guard let p = products[id] else { await load(); return }
        busyID = id; error = nil; thanks = false
        defer { busyID = nil }
        do {
            switch try await p.purchase(options: quantity > 1 ? [.quantity(quantity)] : []) {
            case .success(let result):
                if case .verified(let t) = result { await t.finish(); thanks = true }
                else { error = "The tip couldn't be verified. You were not charged." }
            case .pending:
                error = "Your tip is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            self.error = "The tip didn't go through. Please try again."
        }
    }
}

/// The Tips tab. NuviGo is free; tips are one-time, optional and unlock nothing.
struct TipsView: View {
    @StateObject private var store = TipStore()
    /// Custom amount = this many of the $4.99 tip, so it goes up about $5 at a time. The App Store allows 1 to 10 per purchase.
    @State private var customQty = 1
    private var unit: Product? { store.products[TipConfig.tiers[2].id] }
    private var customTotal: String {
        guard let u = unit else { return "…" }
        return u.priceFormatStyle.format(u.price * Decimal(customQty))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accent).padding(.top, 28)
                    Text("Support NuviGo").font(.title2.bold())
                    Text("NuviGo is free, with no ads and no paywall. If you'd like to help cover server costs and keep it going, you can leave a tip. It's completely optional and doesn't unlock anything.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        ForEach(TipConfig.tiers, id: \.id) { t in
                            Button { Task { await store.tip(t.id) } } label: {
                                HStack(spacing: 14) {
                                    Text(t.emoji).font(.title)
                                    Text(LocalizedStringKey(t.name)).font(.headline)
                                    Spacer()
                                    if store.busyID == t.id { ProgressView() }
                                    else { Text(store.products[t.id]?.displayPrice ?? "…").font(.headline).foregroundStyle(Theme.accent) }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.busyID != nil || store.products[t.id] == nil)
                        }
                    }
                    .padding(.top, 6)

                    // Custom amount: pick how many of the smallest tip.
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            Text("✏️").font(.title)
                            Text("Custom amount").font(.headline)
                            Spacer()
                            HStack(spacing: 14) {
                                Button { customQty = max(1, customQty - 1) } label: {
                                    Image(systemName: "minus.circle.fill").font(.title2)
                                }
                                .disabled(customQty <= 1)
                                Text("\(customQty)").font(.headline).monospacedDigit().frame(minWidth: 22)
                                Button { customQty = min(10, customQty + 1) } label: {
                                    Image(systemName: "plus.circle.fill").font(.title2)
                                }
                                .disabled(customQty >= 10)
                            }
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                        }
                        Button { Task { await store.tip(TipConfig.tiers[2].id, quantity: customQty) } } label: {
                            Group {
                                if store.busyID == TipConfig.tiers[2].id { ProgressView().tint(.white) }
                                else { Text("Tip \(customTotal)").font(.headline) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.busyID != nil || unit == nil)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if store.thanks {
                        Label("Thank you! Your support means a lot.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                    }
                    if let e = store.error { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }

                    Text("Tips are one-time payments handled by Apple. They don't give you extra features, and refunds are handled by Apple.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 6)
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.load() }
        }
    }
}
