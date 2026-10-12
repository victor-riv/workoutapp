import Foundation

/// Minimal Gmail REST client (read-only). Auth comes from an injected token
/// provider so this stays testable without the GoogleSignIn SDK.
///
/// Only ever queries the coach's workout emails — see `coachSender`.
final class GmailService: Sendable {

    struct MessageSummary: Sendable {
        var id: String
        var subject: String
        var internalDate: Date?
        var snippet: String
    }

    struct FetchedMessage: Sendable {
        var id: String
        var subject: String
        var date: Date?
        var body: String
    }

    /// TrueCoach workout notification sender. The local part is the coach's
    /// TrueCoach handle (`swoletron`); the filter is deliberately narrow so
    /// the app never touches any other mail.
    static let coachSender = "swoletron@truecoach.co"

    private let tokenProvider: @Sendable () async throws -> String
    private let session: URLSession

    init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Workout emails from the coach, newest first.
    func listWorkoutMessages(maxResults: Int = 50) async throws -> [MessageSummary] {
        let token = try await tokenProvider()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: #"from:\#(Self.coachSender) "[TrueCoach]""#),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
        ]
        guard let url = components.url else { throw ImportError.invalidResponse }
        let list: MessageListResponse = try await get(url: url, token: token)

        // Fetch subjects/dates concurrently; one bad message must not
        // sink the whole list.
        let ids = list.messages?.map(\.id) ?? []
        return try await withThrowingTaskGroup(of: MessageSummary?.self) { group in
            for id in ids {
                group.addTask { try? await self.metadata(messageID: id, token: token) }
            }
            var out: [MessageSummary] = []
            for try await summary in group {
                if let summary { out.append(summary) }
            }
            return out.sorted { ($0.internalDate ?? .distantPast) > ($1.internalDate ?? .distantPast) }
        }
    }

    /// Full body of one message, preferring the text/plain MIME part.
    func fetchBody(messageID: String) async throws -> FetchedMessage {
        let token = try await tokenProvider()
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageID)"
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        guard let url = components.url else { throw ImportError.invalidResponse }
        let detail: MessageDetail = try await get(url: url, token: token)

        let headers = detail.payload?.headers ?? []
        func header(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let subject = header("Subject") ?? ""

        let body: String
        if let encoded = findPart(mimeType: "text/plain", in: detail.payload),
           let text = Self.decodeBase64URL(encoded) {
            body = text
        } else if let encoded = findPart(mimeType: "text/html", in: detail.payload),
                  let html = Self.decodeBase64URL(encoded) {
            // Fallback: TrueCoach sends multipart/alternative, so this path
            // should rarely trigger.
            body = Self.stripHTML(html)
        } else {
            throw ImportError.invalidResponse
        }

        return FetchedMessage(
            id: messageID,
            subject: subject,
            date: header("Date").flatMap(Self.parseEmailDate),
            body: body
        )
    }

    // MARK: - Private

    private func metadata(messageID: String, token: String) async throws -> MessageSummary {
        var components = URLComponents(
            string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageID)"
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        guard let url = components.url else { throw ImportError.invalidResponse }
        let detail: MessageDetail = try await get(url: url, token: token)
        let headers = detail.payload?.headers ?? []
        func header(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        return MessageSummary(
            id: messageID,
            subject: header("Subject") ?? "",
            internalDate: detail.internalDateMillis.map { Date(timeIntervalSince1970: $0 / 1000) },
            snippet: detail.snippet ?? ""
        )
    }

    private func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ImportError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ImportError.networkError("No HTTP response")
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            // Token expired/revoked or scope missing — send the user back
            // to Settings to reconnect.
            throw ImportError.notSignedIn
        default:
            throw ImportError.gmailError("Gmail API returned HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ImportError.invalidResponse
        }
    }

    /// Recursively find the encoded body of the first part with `mimeType`.
    private func findPart(mimeType: String, in payload: MessageDetail.Payload?) -> String? {
        guard let payload else { return nil }
        if payload.mimeType == mimeType,
           let data = payload.body?.data, !data.isEmpty {
            return data
        }
        for part in payload.parts ?? [] {
            if let found = findPart(mimeType: mimeType, in: part) { return found }
        }
        return nil
    }

    /// Gmail uses base64url without padding.
    static func decodeBase64URL(_ string: String) -> String? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Best-effort HTML → text for the fallback path.
    static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</(p|div|tr)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, replacement) in [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<",
            "&gt;": ">", "&quot;": "\"", "&#39;": "'",
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }

    /// "Sat, 10 Oct 2026 04:22:30 +0000"
    static func parseEmailDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string)
    }
}

// MARK: - Gmail JSON DTOs

private struct MessageListResponse: Decodable {
    var messages: [MessageRef]?
    var nextPageToken: String?

    struct MessageRef: Decodable {
        var id: String
    }
}

private struct MessageDetail: Decodable {
    var id: String
    var snippet: String?
    /// Milliseconds since epoch, encoded as a JSON string.
    var internalDate: String?
    var payload: Payload?

    var internalDateMillis: TimeInterval? {
        internalDate.flatMap(TimeInterval.init)
    }

    struct Payload: Decodable {
        var mimeType: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Payload]?

        struct Header: Decodable {
            var name: String
            var value: String
        }

        struct Body: Decodable {
            var data: String?
        }
    }
}
