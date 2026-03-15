import Foundation
import OrchivisteKitContracts
import Testing
@testable import MuniControleCore
@testable import MuniControleInterop

struct MuniControleCoreTests {
    @Test
    func auditProducesHighScoreWhenSignalsAreComplete() {
        let seedData = ControlSeedData(
            text: """
            Avis municipal concernant la revision du plan de circulation dans le secteur nord.
            Le document decrit les objectifs, les etapes de consultation publique et les impacts attendus.
            """,
            sourceKind: "inline_text",
            metadataKeywordCount: 4,
            metadataSummary: "Revision du plan de circulation pour le secteur nord.",
            metadataSuggestedTitle: "Revision circulation secteur nord",
            preclassTopClassCode: "URB-02",
            preclassTopScore: 4,
            preclassConfidence: "high",
            analysisWordCount: 28,
            minQualityScore: 70
        )
        let report = MuniControleRunner.audit(seedData: seedData, generatedAt: "2026-03-15T00:00:00Z")

        #expect(report.qualityScore >= 85)
        #expect(report.qualityLevel == .high)
        #expect(report.findings.isEmpty)
        #expect(report.gates.count == 5)
    }

    @Test
    func canonicalRunWithInlineTextReturnsNeedsReview() {
        let request = ToolRequest(
            requestID: "req-inline",
            tool: "MuniControle",
            action: "run",
            parameters: [
                "text": .string("Avis municipal bref.")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .needsReview)
        #expect(result.errors.isEmpty)
        #expect(result.progressEvents.last?.status == .needsReview)
    }

    @Test
    func canonicalRunWithSeedReportsSucceedsAndWritesReport() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("muni-controle-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let metadataPath = tempDirectory.appendingPathComponent("metadata-report.json")
        let preclassPath = tempDirectory.appendingPathComponent("preclass-report.json")
        let outputPath = tempDirectory.appendingPathComponent("quality-report.json")

        let metadataPayload = """
        {
          "keywords": [
            { "term": "urbanisme", "score": 5 },
            { "term": "mobilite", "score": 4 },
            { "term": "consultation", "score": 3 }
          ],
          "summary": "Projet de revision d'un axe de circulation.",
          "suggested_title": "Revision circulation axe nord"
        }
        """
        let preclassPayload = """
        {
          "top_class_code": "URB-02",
          "top_score": 4,
          "confidence_level": "high"
        }
        """

        try metadataPayload.write(to: metadataPath, atomically: true, encoding: .utf8)
        try preclassPayload.write(to: preclassPath, atomically: true, encoding: .utf8)

        let request = ToolRequest(
            requestID: "req-seeded",
            tool: "MuniControle",
            action: "run",
            parameters: [
                "text": .string("""
                La municipalite publie un avis detaille concernant la modernisation
                du reseau local et la planification des consultations citoyennes.
                """),
                "metadata_report_path": .string(metadataPath.path),
                "preclassification_report_path": .string(preclassPath.path),
                "output_report_path": .string(outputPath.path),
                "min_quality_score": .number(70)
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .succeeded)
        #expect(result.errors.isEmpty)
        #expect(result.outputArtifacts.count == 1)
        #expect(result.outputArtifacts.first?.kind == .report)
        #expect(FileManager.default.fileExists(atPath: outputPath.path))
    }

    @Test
    func canonicalRunFailsWithoutInput() {
        let request = ToolRequest(
            requestID: "req-missing",
            tool: "MuniControle",
            action: "run"
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .failed)
        #expect(result.errors.first?.code == "MISSING_INPUT")
    }

    @Test
    func canonicalRunFailsOnUnsupportedAction() {
        let request = ToolRequest(
            requestID: "req-action",
            tool: "MuniControle",
            action: "preview",
            parameters: [
                "text": .string("Texte de controle.")
            ]
        )

        let result = CanonicalRunAdapter.execute(request: request)

        #expect(result.status == .failed)
        #expect(result.errors.first?.code == "UNSUPPORTED_ACTION")
    }
}
