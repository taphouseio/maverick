import Crypto
import Foundation
import MaverickBroadcast
import MaverickLib
import ShellOut
import Vapor

struct AdminRouteCollection: RouteCollection {
    let runtime: BroadcastRuntime?

    func boot(routes router: RoutesBuilder) throws {
        let root = router.grouped("_admin").grouped(AdminHTTPSMiddleware())
        guard let runtime else { return }
        let adminRouter = root.grouped(AdminBasicAuthMiddleware(runtime: runtime), AdminCSRFMiddleware())

        adminRouter.post("reload") { _ -> Response in
            AdminController.reloadActionTriggered()
                ? Response(status: .ok)
                : Response(status: .internalServerError)
        }
        adminRouter.get("broadcast") { req async throws -> Response in
            try await broadcastPage(req: req, runtime: runtime)
        }
        adminRouter.post("broadcast", "initialize") { req async throws -> Response in
            try await requireCoordinator(runtime).initialize(with: runtime.currentPosts())
            return redirectToAdmin(req)
        }
        adminRouter.post("broadcast", "backfill") { req async throws -> Response in
            let form = try req.content.decode(DeliveryForm.self)
            try await requireCoordinator(runtime).backfill(postID: form.postID, providerIDs: [form.providerID])
            return redirectToAdmin(req)
        }
        adminRouter.post("broadcast", "retry") { req async throws -> Response in
            let form = try req.content.decode(DeliveryForm.self)
            try await requireCoordinator(runtime).retry(postID: form.postID, providerID: form.providerID)
            return redirectToAdmin(req)
        }
        adminRouter.post("broadcast", "explicitly-queue") { req async throws -> Response in
            let form = try req.content.decode(DeliveryForm.self)
            try await requireCoordinator(runtime).explicitlyQueue(postID: form.postID, providerID: form.providerID)
            return redirectToAdmin(req)
        }
        adminRouter.post("broadcast", "check") { req async throws -> Response in
            let form = try req.content.decode(ProviderForm.self)
            try await requireCoordinator(runtime).checkConnection(providerID: form.providerID)
            return redirectToAdmin(req, message: "Connection succeeded for \(form.providerID)")
        }
        adminRouter.get("broadcast", "preview") { req async throws -> Response in
            let query = try req.query.decode(DeliveryQuery.self)
            let preview = try await requireCoordinator(runtime).preview(
                postID: query.postID,
                providerID: query.providerID
            )
            return htmlResponse("<h1>Preview</h1><pre>\(escape(preview))</pre><p><a href=\"/_admin/broadcast\">Back</a></p>")
        }
        adminRouter.post("broadcast", "linkedin", "connect") { req async throws -> Response in
            let form = try req.content.decode(ProviderForm.self)
            let state = try await requireCoordinator(runtime).beginOAuth(providerID: form.providerID)
            let url = try runtime.linkedinOAuthClient(providerID: form.providerID)
                .authorizationURL(redirectURI: try linkedinCallbackURL(), state: state)
            return req.redirect(to: url.absoluteString)
        }
        adminRouter.post("broadcast", "restore") { req async throws -> Response in
            let form = try req.content.decode(RestoreForm.self)
            try await requireCoordinator(runtime).restore(SnapshotDescriptor(
                revision: form.revision,
                key: form.key,
                checksum: form.checksum,
                createdAt: .distantPast
            ))
            return redirectToAdmin(req, message: "Restored revision \(form.revision)")
        }

        // The callback is state-protected and cannot depend on the browser retaining Basic auth.
        root.get("broadcast", "linkedin", "callback") { req async throws -> Response in
            let query = try req.query.decode(LinkedInCallbackQuery.self)
            if let error = query.error { throw Abort(.unauthorized, reason: error) }
            guard let code = query.code, let state = query.state else {
                throw Abort(.badRequest, reason: "LinkedIn callback is missing code or state")
            }
            let coordinator = try requireCoordinator(runtime)
            let providerID = try await coordinator.consumeOAuthState(state)
            let token = try await runtime.linkedinOAuthClient(providerID: providerID)
                .exchange(code: code, redirectURI: try linkedinCallbackURL())
            try await coordinator.saveConnection(token.connection, providerID: providerID)
            return req.redirect(to: "/_admin/broadcast?message=LinkedIn%20connected")
        }
    }
}

