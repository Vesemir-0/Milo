import AppKit

enum ContentType { case image(NSImage), text(String) }
struct CapturedContent {
    let type: ContentType
    let timestamp: Date
    let source: String
    let timeZoneID: String
    init(type: ContentType, source: String, timestamp: Date = Date(), timeZoneID: String = TimeZone.current.identifier) { self.type = type; self.source = source; self.timestamp = timestamp; self.timeZoneID = timeZoneID }
}
