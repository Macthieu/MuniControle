import Foundation

public enum QualitySeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public enum QualityLevel: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case critical
}

public struct QualityFinding: Codable, Equatable, Sendable {
    public let code: String
    public let severity: QualitySeverity
    public let message: String

    public init(code: String, severity: QualitySeverity, message: String) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct QualityGate: Codable, Equatable, Sendable {
    public let id: String
    public let passed: Bool
    public let message: String

    public init(id: String, passed: Bool, message: String) {
        self.id = id
        self.passed = passed
        self.message = message
    }
}

public struct ControlSeedData: Equatable, Sendable {
    public let text: String
    public let sourceKind: String
    public let metadataKeywordCount: Int
    public let metadataSummary: String?
    public let metadataSuggestedTitle: String?
    public let preclassTopClassCode: String?
    public let preclassTopScore: Int
    public let preclassConfidence: String?
    public let analysisWordCount: Int?
    public let minQualityScore: Int

    public init(
        text: String,
        sourceKind: String,
        metadataKeywordCount: Int = 0,
        metadataSummary: String? = nil,
        metadataSuggestedTitle: String? = nil,
        preclassTopClassCode: String? = nil,
        preclassTopScore: Int = 0,
        preclassConfidence: String? = nil,
        analysisWordCount: Int? = nil,
        minQualityScore: Int = 70
    ) {
        self.text = text
        self.sourceKind = sourceKind
        self.metadataKeywordCount = max(0, metadataKeywordCount)
        self.metadataSummary = metadataSummary
        self.metadataSuggestedTitle = metadataSuggestedTitle
        self.preclassTopClassCode = preclassTopClassCode
        self.preclassTopScore = max(0, preclassTopScore)
        self.preclassConfidence = preclassConfidence
        self.analysisWordCount = analysisWordCount
        self.minQualityScore = min(max(0, minQualityScore), 100)
    }
}