private struct DeliveryForm: Content { let csrfToken: String; let postID: String; let providerID: String }
private struct ProviderForm: Content { let csrfToken: String; let providerID: String }
private struct RestoreForm: Content { let csrfToken: String; let revision: UInt64; let key: String; let checksum: String }
private struct DeliveryQuery: Content { let postID: String; let providerID: String }
private struct LinkedInCallbackQuery: Content { let code: String?; let state: String?; let error: String? }

private func broadcastPage(req: Request, runtime: BroadcastRuntime) async throws -> Response {
    let csrf = req.cookies[AdminCSRFMiddleware.cookieName]?.string ?? UUID().uuidString
    var response: Response
    guard let coordinator = runtime.coordinator else {
        response = htmlResponse("<h1>Post Broadcaster</h1><p class=\"error\">\(escape(runtime.startupError ?? "Unavailable"))</p>")
        setCSRFCookie(csrf, on: &response, secure: req.application.environment == .production)
        return response
    }

    let posts = try runtime.currentPosts()
    await coordinator.observe(posts)
    let status = await coordinator.status()
    let ledger = await coordinator.ledgerSnapshot()
    let snapshots = (try? await coordinator.availableSnapshots()) ?? []
    let queryMessage = try? req.query.get(String.self, at: "message")

    var body = "<h1>Post Broadcaster</h1>"
    if let queryMessage { body += "<p class=\"notice\">\(escape(queryMessage))</p>" }
    let stateLabel = runtime.configuration.state.type == "r2" ? "R2" : "Local"
    body += "<p>\(escape(statusText(status, stateLabel: stateLabel)))</p>"
    body += "<p>Automatic delivery: <strong>\(runtime.configuration.enabled ? "enabled" : "disabled")</strong></p>"

    if ledger == nil, case .uninitialized = status.health {
        body += form(action: "/_admin/broadcast/initialize", csrf: csrf, button: "Initialize observed-post baseline")
    } else if ledger != nil {
        body += "<h2>Providers</h2><ul>"
        for provider in runtime.configuration.providers {
            let connection = await coordinator.connection(providerID: provider.id)
            let detail: String
            if provider.type == .linkedin {
                if let connection {
                    detail = connection.isExpired ? "expired" : "connected until \(format(connection.expiresAt))"
                } else { detail = "not connected" }
            } else { detail = "configured" }
            body += "<li><strong>\(escape(provider.id))</strong>: \(escape(detail)) "
            body += providerForm(action: "/_admin/broadcast/check", csrf: csrf, providerID: provider.id, button: "Test")
            if provider.type == .linkedin {
                body += providerForm(action: "/_admin/broadcast/linkedin/connect", csrf: csrf,
                                     providerID: provider.id, button: "Connect")
            }
            body += "</li>"
        }
        body += "</ul><h2>Posts</h2>"
        for post in posts.sorted(by: { $0.publicationDate > $1.publicationDate }).prefix(50) {
            body += "<section><h3>\(escape(post.title ?? post.url.absoluteString))</h3>"
            if !post.isSupported { body += "<p>Micropost: unsupported in v1</p>" }
            if let state = ledger?.posts[post.identifier] {
                body += "<ul>"
                for provider in runtime.configuration.providers {
                    let delivery = state.deliveries[provider.id]
                    body += "<li>\(escape(provider.id)): <strong>\(delivery?.status.rawValue ?? "missing")</strong>"
                    if let delivery {
                        body += " — attempts \(delivery.attemptCount), updated \(escape(format(delivery.updatedAt)))"
                        if let externalURL = delivery.externalURL {
                            body += " — <a href=\"\(escape(externalURL.absoluteString))\">external post</a>"
                        } else if let externalID = delivery.externalID {
                            body += " — receipt <code>\(escape(externalID))</code>"
                        }
                    }
                    if let error = delivery?.lastError { body += " — \(escape(error))" }
                    if post.isSupported {
                        body += " <a href=\"/_admin/broadcast/preview?postID=\(urlEncode(post.identifier))&providerID=\(urlEncode(provider.id))\">Preview</a>"
                        switch delivery?.status {
                        case .observed, .skipped:
                            body += deliveryForm(action: "/_admin/broadcast/backfill", csrf: csrf, postID: post.identifier,
                                                 providerID: provider.id, button: "Backfill")
                        case .failed:
                            body += deliveryForm(action: "/_admin/broadcast/retry", csrf: csrf, postID: post.identifier,
                                                 providerID: provider.id, button: "Retry")
                        case .ambiguous, .delivered:
                            body += deliveryForm(action: "/_admin/broadcast/explicitly-queue", csrf: csrf,
                                                 postID: post.identifier, providerID: provider.id,
                                                 button: delivery?.status == .ambiguous ? "Retry despite duplicate risk" : "Rebroadcast")
                        default: break
                        }
                    }
                    body += "</li>"
                }
                body += "</ul>"
            }
            body += "</section>"
        }
    }

    body += "<h2>\(stateLabel) snapshots</h2><p>Revision \(status.revision.map(String.init) ?? "none")</p><ul>"
    for snapshot in snapshots.prefix(20) {
        body += "<li>Revision \(snapshot.revision)"
        if snapshot.revision != status.revision { body += restoreForm(snapshot: snapshot, csrf: csrf) }
        body += "</li>"
    }
    body += "</ul>"

    response = htmlResponse(body)
    setCSRFCookie(csrf, on: &response, secure: req.application.environment == .production)
    return response
}

