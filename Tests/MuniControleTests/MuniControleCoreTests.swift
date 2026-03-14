import Testing
@testable import MuniControleCore

struct MuniControleCoreTests {
    @Test
    func placeholderReturnsNotImplementedStatus() {
        let request = ToolRequest(requestID: "req-1", tool: "MuniControle", action: "run")
        let result = MuniControleRunner.runPlaceholder(request: request)

        #expect(result.status == ToolStatus.notImplemented)
        #expect(result.errors.first?.code == "NOT_IMPLEMENTED")
        #expect(result.requestID == "req-1")
    }
}
