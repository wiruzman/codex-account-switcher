import AppKit
import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

struct AuthFile: Decodable {
    struct Tokens: Decodable {
        let idToken: String?
        let accessToken: String?
        let refreshToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accountId = "account_id"
        }
    }

    let tokens: Tokens?
}

struct TokenRefreshRequest: Encodable {
    let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    let grantType = "refresh_token"
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}

struct TokenRefreshResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct LimitWindowResponse: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}

struct RateLimitResponse: Decodable {
    let primaryWindow: LimitWindowResponse?
    let secondaryWindow: LimitWindowResponse?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct AdditionalRateLimitResponse: Decodable {
    let limitName: String?
    let rateLimit: RateLimitResponse?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case rateLimit = "rate_limit"
    }
}

struct UsageResponse: Decodable {
    let rateLimit: RateLimitResponse?
    let additionalRateLimits: [AdditionalRateLimitResponse]?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }
}

struct UsageWindowSnapshot: Codable {
    // Named windows come from `additional_rate_limits`; the main allowance has
    // no name and is labelled from its duration in the menu.
    let label: String?
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Double?
    let windowSeconds: Double?

    func resetElapsedPercent(at date: Date = Date()) -> Double? {
        guard let resetAt, resetAt.isFinite,
              let windowSeconds, windowSeconds.isFinite, windowSeconds > 0 else { return nil }
        let remaining = resetAt - date.timeIntervalSince1970
        return min(max(1 - remaining / windowSeconds, 0), 1) * 100
    }
}

struct UsageSnapshot: Codable {
    let fetchedAt: Date
    let primary: UsageWindowSnapshot?
    let secondary: UsageWindowSnapshot?
    // Optional preserves compatibility with usage caches written by older app versions.
    let additional: [UsageWindowSnapshot]?
    let error: String?

    var windows: [UsageWindowSnapshot] {
        [primary, secondary].compactMap { $0 } + (additional ?? [])
    }
}

private struct UsageBarRow {
    let title: String
    let usedPercent: Double?
    let resetPercent: Double?
    let resetText: String
}

private final class PlainTextButton: NSButton {
    private let textColor: NSColor

    init(title: String, frame: NSRect, textColor: NSColor, target: AnyObject?, action: Selector?) {
        self.textColor = textColor
        super.init(frame: frame)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: textColor
        ]
        (title as NSString).draw(
            with: bounds,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }
}

// Draw the account styling while NSMenu owns submenu tracking and navigation.
private final class AccountSubmenuCell: NSCell {
    var activeProfile = ""

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: cellFrame, xRadius: 4, yRadius: 4).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let name = activeProfile.isEmpty ? "Accounts" : activeProfile
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let nameHeight = NSAttributedString(string: name, attributes: nameAttributes).size().height
        (name as NSString).draw(
            in: NSRect(x: cellFrame.minX + 10, y: cellFrame.midY - nameHeight / 2,
                       width: cellFrame.width - (activeProfile.isEmpty ? 40 : 86), height: nameHeight),
            withAttributes: nameAttributes
        )

        if !activeProfile.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85)
            ]
            let size = NSAttributedString(string: "Active", attributes: attributes).size()
            ("Active" as NSString).draw(
                at: NSPoint(x: cellFrame.maxX - 32 - size.width, y: cellFrame.midY - size.height / 2),
                withAttributes: attributes
            )
        }

        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            let tinted = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            tinted.draw(in: NSRect(x: cellFrame.maxX - 24, y: cellFrame.midY - 6, width: 12, height: 12))
        }
    }
}

private final class AccountSubmenuView: NSView {
    private let accountCell: AccountSubmenuCell

    override var isFlipped: Bool { true }

    init(activeProfile: String) {
        accountCell = AccountSubmenuCell(textCell: activeProfile.isEmpty ? "Accounts" : activeProfile)
        accountCell.activeProfile = activeProfile
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 66))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("Accounts")
        setAccessibilityValue(activeProfile.isEmpty ? "No active account" : activeProfile)
        setAccessibilityHelp("Open the accounts submenu")
    }

    required init?(coder: NSCoder) { nil }

    // The native menu handles hover, clicks and keyboard navigation for this row.
    override func draw(_ dirtyRect: NSRect) {
        accountCell.draw(withFrame: NSRect(x: 16, y: 16, width: bounds.width - 32, height: 40), in: self)
    }
}

