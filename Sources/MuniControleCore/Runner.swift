import Foundation

public struct QualityControlReport: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sourceKind: String
    public let qualityScore: Int
    public let qualityLevel: QualityLevel
    public let findings: [QualityFinding]
    public let gates: [QualityGate]
    public let suggestedActions: [String]

    public init(
        generatedAt: String,
        sourceKind: String,
        qualityScore: Int,
        qualityLevel: QualityLevel,
        findings: [QualityFinding],
        gates: [QualityGate],
        suggestedActions: [String]
    ) {
        self.generatedAt = generatedAt
        self.sourceKind = sourceKind
        self.qualityScore = qualityScore
        self.qualityLevel = qualityLevel
        self.findings = findings
        self.gates = gates
        self.suggestedActions = suggestedActions
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case sourceKind = "source_kind"
        case qualityScore = "quality_score"
        case qualityLevel = "quality_level"
        case findings
        case gates
        case suggestedActions = "suggested_actions"
    }
}

public enum MuniControleRunner {
    public static func audit(seedData: ControlSeedData, generatedAt: String? = nil) -> QualityControlReport {
        let timestamp = generatedAt ?? isoTimestamp()
        let trimmedText = seedData.text.trimmingCharacters(in: .whitespacesAndNewlines)

        var score = 100
        var findings: [QualityFinding] = []
        var gates: [QualityGate] = []

        let hasSummary = hasContent(seedData.metadataSummary) || hasContent(deriveSummary(from: trimmedText))
        let hasKeywords = seedData.metadataKeywordCount > 0
        let hasRichKeywords = seedData.metadataKeywordCount >= 3
        let hasPreclassification = hasContent(seedData.preclassTopClassCode) && seedData.preclassTopScore > 0
        let hasStrongPreclassification = hasPreclassification && seedData.preclassTopScore >= 3
        let confidenceIsLow = (seedData.preclassConfidence?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "low")
        let estimatedWordCount = seedData.analysisWordCount ?? wordCount(from: trimmedText)

        if !hasSummary {
            score -= 20
            findings.append(QualityFinding(code: "SUMMARY_MISSING", severity: .warning, message: "Aucun resume exploitable detecte."))
        }
        gates.append(QualityGate(id: "summary_present", passed: hasSummary, message: hasSummary ? "Resume present." : "Resume absent."))

        if !hasKeywords {
            score -= 25
            findings.append(QualityFinding(code: "KEYWORDS_MISSING", severity: .warning, message: "Aucun mot-cle structure disponible."))
        } else if !hasRichKeywords {
            score -= 10
            findings.append(QualityFinding(code: "KEYWORDS_WEAK", severity: .warning, message: "Moins de 3 mots-cles detectes."))
        }
        gates.append(QualityGate(id: "keywords_present", passed: hasKeywords, message: hasKeywords ? "Mots-cles presents." : "Mots-cles absents."))

        if !hasPreclassification {
            score -= 20
            findings.append(QualityFinding(code: "PRECLASSIFICATION_MISSING", severity: .warning, message: "Aucun resultat de preclassement exploitable."))
        } else if !hasStrongPreclassification || confidenceIsLow {
            score -= 15
            findings.append(QualityFinding(code: "PRECLASSIFICATION_WEAK", severity: .warning, message: "Preclassement present mais confiance insuffisante."))
        }
        gates.append(QualityGate(
            id: "preclassification_present",
            passed: hasPreclassification,
            message: hasPreclassification ? "Preclassement present." : "Preclassement absent."
        ))

        if estimatedWordCount < 20 {
            score -= 10
            findings.append(QualityFinding(code: "CONTENT_TOO_SHORT", severity: .info, message: "Volume de contenu faible pour un controle fiable."))
        }
        gates.append(QualityGate(
            id: "content_volume",
            passed: estimatedWordCount >= 20,
            message: estimatedWordCount >= 20 ? "Volume de contenu adequat." : "Volume de contenu faible."
        ))

        if trimmedText.isEmpty && !hasContent(seedData.metadataSummary) && !hasContent(seedData.metadataSuggestedTitle) {
            score -= 20
            findings.append(QualityFinding(code: "TEXT_SIGNAL_MISSING", severity: .error, message: "Aucun signal textuel exploitable detecte."))
        }
        gates.append(QualityGate(
            id: "text_signal",
            passed: !(trimmedText.isEmpty && !hasContent(seedData.metadataSummary) && !hasContent(seedData.metadataSuggestedTitle)),
            message: "Signal textuel minimum requis."
        ))

        score = min(max(score, 0), 100)

        if score < seedData.minQualityScore {
            findings.append(QualityFinding(
                code: "QUALITY_BELOW_THRESHOLD",
                severity: .warning,
                message: "Score qualite (\(score)) sous le seuil attendu (\(seedData.minQualityScore))."
            ))
        }

        let qualityLevel = qualityLevel(for: score)
        let suggestedActions = buildSuggestedActions(findings: findings)

        return QualityControlReport(
            generatedAt: timestamp,
            sourceKind: seedData.sourceKind,
            qualityScore: score,
            qualityLevel: qualityLevel,
            findings: findings,
            gates: gates,
            suggestedActions: suggestedActions
        )
    }

    private static func hasContent(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func deriveSummary(from text: String) -> String? {
        guard !text.isEmpty else { return nil }

        let sentence = text
            .split(whereSeparator: { ".!?".contains($0) })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sentence, !sentence.isEmpty else {
            return nil
        }
        return sentence
    }

    private static func wordCount(from text: String) -> Int {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
    }

    private static func qualityLevel(for score: Int) -> QualityLevel {
        switch score {
        case 85...100:
            return .high
        case 70..<85:
            return .medium
        case 50..<70:
            return .low
        default:
            return .critical
        }
    }

    private static func buildSuggestedActions(findings: [QualityFinding]) -> [String] {
        var actions: Set<String> = []

        for finding in findings {
            switch finding.code {
            case "SUMMARY_MISSING":
                actions.insert("Ajouter ou corriger le resume documentaire.")
            case "KEYWORDS_MISSING", "KEYWORDS_WEAK":
                actions.insert("Renforcer les metadonnees (mots-cles) avant publication.")
            case "PRECLASSIFICATION_MISSING", "PRECLASSIFICATION_WEAK":
                actions.insert("Reexecuter le preclassement avec un contexte plus riche.")
            case "CONTENT_TOO_SHORT", "TEXT_SIGNAL_MISSING":
                actions.insert("Fournir davantage de contenu textuel pour le controle qualite.")
            case "QUALITY_BELOW_THRESHOLD":
                actions.insert("Lancer une revue manuelle avant validation finale.")
            default:
                actions.insert("Revue manuelle recommandee.")
            }
        }

        return actions.sorted()
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
