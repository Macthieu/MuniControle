import Foundation
import MuniControleCore
import OrchivisteKitContracts

private struct MetadataKeywordPayload: Codable {
    let term: String
    let score: Int
}

private struct MetadataReportPayload: Codable {
    let keywords: [MetadataKeywordPayload]?
    let summary: String?
    let suggestedTitle: String?

    enum CodingKeys: String, CodingKey {
        case keywords
        case summary
        case suggestedTitle = "suggested_title"
    }
}

private struct PreclassificationReportPayload: Codable {
    let topClassCode: String?
    let topScore: Int?
    let confidenceLevel: String?

    enum CodingKeys: String, CodingKey {
        case topClassCode = "top_class_code"
        case topScore = "top_score"
        case confidenceLevel = "confidence_level"
    }
}

private struct AnalysisReportPayload: Codable {
    let wordCount: Int?
    let preview: String?

    enum CodingKeys: String, CodingKey {
        case wordCount = "word_count"
        case preview
    }
}

private struct SeedAggregate {
    var metadataKeywordCount: Int = 0
    var metadataSummary: String?
    var metadataSuggestedTitle: String?
    var preclassTopClassCode: String?
    var preclassTopScore: Int = 0
    var preclassConfidence: String?
    var analysisWordCount: Int?
    var analysisPreview: String?

    mutating func merge(_ other: SeedAggregate) {
        metadataKeywordCount = max(metadataKeywordCount, other.metadataKeywordCount)
        metadataSummary = firstNonEmpty(metadataSummary, other.metadataSummary)
        metadataSuggestedTitle = firstNonEmpty(metadataSuggestedTitle, other.metadataSuggestedTitle)
        preclassTopClassCode = firstNonEmpty(preclassTopClassCode, other.preclassTopClassCode)
        preclassTopScore = max(preclassTopScore, other.preclassTopScore)
        preclassConfidence = firstNonEmpty(preclassConfidence, other.preclassConfidence)

        if let wordCount = other.analysisWordCount {
            analysisWordCount = max(analysisWordCount ?? 0, wordCount)
        }
        analysisPreview = firstNonEmpty(analysisPreview, other.analysisPreview)
    }

    private func firstNonEmpty(_ first: String?, _ second: String?) -> String? {
        if let first, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return first
        }
        if let second, !second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return second
        }
        return nil
    }
}

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingInput
    case invalidParameter(String, String)
    case sourceReadFailed(String)
    case metadataReportParseFailed(String)
    case preclassificationReportParseFailed(String)
    case analysisReportParseFailed(String)
    case reportWriteFailed(String)
    case runtimeFailure(String)

    var toolError: ToolError {
        switch self {
        case .unsupportedAction(let action):
            return ToolError(code: "UNSUPPORTED_ACTION", message: "Unsupported action: \(action)", retryable: false)
        case .missingInput:
            return ToolError(code: "MISSING_INPUT", message: "Provide text/source or at least one valid report seed.", retryable: false)
        case .invalidParameter(let parameter, let reason):
            return ToolError(code: "INVALID_PARAMETER", message: "Invalid parameter \(parameter): \(reason)", retryable: false)
        case .sourceReadFailed(let reason):
            return ToolError(code: "SOURCE_READ_FAILED", message: reason, retryable: false)
        case .metadataReportParseFailed(let reason):
            return ToolError(code: "METADATA_REPORT_PARSE_FAILED", message: reason, retryable: false)
        case .preclassificationReportParseFailed(let reason):
            return ToolError(code: "PRECLASSIFICATION_REPORT_PARSE_FAILED", message: reason, retryable: false)
        case .analysisReportParseFailed(let reason):
            return ToolError(code: "ANALYSIS_REPORT_PARSE_FAILED", message: reason, retryable: false)
        case .reportWriteFailed(let reason):
            return ToolError(code: "REPORT_WRITE_FAILED", message: reason, retryable: true)
        case .runtimeFailure(let reason):
            return ToolError(code: "RUNTIME_FAILURE", message: reason, retryable: false)
        }
    }
}

