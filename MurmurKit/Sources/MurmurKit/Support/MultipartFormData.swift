import Foundation

/// Minimal multipart/form-data builder for file-upload endpoints (cloud
/// transcription APIs).
public struct MultipartFormData {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "MurmurBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    public func finalized() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n")
        return result
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
