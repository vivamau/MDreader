import Foundation

func expect(_ source: String, _ expected: [MarkdownBlock]) {
    let actual = MarkdownBlocks.parse(source)
    precondition(actual == expected, "Unexpected parse for \(source): \(actual)")
}
expect("# Title\n\nHello **world**", [.heading(1, "Title"), .paragraph("Hello **world**")])
expect("```swift\nlet x = 1\n```", [.code("let x = 1")])
expect("````\n```\n````", [.code("```")])
expect("~~~\nunfinished", [.code("unfinished")])
expect("- first\n2. second\n> quote\n---", [.item("• first"), .item("2. second"), .quote("quote"), .rule])
expect("#hashtag\nnext", [.paragraph("#hashtag\nnext")])
expect("", [])
print("7 Markdown parser checks passed")
expect("| Name | Value |\r\n| :--- | ---: |\r\n| **one** | 2 |", [.table(headers: ["Name", "Value"], alignments: [.left, .right], rows: [["**one**", "2"]])])
expect("| | Center |\n|---|:---:|\n| a | `x\\|y` |", [.table(headers: ["", "Center"], alignments: [.left, .center], rows: [["a", "`x|y`"]])])
expect("A | B\n--- | ---\nx | y | extra\nz |\n\nafter", [.table(headers: ["A", "B"], alignments: [.left, .left], rows: [["x", "y"], ["z", ""]]), .paragraph("after")])
expect("| A | B |\n| nope | --- |", [.paragraph("| A | B |\n| nope | --- |")])
expect("```\n| A | B |\n|---|---|\n```", [.code("| A | B |\n|---|---|")])
expect("| A | B |\n|---|", [.paragraph("| A | B |\n|---|")])
print("6 table regression checks passed")
if CommandLine.arguments.count > 1 {
    let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    let tables = MarkdownBlocks.parse(source).compactMap { block -> [[String]]? in
        if case let .table(headers, _, rows) = block {
            precondition(headers.count > 0 && rows.allSatisfy { $0.count == headers.count })
            return rows
        }
        return nil
    }
    precondition(tables.count == 11, "Expected all eleven audit tables, got \(tables.count)")
    precondition(tables.flatMap { $0 }.flatMap { $0 }.contains { $0.contains("{{ message|escapejs }}") })
    print("Audit document: all 11 tables parsed, escaped code pipe preserved")
}

let printHTML = PrintHTML.document("# Title\n\n**Bold** & <script>alert(1)</script>\n\n| A | B |\n|---|---:|\n| x | `y` |\n\n```\n<x>\n```", title: "<Document>")
precondition(printHTML.contains("<h1>Title</h1>"))
precondition(printHTML.contains("<strong>Bold</strong>"))
precondition(!printHTML.contains("<script>"))
precondition(printHTML.contains("&lt;script&gt;"))
precondition(printHTML.contains("<thead><tr>"))
precondition(printHTML.contains("text-align:right"))
precondition(printHTML.contains("<pre><code>&lt;x&gt;</code></pre>"))
precondition(printHTML.contains("<title>&lt;Document&gt;</title>"))
print("8 print HTML checks passed")