// Menu items retain their native title/action for keyboard navigation and type-select.
// The view supplies wrapped usage details and a full-width pointer target.
private final class AccountMenuItemView: NSView {
    private static let horizontalPadding: CGFloat = 16
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(title: String, details: [String] = [], symbol: String? = nil) {
        let width: CGFloat = 248
        let textX = Self.horizontalPadding + (symbol == nil ? 0 : 24)
        let textWidth = width - textX - Self.horizontalPadding
        let detailFont = NSFont.systemFont(ofSize: 11)
        var height: CGFloat = details.isEmpty ? 36 : 28
        let detailHeights = details.map { detail -> CGFloat in
            let rect = (detail as NSString).boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: detailFont]
            )
            return ceil(rect.height)
        }
        height += detailHeights.reduce(0) { $0 + $1 + 2 }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: details.isEmpty ? 12 : 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: textX, y: details.isEmpty ? 9 : 6, width: textWidth, height: 18)
        label.autoresizingMask = [.width]
        label.setAccessibilityElement(false)
        addSubview(label)

        var y: CGFloat = 27
        for (index, detail) in details.enumerated() {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.font = detailFont
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: textX, y: y, width: textWidth, height: detailHeights[index])
            label.autoresizingMask = [.width]
            label.setAccessibilityElement(false)
            addSubview(label)
            y += detailHeights[index] + 2
        }

        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(frame: NSRect(x: Self.horizontalPadding, y: (height - 16) / 2, width: 16, height: 16))
            icon.image = image
            icon.contentTintColor = .labelColor
            icon.setAccessibilityElement(false)
            addSubview(icon)
        }
        toolTip = ([title] + details).joined(separator: "\n")
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
        setAccessibilityValue(details.joined(separator: ", "))
    }

    required init?(coder: NSCoder) { nil }

    // Labels are display-only; the entire row handles the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || enclosingMenuItem?.isHighlighted == true {
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }

    override func accessibilityPerformPress() -> Bool { activate() }

    @discardableResult private func activate() -> Bool {
        guard let item = enclosingMenuItem, item.isEnabled, let action = item.action else { return false }
        var rootMenu = item.menu
        while let parent = rootMenu?.supermenu { rootMenu = parent }
        rootMenu?.cancelTracking()
        // Let native menu tracking end before showing a switch/capture alert.
        DispatchQueue.main.async { NSApp.sendAction(action, to: item.target, from: item) }
        return true
    }
}

private final class UsageBarsMenuView: NSView {
    private static let menuWidth: CGFloat = 280
    private static let horizontalPadding: CGFloat = 16
    private static let topPadding: CGFloat = 0
    private static let rowHeight: CGFloat = 58
    private static let footerHeight: CGFloat = 18
    private static let barHeight: CGFloat = 6
    private static let labelGap: CGFloat = 8
    private static let refreshTitle = "Refresh now"
    private static let footerGap: CGFloat = 4

