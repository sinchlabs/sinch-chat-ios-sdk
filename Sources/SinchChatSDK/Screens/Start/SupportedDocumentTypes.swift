import UniformTypeIdentifiers

/// Document types the chat can send. Identifiers are plain ASCII on purpose: a zero-width character inside
/// a UTI silently produces a type the system does not know.
enum SupportedDocumentTypes {

    static let identifiers: [String] = [
        "com.adobe.pdf",
        "com.compuserve.gif",
        "com.microsoft.word.doc",
        "com.microsoft.excel.xls",
        "com.microsoft.powerpoint.ppt",
        "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.presentationml.presentation",
        "org.openxmlformats.spreadsheetml.sheet"
    ]

    /// Resolved content types; identifiers the system does not know are skipped.
    static var contentTypes: [UTType] {
        identifiers.compactMap { UTType($0) }
    }
}