private struct CanonicalExecutionContext: Sendable {
    let seedData: ControlSeedData
    let outputPath: String?
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            let context = try parseContext(from: request)
            let report = MuniControleRunner.audit(seedData: context.seedData, generatedAt: isoTimestamp())
            let finishedAt = isoTimestamp()

            let hasWarningOrError = report.findings.contains { finding in
                finding.severity == .warning || finding.severity == .error
            }
            let status: ToolStatus = hasWarningOrError ? .needsReview : .succeeded
            let summary = status == .succeeded
                ? "Quality control completed successfully."
                : "Quality control completed with review findings."

            var outputArtifacts: [ArtifactDescriptor] = []
            if let outputPath = context.outputPath {
                try writeReport(report, toPath: outputPath)
                outputArtifacts.append(
                    ArtifactDescriptor(
                        id: "quality_report",
                        kind: .report,
                        uri: fileURI(forPath: outputPath),
                        mediaType: "application/json",
                        metadata: [
                            "quality_score": .number(Double(report.qualityScore))
                        ]
                    )
                )
            }

            return makeResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                status: status,
                summary: summary,
                outputArtifacts: outputArtifacts,
                errors: [],
                metadata: resultMetadata(from: report)
            )
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical quality control request failed."
            )
        } catch {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError],
                summary: "Canonical quality control request failed with an unexpected runtime error."
            )
        }
    }

    private static func parseContext(from request: ToolRequest) throws -> CanonicalExecutionContext {
        try validateAction(request.action)

        let inlineText = try optionalStringParameter("text", in: request)
        let sourcePath = try optionalStringParameter("source_path", in: request)
        let outputPath = try optionalStringParameter("output_report_path", in: request)

        let minQualityScore = try optionalIntParameter("min_quality_score", in: request) ?? 70
        guard (0...100).contains(minQualityScore) else {
            throw CanonicalRunAdapterError.invalidParameter("min_quality_score", "expected integer in range 0...100")
        }

        var seeds = SeedAggregate()

        if let metadataPath = try optionalStringParameter("metadata_report_path", in: request), !metadataPath.isEmpty {
            seeds.merge(try parseMetadataSeed(fromPath: metadataPath, strict: true))
        }
        if let preclassPath = try optionalStringParameter("preclassification_report_path", in: request), !preclassPath.isEmpty {
            seeds.merge(try parsePreclassificationSeed(fromPath: preclassPath, strict: true))
        }
        if let analysisPath = try optionalStringParameter("analysis_report_path", in: request), !analysisPath.isEmpty {
            seeds.merge(try parseAnalysisSeed(fromPath: analysisPath, strict: true))
        }

        for reportArtifact in request.inputArtifacts where reportArtifact.kind == .report {
            let path = resolvePathFromURIOrPath(reportArtifact.uri)
            seeds.merge((try? parseMetadataSeed(fromPath: path, strict: false)) ?? SeedAggregate())
            seeds.merge((try? parsePreclassificationSeed(fromPath: path, strict: false)) ?? SeedAggregate())
            seeds.merge((try? parseAnalysisSeed(fromPath: path, strict: false)) ?? SeedAggregate())
        }

        let resolvedText: String
        let sourceKind: String

        if let inlineText, !inlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedText = inlineText
            sourceKind = "inline_text"
        } else if let sourcePath {
            resolvedText = try readText(fromPath: sourcePath)
            sourceKind = "source_path"
        } else if let inputPath = firstInputArtifactPath(in: request) {
            resolvedText = try readText(fromPath: inputPath)
            sourceKind = "input_artifact"
        } else {
            let combined = [seeds.metadataSuggestedTitle, seeds.metadataSummary, seeds.analysisPreview]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            resolvedText = combined
            sourceKind = combined.isEmpty ? "unknown" : "report_seed"
        }

        let hasSeedSignal = seeds.metadataKeywordCount > 0 || seeds.preclassTopScore > 0 || seeds.analysisWordCount != nil
        if resolvedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasSeedSignal {
            throw CanonicalRunAdapterError.missingInput
        }

        let seedData = ControlSeedData(
            text: resolvedText,
            sourceKind: sourceKind,
            metadataKeywordCount: seeds.metadataKeywordCount,
            metadataSummary: seeds.metadataSummary,
            metadataSuggestedTitle: seeds.metadataSuggestedTitle,
            preclassTopClassCode: seeds.preclassTopClassCode,
            preclassTopScore: seeds.preclassTopScore,
            preclassConfidence: seeds.preclassConfidence,
            analysisWordCount: seeds.analysisWordCount,
            minQualityScore: minQualityScore
        )

        return CanonicalExecutionContext(seedData: seedData, outputPath: outputPath)
    }

    private static func validateAction(_ rawAction: String) throws {
        let normalized = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "run", "audit":
            return
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawAction)
        }
    }

    private static func optionalStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .string(let rawValue):
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ""
            }

            switch key {
            case "source_path", "metadata_report_path", "preclassification_report_path", "analysis_report_path", "output_report_path":
                return resolvePathFromURIOrPath(trimmed)
            default:
                return trimmed
            }
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalIntParameter(_ key: String, in request: ToolRequest) throws -> Int? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .number(let numberValue):
            guard numberValue.rounded() == numberValue else {
                throw CanonicalRunAdapterError.invalidParameter(key, "expected integer value")
            }
            return Int(numberValue)
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected number")
        }
    }

    private static func parseMetadataSeed(fromPath path: String, strict: Bool) throws -> SeedAggregate {
        let data = try readData(fromPath: path)

        if let payload = try? JSONDecoder().decode(MetadataReportPayload.self, from: data) {
            var seed = SeedAggregate()
            seed.metadataKeywordCount = payload.keywords?.count ?? 0
            seed.metadataSummary = payload.summary
            seed.metadataSuggestedTitle = payload.suggestedTitle
            return seed
        }

        if let toolResult = try? JSONDecoder().decode(ToolResult.self, from: data) {
            var seed = SeedAggregate()
            seed.metadataKeywordCount = jsonKeywordCount(from: toolResult.metadata["keywords"])
            seed.metadataSummary = jsonString(from: toolResult.metadata["summary"])
            seed.metadataSuggestedTitle = jsonString(from: toolResult.metadata["suggested_title"])
            return seed
        }

        if strict {
            throw CanonicalRunAdapterError.metadataReportParseFailed("Unsupported metadata report at \(path).")
        }
        return SeedAggregate()
    }

    private static func parsePreclassificationSeed(fromPath path: String, strict: Bool) throws -> SeedAggregate {
        let data = try readData(fromPath: path)

        if let payload = try? JSONDecoder().decode(PreclassificationReportPayload.self, from: data) {
            var seed = SeedAggregate()
            seed.preclassTopClassCode = payload.topClassCode
            seed.preclassTopScore = payload.topScore ?? 0
            seed.preclassConfidence = payload.confidenceLevel
            return seed
        }

        if let toolResult = try? JSONDecoder().decode(ToolResult.self, from: data) {
            var seed = SeedAggregate()
            seed.preclassTopClassCode = jsonString(from: toolResult.metadata["top_class_code"])
            seed.preclassTopScore = jsonInt(from: toolResult.metadata["top_score"]) ?? 0
            seed.preclassConfidence = jsonString(from: toolResult.metadata["confidence_level"])
            return seed
        }

        if strict {
            throw CanonicalRunAdapterError.preclassificationReportParseFailed("Unsupported preclassification report at \(path).")
        }
        return SeedAggregate()
    }

    private static func parseAnalysisSeed(fromPath path: String, strict: Bool) throws -> SeedAggregate {
        let data = try readData(fromPath: path)

        if let payload = try? JSONDecoder().decode(AnalysisReportPayload.self, from: data) {
            var seed = SeedAggregate()
            seed.analysisWordCount = payload.wordCount
            seed.analysisPreview = payload.preview
            return seed
        }

        if let toolResult = try? JSONDecoder().decode(ToolResult.self, from: data) {
            var seed = SeedAggregate()
            seed.analysisWordCount = jsonInt(from: toolResult.metadata["word_count"])
            seed.analysisPreview = jsonString(from: toolResult.metadata["preview"])
            return seed
        }

        if strict {
            throw CanonicalRunAdapterError.analysisReportParseFailed("Unsupported analysis report at \(path).")
        }
        return SeedAggregate()
    }

    private static func readData(fromPath path: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CanonicalRunAdapterError.sourceReadFailed(
                "Unable to read source at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func firstInputArtifactPath(in request: ToolRequest) -> String? {
        request.inputArtifacts
            .first(where: { $0.kind == .input })
            .map { resolvePathFromURIOrPath($0.uri) }
    }

    private static func readText(fromPath path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            do {
                let data = try Data(contentsOf: fileURL)
                return String(decoding: data, as: UTF8.self)
            } catch {
                throw CanonicalRunAdapterError.sourceReadFailed(
                    "Unable to read text at \(path): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func writeReport(_ report: QualityControlReport, toPath path: String) throws {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CanonicalRunAdapterError.reportWriteFailed(
                "Unable to write quality report at \(path): \(error.localizedDescription)"
            )
        }
    }

    private static func resultMetadata(from report: QualityControlReport) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "source_kind": .string(report.sourceKind),
            "quality_score": .number(Double(report.qualityScore)),
            "quality_level": .string(report.qualityLevel.rawValue),
            "findings": .array(
                report.findings.map {
                    .object([
                        "code": .string($0.code),
                        "severity": .string($0.severity.rawValue),
                        "message": .string($0.message)
                    ])
                }
            ),
            "gates": .array(
                report.gates.map {
                    .object([
                        "id": .string($0.id),
                        "passed": .bool($0.passed),
                        "message": .string($0.message)
                    ])
                }
            ),
            "suggested_actions": .array(report.suggestedActions.map { .string($0) })
        ]

        if let criticalFinding = report.findings.first(where: { $0.severity == .error }) {
            metadata["critical_issue"] = .string(criticalFinding.code)
        }

        return metadata
    }

    private static func makeResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        status: ToolStatus,
        summary: String,
        outputArtifacts: [ArtifactDescriptor],
        errors: [ToolError],
        metadata: [String: JSONValue]
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "quality_checks",
                    percent: 75,
                    message: "Deterministic quality checks executed.",
                    occurredAt: finishedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: status,
                    stage: "quality_control_complete",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: outputArtifacts,
            errors: errors,
            summary: summary,
            metadata: metadata
        )
    }

    private static func makeFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        errors: [ToolError],
        summary: String
    ) -> ToolResult {
        ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .running,
                    stage: "load_input",
                    percent: 20,
                    message: "Canonical request parsed.",
                    occurredAt: startedAt
                ),
                ProgressEvent(
                    requestID: request.requestID,
                    status: .failed,
                    stage: "quality_control_failed",
                    percent: 100,
                    message: summary,
                    occurredAt: finishedAt
                )
            ],
            outputArtifacts: [],
            errors: errors,
            summary: summary,
            metadata: ["action": .string(request.action)]
        )
    }

    private static func jsonString(from value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonInt(from value: JSONValue?) -> Int? {
        guard case .number(let raw)? = value else {
            return nil
        }
        guard raw.rounded() == raw else {
            return nil
        }
        return Int(raw)
    }

    private static func jsonKeywordCount(from value: JSONValue?) -> Int {
        guard case .array(let entries)? = value else {
            return 0
        }
        return entries.count
    }

    private static func resolvePathFromURIOrPath(_ candidate: String) -> String {
        guard let url = URL(string: candidate), url.isFileURL else {
            return candidate
        }
        return url.path
    }

    private static func fileURI(forPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
