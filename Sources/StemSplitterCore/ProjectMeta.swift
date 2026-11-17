import Foundation

/// Metadata som sparas i varje cachat projekt (project.json).
public struct ProjectMeta: Codable, Equatable, Sendable {
    public static let fileName = "project.json"

    public var sourceName: String
    public var createdAt: Date
    public var model: String
    /// Vågformstoppar per stem, nyckel = `StemKind.rawValue`.
    public var peaks: [String: [Float]]
    /// Tempo och slag (saknas i projekt från äldre versioner).
    public var beatGrid: BeatGrid?
    /// Sökväg till originalfilen när låten separerades (för att kunna separera om).
    public var sourcePath: String?

    public init(
        sourceName: String,
        createdAt: Date,
        model: String,
        peaks: [String: [Float]] = [:],
        beatGrid: BeatGrid? = nil,
        sourcePath: String? = nil
    ) {
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.model = model
        self.peaks = peaks
        self.beatGrid = beatGrid
        self.sourcePath = sourcePath
    }

    public var displayName: String {
        let base = (sourceName as NSString).deletingPathExtension
        return base.isEmpty ? sourceName : base
    }

    public func peaks(for kind: StemKind) -> [Float]? {
        peaks[kind.rawValue]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProjectMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectMeta.self, from: data)
    }
}
