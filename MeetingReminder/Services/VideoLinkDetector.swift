import AppKit
import EventKit
import Foundation

struct VideoLinkDetector {
    private static let patterns: [(name: String, pattern: String)] = [
        ("Zoom", #"https?://[\w.-]*zoom\.us/j/\S+"#),
        ("Google Meet", #"https?://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+\S*"#),
        ("Microsoft Teams", #"https?://teams\.microsoft\.com/l/meetup-join/\S+"#),
        ("Webex", #"https?://[\w.-]*webex\.com/\S+"#),
        ("Slack Huddle", #"https?://app\.slack\.com/huddle/\S+"#),
    ]

    static func detectLink(in event: EKEvent) -> URL? {
        // Check the event URL first — most reliable source
        if let url = event.url, isVideoLink(url) {
            return url
        }

        // Search through text fields
        let searchTexts = [event.notes, event.location].compactMap { $0 }

        for text in searchTexts {
            if let url = findVideoURL(in: text) {
                return url
            }
        }

        return nil
    }

    static func isVideoLink(_ url: URL) -> Bool {
        let urlString = url.absoluteString
        return patterns.contains { _, pattern in
            urlString.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func findVideoURL(in text: String) -> URL? {
        for (_, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                let matchRange = Range(match.range, in: text)!
                var urlString = String(text[matchRange])

                // Clean trailing punctuation that might have been captured
                while urlString.hasSuffix(")") || urlString.hasSuffix(">") ||
                      urlString.hasSuffix("\"") || urlString.hasSuffix("'") {
                    urlString = String(urlString.dropLast())
                }

                if let url = URL(string: urlString) {
                    return url
                }
            }
        }

        return nil
    }

    /// Convert an HTTPS meeting URL to the native app URL scheme so the
    /// meeting app opens directly instead of going through the browser.
    static func nativeAppURL(for url: URL) -> URL {
        let host = url.host?.lowercased() ?? ""
        let absString = url.absoluteString

        // Zoom: https://zoom.us/j/123?pwd=abc → zoommtg://zoom.us/join?confno=123&pwd=abc
        if host.contains("zoom.us"), absString.contains("/j/") {
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = host
            components.path = "/join"

            let pathParts = url.pathComponents
            if let jIndex = pathParts.firstIndex(of: "j"),
               jIndex + 1 < pathParts.count {
                let confno = pathParts[jIndex + 1]
                var queryItems = [URLQueryItem(name: "confno", value: confno)]
                // Preserve password and other query params
                if let existing = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                    queryItems.append(contentsOf: existing)
                }
                components.queryItems = queryItems
            }

            if let native = components.url { return native }
        }

        // Teams: https://teams.microsoft.com/l/meetup-join/... → msteams://...
        if host.contains("teams.microsoft.com") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "msteams"
            if let native = components?.url { return native }
        }

        return url
    }

    /// Open a meeting URL, preferring the native app scheme with browser fallback.
    static func openMeetingURL(_ url: URL) {
        let native = nativeAppURL(for: url)
        if native != url {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(native, configuration: config) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func serviceName(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom.us") { return "Zoom" }
        if host.contains("meet.google.com") { return "Google Meet" }
        if host.contains("teams.microsoft.com") { return "Teams" }
        if host.contains("webex.com") { return "Webex" }
        if host.contains("slack.com") { return "Slack" }
        return "Meeting"
    }
}