private struct AdminHTTPSMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if request.application.environment != .production {
            return try await next.respond(to: request)
        }
        let forwardedScheme = request.headers.first(name: "X-Forwarded-Proto")?
            .split(separator: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.url.scheme?.lowercased() == "https" || forwardedScheme?.lowercased() == "https" else {
            throw Abort(.upgradeRequired, reason: "Maverick admin requires HTTPS")
        }
        return try await next.respond(to: request)
    }
}

private struct AdminBasicAuthMiddleware: AsyncMiddleware {
    let runtime: BroadcastRuntime
    let limiter = AdminLoginLimiter()

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let address = runtime.configuration.admin.trustForwardedClientIP
            ? request.peerAddress
            : request.remoteAddress
        // Never include the ephemeral source port in the limiter identity.
        let client = address?.ipAddress ?? "unknown"
        guard await limiter.canAttempt(client: client) else {
            throw Abort(.tooManyRequests, reason: "Too many admin authentication failures")
        }
        do {
            let username = try runtime.secrets.resolve(runtime.configuration.admin.usernameSecret)
            let password = try runtime.secrets.resolve(runtime.configuration.admin.passwordSecret)
            guard let basic = request.headers.basicAuthorization,
                  constantTimeEqual(basic.username, username),
                  constantTimeEqual(basic.password, password) else {
                await limiter.recordFailure(client: client)
                let response = Response(status: .unauthorized)
                response.headers.replaceOrAdd(name: .wwwAuthenticate, value: "Basic realm=\"Maverick Admin\"")
                return response
            }
            await limiter.recordSuccess(client: client)
            return try await next.respond(to: request)
        } catch let error as AbortError {
            throw error
        } catch {
            throw Abort(.serviceUnavailable, reason: "Admin credentials are unavailable")
        }
    }
}

private actor AdminLoginLimiter {
    struct Failure: Sendable { var count: Int; var firstFailure: Date }
    private var failures: [String: Failure] = [:]

    func canAttempt(client: String) -> Bool {
        guard let failure = failures[client] else { return true }
        if Date().timeIntervalSince(failure.firstFailure) > 300 { failures[client] = nil; return true }
        return failure.count < 10
    }
    func recordFailure(client: String) {
        if var failure = failures[client], Date().timeIntervalSince(failure.firstFailure) <= 300 {
            failure.count += 1; failures[client] = failure
        } else { failures[client] = Failure(count: 1, firstFailure: Date()) }
    }
    func recordSuccess(client: String) { failures[client] = nil }
}

private struct AdminCSRFMiddleware: AsyncMiddleware {
    static let cookieName = "maverick-admin-csrf"
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if request.method == .POST {
            guard let cookie = request.cookies[Self.cookieName]?.string,
                  let body = try? request.content.decode(CSRFForm.self),
                  constantTimeEqual(cookie, body.csrfToken) else {
                throw Abort(.forbidden, reason: "Invalid CSRF token")
            }
        }
        return try await next.respond(to: request)
    }
}