    private let rows: [UsageBarRow]
    private let updatedText: String

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: Self.menuWidth,
            height: Self.topPadding + CGFloat(rows.count) * Self.rowHeight + Self.footerHeight
        )
    }

    init(rows: [UsageBarRow], updatedText: String, target: AnyObject?, refreshAction: Selector) {
        self.rows = rows
        self.updatedText = updatedText
        let initialSize = NSSize(
            width: Self.menuWidth,
            height: Self.topPadding + CGFloat(rows.count) * Self.rowHeight + Self.footerHeight
        )
        super.init(frame: NSRect(origin: .zero, size: initialSize))

        let footerFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let updatedWidth = Self.updatedTextWidth(updatedText, font: footerFont)
        let refreshWidth = Self.textWidth(Self.refreshTitle, font: footerFont)
        let refreshButton = PlainTextButton(
            title: Self.refreshTitle,
            frame: NSRect(
                x: Self.horizontalPadding + updatedWidth + Self.footerGap,
                y: Self.topPadding + CGFloat(rows.count) * Self.rowHeight + 3,
                width: refreshWidth + 2,
                height: 14
            ),
            textColor: .labelColor,
            target: target,
            action: refreshAction
        )
        refreshButton.font = footerFont
        addSubview(refreshButton)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let titleAttributes = textAttributes(
            font: .systemFont(ofSize: 12, weight: .medium),
            color: .labelColor
        )
        let valueFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueAttributes = textAttributes(
            font: valueFont,
            color: .labelColor.withAlphaComponent(0.65),
            alignment: .right
        )
        let footerAttributes = textAttributes(
            font: .systemFont(ofSize: 10, weight: .medium),
            color: .labelColor.withAlphaComponent(0.45)
        )
        let fillColor = NSColor(calibratedRed: 252 / 255, green: 121 / 255, blue: 32 / 255, alpha: 1)
        let contentWidth = bounds.width - Self.horizontalPadding * 2
        let labelWidth = min(rows.flatMap { row in
            [Self.textWidth("\(formatPercent(row.usedPercent)) used", font: valueFont),
             Self.textWidth(row.resetText, font: valueFont)]
        }.max() ?? 0, contentWidth / 2)
        let barWidth = contentWidth - Self.labelGap - labelWidth
        let labelX = Self.horizontalPadding + barWidth + Self.labelGap

        for (index, row) in rows.enumerated() {
            let y = Self.topPadding + CGFloat(index) * Self.rowHeight
            drawText(row.title, in: NSRect(x: Self.horizontalPadding, y: y, width: contentWidth, height: 18), attributes: titleAttributes)

            let textY = y + 20
            drawBar(row.usedPercent, in: NSRect(x: Self.horizontalPadding, y: textY + 4, width: barWidth, height: Self.barHeight), color: fillColor)
            drawText(
                "\(formatPercent(row.usedPercent)) used",
                in: NSRect(x: labelX, y: textY, width: labelWidth, height: 14),
                attributes: valueAttributes
            )
            drawBar(row.resetPercent, in: NSRect(x: Self.horizontalPadding, y: textY + 20, width: barWidth, height: Self.barHeight), color: fillColor)
            drawText(
                row.resetText,
                in: NSRect(x: labelX, y: textY + 16, width: labelWidth, height: 14),
                attributes: valueAttributes
            )
        }

        let footerY = Self.topPadding + CGFloat(rows.count) * Self.rowHeight
        let footerFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        drawText(
            updatedText,
            in: NSRect(
                x: Self.horizontalPadding,
                y: footerY + 3,
                width: Self.updatedTextWidth(updatedText, font: footerFont),
                height: 16
            ),
            attributes: footerAttributes
        )
    }

    private func drawBar(_ value: Double?, in trackRect: NSRect, color: NSColor) {
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: Self.barHeight / 2, yRadius: Self.barHeight / 2).fill()

        let percent = clampedPercent(value)
        guard percent > 0 else { return }
        let fillWidth = max(Self.barHeight, trackRect.width * CGFloat(percent / 100))
        let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: min(fillWidth, trackRect.width), height: trackRect.height)
        color.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: Self.barHeight / 2, yRadius: Self.barHeight / 2).fill()
    }

    private static func updatedTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let availableWidth = menuWidth - horizontalPadding * 2 - footerGap - textWidth(refreshTitle, font: font)
        return min(textWidth(text, font: font), availableWidth)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func clampedPercent(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        return "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    private func textAttributes(font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func drawText(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }
}

final class UsageFetcher {
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!

    private enum UsageFetchResult {
        case success(UsageSnapshot)
        case unauthorized(Data?)
        case failure(String)
    }

    private enum TokenRefreshResult {
        case success(TokenRefreshResponse)
        case failure(String)
    }

