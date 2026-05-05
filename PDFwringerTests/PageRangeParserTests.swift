import Testing
@testable import PDFwringer

@Suite("PageRangeParser")
struct PageRangeParserTests {

    @Test("Single page")
    func singlePage() throws {
        let result = try PageRangeParser.parse("3", pageCount: 10)
        #expect(result == [2])
    }

    @Test("Multiple individual pages")
    func multiplePages() throws {
        let result = try PageRangeParser.parse("1,5,10", pageCount: 10)
        #expect(result == [0, 4, 9])
    }

    @Test("Ascending range")
    func ascendingRange() throws {
        let result = try PageRangeParser.parse("3-6", pageCount: 10)
        #expect(result == [2, 3, 4, 5])
    }

    @Test("Descending range")
    func descendingRange() throws {
        let result = try PageRangeParser.parse("6-3", pageCount: 10)
        #expect(result == [5, 4, 3, 2])
    }

    @Test("Open range from start")
    func openRangeFromStart() throws {
        let result = try PageRangeParser.parse("-3", pageCount: 10)
        #expect(result == [0, 1, 2])
    }

    @Test("Open range to end")
    func openRangeToEnd() throws {
        let result = try PageRangeParser.parse("8-", pageCount: 10)
        #expect(result == [7, 8, 9])
    }

    @Test("Mixed syntax")
    func mixedSyntax() throws {
        let result = try PageRangeParser.parse("1, 3-5, 8-", pageCount: 10)
        #expect(result == [0, 2, 3, 4, 7, 8, 9])
    }

    @Test("Preserves user order")
    func preservesOrder() throws {
        let result = try PageRangeParser.parse("5,3,1", pageCount: 10)
        #expect(result == [4, 2, 0])
    }

    @Test("Allows duplicates")
    func allowsDuplicates() throws {
        let result = try PageRangeParser.parse("1,1,1", pageCount: 10)
        #expect(result == [0, 0, 0])
    }

    @Test("Whitespace is stripped")
    func whitespaceStripped() throws {
        let result = try PageRangeParser.parse("  1 , 3 , 5  ", pageCount: 10)
        #expect(result == [0, 2, 4])
    }

    @Test("Page out of bounds throws")
    func outOfBounds() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("15", pageCount: 10)
        }
    }

    @Test("Open end range out of bounds throws")
    func openEndOutOfBounds() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("15-", pageCount: 10)
        }
    }

    @Test("Zero page number throws")
    func zeroPageNumber() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("0", pageCount: 10)
        }
    }

    @Test("Non-numeric input throws")
    func nonNumeric() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("abc", pageCount: 10)
        }
    }

    @Test("Bare dash throws")
    func bareDash() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("-", pageCount: 10)
        }
    }

    @Test("Empty input returns empty")
    func emptyInput() throws {
        let result = try PageRangeParser.parse("", pageCount: 10)
        #expect(result.isEmpty)
    }
}