private struct CSRFForm: Content { let csrfToken: String }

private func requireCoordinator(_ runtime: BroadcastRuntime) throws -> Coordinator {
    guard let coordinator = runtime.coordinator else {
        throw Abort(.serviceUnavailable, reason: runtime.startupError ?? "Broadcaster unavailable")
    }
    return coordinator
}

private func linkedinCallbackURL() throws -> URL {
    try SiteConfigController.fetchSite().url
        .appendingPathComponent("_admin")
        .appendingPathComponent("broadcast")
        .appendingPathComponent("linkedin")
        .appendingPathComponent("callback")
}

private func statusText(_ status: CoordinatorStatus, stateLabel: String) -> String {
    switch status.health {
    case .disabled: return "Disabled"
    case .uninitialized: return "\(stateLabel) state is uninitialized"
    case .ready: return "\(stateLabel) state is healthy at revision \(status.revision.map(String.init) ?? "0")"
    case .unavailable(let message): return "Broadcasting unavailable: \(message)"
    }
}

private func redirectToAdmin(_ req: Request, message: String? = nil) -> Response {
    let suffix = message.map { "?message=\(urlEncode($0))" } ?? ""
    return req.redirect(to: "/_admin/broadcast\(suffix)")
}

private func htmlResponse(_ body: String) -> Response {
    let page = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
    <title>Maverick Admin</title><style>
    body{font:16px system-ui;max-width:70rem;margin:2rem auto;padding:0 1rem;line-height:1.45}
    section{border-top:1px solid #ddd;padding:1rem 0}form{display:inline;margin-left:.5rem}
    button{margin:.25rem}.error{color:#b00020}.notice{background:#eef8ee;padding:.75rem}pre{white-space:pre-wrap}
    </style></head><body>\(body)</body></html>
    """
    var headers = HTTPHeaders(); headers.contentType = .html
    return Response(status: .ok, headers: headers, body: .init(string: page))
}

private func setCSRFCookie(_ value: String, on response: inout Response, secure: Bool) {
    response.cookies[AdminCSRFMiddleware.cookieName] = .init(
        string: value, maxAge: 3_600, path: "/_admin", isSecure: secure, isHTTPOnly: true, sameSite: .strict
    )
}

private func form(action: String, csrf: String, button: String) -> String {
    formFields(action: action, csrf: csrf, fields: [:], button: button)
}
private func providerForm(action: String, csrf: String, providerID: String, button: String) -> String {
    formFields(action: action, csrf: csrf, fields: ["providerID": providerID], button: button)
}
private func deliveryForm(action: String, csrf: String, postID: String, providerID: String, button: String) -> String {
    formFields(action: action, csrf: csrf, fields: ["postID": postID, "providerID": providerID], button: button)
}
private func restoreForm(snapshot: SnapshotDescriptor, csrf: String) -> String {
    formFields(action: "/_admin/broadcast/restore", csrf: csrf,
               fields: ["revision": String(snapshot.revision), "key": snapshot.key, "checksum": snapshot.checksum],
               button: "Restore")
}
private func formFields(action: String, csrf: String, fields: [String: String], button: String) -> String {
    let hidden = (["csrfToken": csrf].merging(fields) { _, new in new }).map { key, value in
        "<input type=\"hidden\" name=\"\(escape(key))\" value=\"\(escape(value))\">"
    }.joined()
    return "<form method=\"post\" action=\"\(action)\">\(hidden)<button>\(escape(button))</button></form>"
}

private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(SHA256.hash(data: Data(lhs.utf8)))
    let right = Array(SHA256.hash(data: Data(rhs.utf8)))
    var difference: UInt8 = 0
    for index in left.indices {
        difference |= left[index] ^ right[index]
    }
    return difference == 0
}
private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
private func urlEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}
private func format(_ date: Date?) -> String {
    date.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
}

struct AdminController {
    static func reloadActionTriggered() -> Bool {
        do {
            try shellOut(to: .gitPull(remote: "origin", branch: "master"), at: FileManager.default.currentDirectoryPath)
            return true
        } catch {
            print("git error: \(error)")
            return false
        }
    }
}