    // A dedicated session that never stores or sends cookies and bypasses the
    // HTTP cache. The usage endpoint sits behind Cloudflare and hands out a
    // `__cflb` load-balancer cookie; persisting it (as URLSession.shared does)
    // pins every refresh to one backend node that can report a stale usage
    // percentage. Staying cookie-less keeps us in sync with the Codex CLI.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    func fetch(authURL: URL, completion: @escaping (UsageSnapshot) -> Void) {
        guard let auth = readAuth(authURL), auth.tokens?.accessToken != nil else {
            completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: "No Codex auth token"))
            return
        }

        fetchUsage(auth: auth) { result in
            switch result {
            case .success(let snapshot):
                completion(snapshot)
            case .failure(let message):
                completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: message))
            case .unauthorized(let body):
                self.refreshAndRetry(authURL: authURL, auth: auth, unauthorizedBody: body, completion: completion)
            }
        }
    }

    private func refreshAndRetry(
        authURL: URL,
        auth: AuthFile,
        unauthorizedBody: Data?,
        completion: @escaping (UsageSnapshot) -> Void
    ) {
        guard let refreshToken = auth.tokens?.refreshToken, !refreshToken.isEmpty else {
            let message = Self.errorMessage(status: 401, body: unauthorizedBody)
            completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: message))
            return
        }

        refreshTokens(refreshToken: refreshToken) { result in
            switch result {
            case .failure(let message):
                completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: message))
            case .success(let refreshed):
                do {
                    try self.persist(refresh: refreshed, authURL: authURL)
                } catch {
                    completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: "Could not save refreshed token"))
                    return
                }

                guard let refreshedAuth = self.readAuth(authURL) else {
                    completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: "Could not read refreshed token"))
                    return
                }

                self.fetchUsage(auth: refreshedAuth) { retryResult in
                    switch retryResult {
                    case .success(let snapshot):
                        completion(snapshot)
                    case .failure(let message):
                        completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: message))
                    case .unauthorized(let body):
                        let message = Self.errorMessage(status: 401, body: body)
                        completion(UsageSnapshot(fetchedAt: Date(), primary: nil, secondary: nil, additional: nil, error: message))
                    }
                }
            }
        }
    }

    private func fetchUsage(auth: AuthFile, completion: @escaping (UsageFetchResult) -> Void) {
        guard let accessToken = auth.tokens?.accessToken else {
            completion(.failure("No Codex auth token"))
            return
        }

        var request = URLRequest(url: usageRequestURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex_desktop", forHTTPHeaderField: "originator")
        request.setValue("Codex Desktop/0.0 (Macintosh; Intel Mac OS X; arm64)", forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "OAI-Language")

        if let accountId = auth.tokens?.accountId ?? accountIdFromJWT(accessToken) {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error.localizedDescription))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure("Invalid usage response"))
                return
            }

            if http.statusCode == 401 {
                completion(.unauthorized(data))
                return
            }

            guard http.statusCode == 200, let data else {
                let message = Self.errorMessage(status: http.statusCode, body: data)
                completion(.failure(message))
                return
            }

            do {
                let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
                let primary = self.snapshot(from: usage.rateLimit?.primaryWindow)
                let secondary = self.snapshot(from: usage.rateLimit?.secondaryWindow)
                let additional = (usage.additionalRateLimits ?? []).flatMap { limit in
                    [
                        self.snapshot(from: limit.rateLimit?.primaryWindow, label: limit.limitName),
                        self.snapshot(from: limit.rateLimit?.secondaryWindow, label: limit.limitName)
                    ].compactMap { $0 }
                }
                completion(.success(UsageSnapshot(
                    fetchedAt: Date(),
                    primary: primary,
                    secondary: secondary,
                    additional: additional,
                    error: nil
                )))
            } catch {
                completion(.failure("Could not parse usage"))
            }
        }.resume()
    }

    private func usageRequestURL() -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "_cas_nocache", value: UUID().uuidString)
        ]
        return components.url ?? endpoint
    }

    private func refreshTokens(
        refreshToken: String,
        completion: @escaping (TokenRefreshResult) -> Void
    ) {
        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("codex_desktop", forHTTPHeaderField: "originator")
        request.setValue("Codex Desktop/0.0 (Macintosh; Intel Mac OS X; arm64)", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try JSONEncoder().encode(TokenRefreshRequest(refreshToken: refreshToken))
        } catch {
            completion(.failure("Could not refresh token"))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error.localizedDescription))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure("Invalid token refresh response"))
                return
            }

            guard http.statusCode >= 200, http.statusCode < 300, let data else {
                completion(.failure(Self.refreshErrorMessage(status: http.statusCode, body: data)))
                return
            }

            do {
                let refreshed = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
                guard refreshed.accessToken != nil else {
                    completion(.failure("Token refresh returned no access token"))
                    return
                }
                completion(.success(refreshed))
            } catch {
                completion(.failure("Could not parse token refresh"))
            }
        }.resume()
    }

    private func persist(refresh: TokenRefreshResponse, authURL: URL) throws {
        let data = try Data(contentsOf: authURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexAccountSwitcher", code: 1)
        }

        var tokens = root["tokens"] as? [String: Any] ?? [:]
        if let idToken = refresh.idToken {
            tokens["id_token"] = idToken
        }
        if let accessToken = refresh.accessToken {
            tokens["access_token"] = accessToken
            if tokens["account_id"] == nil, let accountId = accountIdFromJWT(accessToken) {
                tokens["account_id"] = accountId
            }
        }
        if let refreshToken = refresh.refreshToken {
            tokens["refresh_token"] = refreshToken
        }

        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: authURL, options: .atomic)
    }

    private func readAuth(_ url: URL) -> AuthFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AuthFile.self, from: data)
    }

    // Turns a non-200 usage response into a message the user can act on.
    private static func errorMessage(status: Int, body: Data?) -> String {
        let code = bodyErrorCode(body)
        switch status {
        case 401:
            if code == "refresh_token_invalidated" {
                return "Session ended - sign in to Codex again"
            }
            return "Sign in to Codex again"
        case 403:
            return "Account has no Codex access"
        case 429:
            return "Rate limited — try again later"
        default:
            return "HTTP \(status)"
        }
    }

    private static func refreshErrorMessage(status: Int, body: Data?) -> String {
        let code = bodyErrorCode(body)
        if status == 401 {
            switch code {
            case "refresh_token_expired":
                return "Session expired - sign in to Codex again"
            case "refresh_token_reused", "refresh_token_invalidated":
                return "Session ended - sign in to Codex again"
            default:
                return "Could not refresh session - sign in to Codex again"
            }
        }
        if let code {
            return "Token refresh failed: \(code)"
        }
        return "Token refresh failed: HTTP \(status)"
    }

    private static func bodyErrorCode(_ body: Data?) -> String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            return error["code"] as? String
        }
        if let error = json["error"] as? String {
            return error
        }
        return json["code"] as? String
    }

    private func snapshot(from window: LimitWindowResponse?, label: String? = nil) -> UsageWindowSnapshot? {
        guard let window else { return nil }
        let used = window.usedPercent ?? 0
        let remaining = min(max(100 - used, 0), 100)
        return UsageWindowSnapshot(
            label: label,
            usedPercent: used,
            remainingPercent: remaining,
            resetAt: window.resetAt,
            windowSeconds: window.limitWindowSeconds
        )
    }

    private func accountIdFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String else {
            return nil
        }
        return accountId
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let scriptPath: String
    private let usageFetcher = UsageFetcher()
    private var usageByProfile: [String: UsageSnapshot] = [:]
    private var usageTimer: Timer?
    private var isRefreshingUsage = false

    private var switcherHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexAccountSwitcher")
    }

    private var usageCacheURL: URL {
        switcherHome.appendingPathComponent("usage-cache.json")
    }

    private var codexAuthURL: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_AUTH_FILE"],
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    override init() {
        if let bundled = Bundle.main.path(forResource: "codex-account-switcher", ofType: "sh") {
            scriptPath = bundled
        } else {
            scriptPath = FileManager.default.currentDirectoryPath + "/codex-account-switcher.sh"
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAnotherInstanceIsRunning() else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemIcon()
        loadUsageCache()
        rebuildMenu()
        refreshUsage()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func terminateIfAnotherInstanceIsRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let currentProcessId = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessId }

        guard !otherInstances.isEmpty else { return false }

        NSApplication.shared.terminate(nil)
        return true
    }

    @objc private func rebuildMenu() {
        let active = activeProfile()
        statusItem.menu = makeMenu(profiles: profileNames(), activeProfile: active)
        updateStatusBarTitle(activeProfile: active)
    }

    private func makeMenu(profiles: [String], activeProfile: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let selectorItem = NSMenuItem(title: activeProfile.isEmpty ? "Accounts" : activeProfile, action: nil, keyEquivalent: "")
        selectorItem.submenu = accountsSubmenu(profiles: profiles, activeProfile: activeProfile)
        selectorItem.view = AccountSubmenuView(activeProfile: activeProfile)
        menu.addItem(selectorItem)

        if !activeProfile.isEmpty {
            addUsageItems(to: menu, snapshot: usageByProfile[activeProfile])
        }

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "About", action: #selector(showAbout)))
        menu.addItem(makeItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = [.command]
        }
        return item
    }

    private func accountsSubmenu(profiles: [String], activeProfile: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 248
        let alternatives = profiles.filter { $0 != activeProfile }
        for profile in alternatives {
            let details = accountUsageDetails(profile)
            let item = NSMenuItem(title: profile, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            item.view = AccountMenuItemView(title: profile, details: details)
            menu.addItem(item)
        }

        if !alternatives.isEmpty { menu.addItem(.separator()) }
        let addItem = makeItem(title: "Add account", action: #selector(captureCurrent))
        addItem.view = AccountMenuItemView(title: "Add account", symbol: "plus")
        menu.addItem(addItem)
        return menu
    }

    private func configureStatusItemIcon() {
        guard let button = statusItem.button else { return }
        if let image = statusIcon(size: 18) {
            button.image = image
            button.imagePosition = .imageLeft
            button.title = ""
            button.toolTip = "Codex Account Switcher"
        } else {
            button.title = "Codex"
        }
    }

    private func statusIcon(size: CGFloat) -> NSImage? {
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: size, height: size)
            image.isTemplate = true
            return image
        }
        return nil
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        confirmSwitch(to: profile)
    }

    private func confirmSwitch(to profile: String) {
        statusItem.menu?.cancelTracking()

        guard profile != activeProfile() else { return }
        let alert = NSAlert()
        alert.messageText = "Switch to \(profile)?"
        alert.informativeText = "Codex will quit, the saved account state will be restored, and Codex will reopen."
        alert.addButton(withTitle: "Switch")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(["switch", profile])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.showError(result.output)
                }
                self.rebuildMenu()
                self.refreshUsage()
            }
        }
    }

    @objc private func captureCurrent() {
        statusItem.menu?.cancelTracking()

        let alert = NSAlert()
        alert.messageText = "Capture Current Codex Account"
        alert.informativeText = "Codex will quit first so its login state is fully written. Use a short profile name, such as personal or work."
        alert.addButton(withTitle: "Capture")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "profile-name"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let profile = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(["capture", profile])
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.showError(result.output)
                }
                self.rebuildMenu()
                self.refreshUsage()
            }
        }
    }

    @objc private func refreshNow() {
        statusItem.menu?.cancelTracking()
        rebuildMenu()
        refreshUsage()
    }

    @objc private func openProfilesFolder() {
        statusItem.menu?.cancelTracking()
        _ = run(["open-folder"])
    }

    @objc private func showAbout() {
        statusItem.menu?.cancelTracking()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let description = NSAttributedString(
            string: "A local-first macOS menu bar app for switching between Codex accounts.\n\nSaved account profiles stay on your Mac.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Codex Account Switcher",
            .credits: description
        ])
    }

    @objc private func openCodex() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func run(_ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(status: process.terminationStatus, output: output)
    }

    private func profileNames() -> [String] {
        run(["list", "--plain"]).output
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private func activeProfile() -> String {
        run(["active"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func profileAuthURL(profile: String) -> URL {
        switcherHome
            .appendingPathComponent("profiles")
            .appendingPathComponent(profile)
            .appendingPathComponent("auth/auth.json")
    }

    private func usageAuthURL(profile: String, activeProfile: String) -> URL {
        // Codex rotates refresh tokens in its live auth file. The saved copy for
        // the active profile is only updated when switching away, so polling it
        // can reuse an old refresh token and incorrectly report an ended session.
        profile == activeProfile ? codexAuthURL : profileAuthURL(profile: profile)
    }

    private func refreshUsage() {
        guard !isRefreshingUsage else { return }

        let profiles = profileNames()
        guard !profiles.isEmpty else {
            usageByProfile.removeAll()
            saveUsageCache()
            rebuildMenu()
            return
        }

        isRefreshingUsage = true
        rebuildMenu()

        let group = DispatchGroup()
        var updated: [String: UsageSnapshot] = [:]
        let lock = NSLock()
        let active = activeProfile()

        for profile in profiles {
            group.enter()
            let authURL = usageAuthURL(profile: profile, activeProfile: active)
            usageFetcher.fetch(authURL: authURL) { snapshot in
                lock.lock()
                updated[profile] = snapshot
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.usageByProfile = updated
            self.isRefreshingUsage = false
            self.saveUsageCache()
            self.rebuildMenu()
        }
    }

    private func loadUsageCache() {
        guard let data = try? Data(contentsOf: usageCacheURL),
              let decoded = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data) else {
            return
        }
        usageByProfile = decoded
    }

    private func saveUsageCache() {
        do {
            try FileManager.default.createDirectory(at: switcherHome, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(usageByProfile)
            try data.write(to: usageCacheURL, options: .atomic)
        } catch {
            // The menu can still work without a persisted usage cache.
        }
    }

    private func accountUsageDetails(_ profile: String) -> [String] {
        guard let snapshot = usageByProfile[profile] else { return ["Usage not loaded"] }
        if let error = snapshot.error { return [error] }
        guard !snapshot.windows.isEmpty else { return ["Usage unavailable"] }

        return snapshot.windows.map { window in
            let title: String
            if window.label == nil, let seconds = window.windowSeconds, seconds > 0, seconds < 86_400 {
                title = "Session"
            } else {
                title = usageTitle(for: window)
            }
            return "\(title): \(formatPercent(window.remainingPercent)) left · \(formatResetDistance(window.resetAt))"
        }
    }

    private func addUsageItems(to menu: NSMenu, snapshot: UsageSnapshot?) {
        guard let snapshot else {
            addDisabled("Usage: not loaded", to: menu)
            return
        }

        if let error = snapshot.error {
            addDisabled("Usage: \(error)", to: menu)
            addDisabled("Updated: \(formatDate(snapshot.fetchedAt))", to: menu)
            return
        }

        let windows = snapshot.windows
        guard !windows.isEmpty else {
            addDisabled("Usage: unavailable", to: menu)
            addDisabled("Updated: \(formatDate(snapshot.fetchedAt))", to: menu)
            return
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = UsageBarsMenuView(
            rows: windows.map { window in
                UsageBarRow(
                    title: usageTitle(for: window),
                    usedPercent: window.usedPercent,
                    resetPercent: window.resetElapsedPercent(),
                    resetText: formatResetDistance(window.resetAt)
                )
            },
            updatedText: "Updated \(formatDate(snapshot.fetchedAt))",
            target: self,
            refreshAction: #selector(refreshNow)
        )
        menu.addItem(item)
    }

    private func addDisabled(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func updateStatusBarTitle(activeProfile: String) {
        guard let button = statusItem.button else { return }

        if activeProfile.isEmpty {
            button.title = ""
            button.toolTip = "Codex Account Switcher"
            return
        }

        let snapshot = usageByProfile[activeProfile]
        let statusWindow = snapshot?.primary ?? snapshot?.windows.first
        button.title = " \(formatPercent(statusWindow?.remainingPercent))"

        if let snapshot, snapshot.error == nil {
            let parts = snapshot.windows.map { window in
                "\(usageTitle(for: window)) \(formatPercent(window.remainingPercent))"
            }
            button.toolTip = parts.isEmpty
                ? "\(activeProfile): usage unavailable"
                : "\(activeProfile): \(parts.joined(separator: ", "))"
        } else {
            button.toolTip = "\(activeProfile): usage unavailable"
        }
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func windowTitle(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "Usage" }
        let days = seconds / 86_400
        let hours = seconds / 3_600
        if days >= 28 { return "Monthly" }
        if days >= 6.5 { return "Weekly" }
        if days >= 1.5 { return "\(Int(days.rounded()))d" }
        if days >= 0.9 { return "Daily" }
        if hours >= 1 { return "\(Int(hours.rounded()))h" }
        let minutes = seconds / 60
        return "\(max(Int(minutes.rounded()), 1))m"
    }

    private func usageTitle(for window: UsageWindowSnapshot) -> String {
        let durationTitle = windowTitle(seconds: window.windowSeconds)
        guard let label = window.label, !label.isEmpty else { return durationTitle }
        return "\(label) · \(durationTitle)"
    }

    private func formatResetDistance(_ epochSeconds: Double?) -> String {
        guard let epochSeconds, epochSeconds.isFinite else { return "Reset unavailable" }

        let resetDate = Date(timeIntervalSince1970: epochSeconds)
        let seconds = Int(resetDate.timeIntervalSinceNow.rounded())
        guard seconds > 0 else { return "Resets soon" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h to reset" : "\(days)d to reset"
        }

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m to reset" : "\(hours)h to reset"
        }

        return "\(max(minutes, 1))m to reset"
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(timeFormatter.string(from: date))"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Codex Account Switcher"
        alert.informativeText = message.isEmpty ? "The command failed." : message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
