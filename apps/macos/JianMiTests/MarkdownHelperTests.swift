import XCTest
@testable import JianMi

final class MarkdownHelperTests: XCTestCase {
    func testHardBreaks() {
        // 单个回车 → 硬换行（行尾补两个空格）
        let input = "第一行\n第二行"
        XCTAssertEqual(input.noteMarkdown, "第一行  \n第二行  ")
    }

    func testChineseHeadingAutoSpace() {
        // #标题 自动补空格
        XCTAssertEqual("#无敌的".noteMarkdown, "# 无敌的  ")
        XCTAssertEqual("##二级标题".noteMarkdown, "## 二级标题  ")
        // 已有空格的不重复处理
        XCTAssertEqual("# 正常标题".noteMarkdown, "# 正常标题  ")
        // 6 个以上 # 不是标题，不处理
        XCTAssertEqual("#######七个".noteMarkdown, "#######七个  ")
    }

    func testCodeFenceUntouched() {
        let input = """
        说明文字
        ```swift
        #这是代码不是标题
        let a = 1
        ```
        结尾
        """
        let out = input.noteMarkdown
        // 代码块内保持原样（无补空格、无硬换行）
        XCTAssertTrue(out.contains("#这是代码不是标题\n"))
        XCTAssertTrue(out.contains("let a = 1\n"))
        // 代码块外正常处理
        XCTAssertTrue(out.hasPrefix("说明文字  \n"))
        XCTAssertTrue(out.hasSuffix("结尾  "))
    }

    func testEmptyLinesPreserved() {
        let input = "段落一\n\n段落二"
        XCTAssertEqual(input.noteMarkdown, "段落一  \n\n段落二  ")
    }
}
