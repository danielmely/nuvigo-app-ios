import AuthenticationServices
import UIKit

/// Runs a browser sign-in (AniList, MyAnimeList) and returns the URL the site redirected back to.
@MainActor
enum WebAuth {
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }

    private static var active: (ASWebAuthenticationSession, Presenter)?

    /// Throws `CancellationError` if the user closes the sign-in sheet.
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let presenter = Presenter()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                Task { @MainActor in active = nil }
                if let callback {
                    cont.resume(returning: callback)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    cont.resume(throwing: CancellationError())
                } else {
                    cont.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            session.presentationContextProvider = presenter
            active = (session, presenter)   // keep both alive until the callback fires
            session.start()
        }
    }
}
