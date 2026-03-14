import Foundation

public enum MuniControleRunner {
    public static func runPlaceholder(request: ToolRequest) -> ToolResult {
        let now = ISO8601DateFormatter().string(from: Date())

        return ToolResult(
            requestID: request.requestID,
            tool: "MuniControle",
            status: .notImplemented,
            startedAt: now,
            finishedAt: now,
            progressEvents: [
                ProgressEvent(
                    requestID: request.requestID,
                    status: .notImplemented,
                    stage: "bootstrap",
                    percent: 100,
                    message: "MuniControle scaffold is ready; business logic not implemented.",
                    occurredAt: now
                )
            ],
            outputArtifacts: [],
            errors: [
                ToolError(
                    code: "NOT_IMPLEMENTED",
                    message: "MuniControle is scaffolded for CLI JSON V1 but processing logic is not implemented yet.",
                    retryable: false
                )
            ],
            summary: "MuniControle returned a placeholder not_implemented result."
        )
    }
}
