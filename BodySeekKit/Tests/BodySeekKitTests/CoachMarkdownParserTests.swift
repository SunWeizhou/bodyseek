@testable import BodySeekFeatures
import Foundation
import XCTest

final class CoachMarkdownParserTests: XCTestCase {
    @MainActor
    func testReplyPreservesMarkdownStructureWithoutImageRequests() async {
        let reply = CoachMarkdownParser().attributedString(for: """
        ## 身体状态

        - **恢复待同步**

        | 指标 | 状态 |
        | --- | --- |
        | 睡眠 | 待同步 |

        ![图表说明](https://example.invalid/chart.png)
        """)
        let blocks = reply.runs.flatMap { $0.presentationIntent?.components.map(\.kind) ?? [] }

        XCTAssertTrue(blocks.contains(.header(level: 2)))
        XCTAssertTrue(blocks.contains(.unorderedList))
        XCTAssertTrue(blocks.contains(.tableHeaderRow))
        XCTAssertTrue(reply.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(String(reply.characters).contains("图表说明"))
        XCTAssertFalse(reply.runs.contains { $0.imageURL != nil })
    }
}
