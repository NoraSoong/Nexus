import NexusCore
import XCTest

final class ContextTextSanitizerTests: XCTestCase {
    func testRemovesInternalCitationAliasesFromNaturalLanguage() {
        XCTAssertEqual(
            ContextTextSanitizer.cleanText("目标依据 S3，约束见 S4。"),
            "目标依据，约束见。"
        )
        XCTAssertEqual(ContextTextSanitizer.cleanText("使用 AWS S3 存储。"), "使用 AWS S3 存储。")
        XCTAssertEqual(
            ContextTextSanitizer.cleanText("基于 PRD 文档（S3）。代码变更证据（S4）仅供参考。"),
            "基于 PRD 文档。代码变更证据仅供参考。"
        )
        XCTAssertEqual(
            ContextTextSanitizer.cleanGeneratedText("基于 PRD 文档（S3）。代码变更证据（S4）仅供参考。"),
            "基于 PRD 文档。代码变更证据仅供参考。"
        )
    }

    func testPreservesCitationMetadata() {
        let content = ContextPackContent(
            objective: "目标 S1",
            scopeIn: [ContextClaim(text: "范围 S2", sourceIDs: ["file:1"])],
            scopeOut: [],
            confirmedFacts: [],
            constraints: [],
            acceptanceCriteria: [],
            assumptions: [],
            questions: [],
            brief: "摘要 S3",
            recommendedSourceIDs: ["file:1"]
        )

        let cleaned = ContextTextSanitizer.clean(content)

        XCTAssertEqual(cleaned.objective, "目标")
        XCTAssertEqual(cleaned.scopeIn.first?.text, "范围")
        XCTAssertEqual(cleaned.scopeIn.first?.sourceIDs, ["file:1"])
        XCTAssertEqual(cleaned.brief, "摘要")
        XCTAssertEqual(cleaned.recommendedSourceIDs, ["file:1"])

        let technicalContent = ContextPackContent(
            objective: "使用 AWS S3 存储",
            scopeIn: [],
            scopeOut: [],
            confirmedFacts: [],
            constraints: [],
            acceptanceCriteria: [],
            assumptions: [],
            questions: [],
            brief: "调用 AWS S3 接口",
            recommendedSourceIDs: []
        )
        let cleanedTechnicalContent = ContextTextSanitizer.clean(technicalContent)
        XCTAssertEqual(cleanedTechnicalContent.objective, "使用 AWS S3 存储")
        XCTAssertEqual(cleanedTechnicalContent.brief, "调用 AWS S3 接口")
    }
}
