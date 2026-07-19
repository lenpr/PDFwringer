import Testing

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

    @Test("Both bounds of range out of bounds throws")
    func bothBoundsOutOfRange() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("15-20", pageCount: 10)
        }
    }

    @Test("Single page document works with page 1")
    func singlePageDoc() throws {
        let result = try PageRangeParser.parse("1", pageCount: 1)
        #expect(result == [0])
    }

    @Test("Single page document rejects page 2")
    func singlePageDocRejectsTwo() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("2", pageCount: 1)
        }
    }

    @Test("Comma-only input returns empty")
    func commaOnly() throws {
        let result = try PageRangeParser.parse(",,,", pageCount: 10)
        #expect(result.isEmpty)
    }

    @Test("Spaces around dash in range throws (not a valid integer)")
    func spacesAroundDash() throws {
        #expect(throws: PDFwringerError.self) {
            try PageRangeParser.parse("2 - 4", pageCount: 10)
        }
    }

    @Test("Open-start range covering all pages")
    func openStartAllPages() throws {
        let result = try PageRangeParser.parse("-5", pageCount: 5)
        #expect(result == [0, 1, 2, 3, 4])
    }

    @Test("Zero pageCount returns empty regardless of input")
    func zeroPageCount() throws {
        let result = try PageRangeParser.parse("1-5", pageCount: 0)
        #expect(result.isEmpty)
    }
}

@Suite("PageSelection")
struct PageSelectionTests {

    @Test("All-pages mode resolves the complete document")
    func resolvesAllPages() {
        let selection = PageSelection()

        #expect(selection.resolvedIndices(pageCount: 4) == [0, 1, 2, 3])
    }

    @Test("Typed ranges normalize to unique sorted pages")
    func normalizesTypedRange() {
        var selection = PageSelection(appliesToAll: false)

        selection.update(from: "5, 3-4, 3", pageCount: 5)

        #expect(selection.selectedPages == [2, 3, 4])
        #expect(selection.resolvedIndices(pageCount: 5) == [2, 3, 4])
    }

    @Test("Invalid text clears the previous authoritative selection")
    func invalidTextClearsSelection() {
        var selection = PageSelection(appliesToAll: false)
        selection.update(from: "1-3", pageCount: 5)

        selection.update(from: "not pages", pageCount: 5)

        #expect(selection.selectedPages.isEmpty)
        #expect(selection.resolvedIndices(pageCount: 5) == nil)
    }

    @Test("Explicit empty and out-of-range selections are invalid")
    func rejectsInvalidExplicitSelection() {
        var selection = PageSelection(appliesToAll: false)
        #expect(selection.resolvedIndices(pageCount: 3) == nil)

        selection.selectedPages = [0, 3]
        #expect(selection.resolvedIndices(pageCount: 3) == nil)
    }

    @Test("Toggling all pages retains the explicit selection")
    func toggleRetainsSelection() {
        var selection = PageSelection(appliesToAll: false, selectedPages: [1, 2])
        selection.appliesToAll = true
        #expect(selection.resolvedIndices(pageCount: 4) == [0, 1, 2, 3])

        selection.appliesToAll = false
        #expect(selection.resolvedIndices(pageCount: 4) == [1, 2])
    }

    @Test("Thumbnail selection formatting is one-based and sorted")
    func formatsSelection() {
        #expect(PageSelection.formatted([4, 0, 2]) == "1, 3, 5")
    }
}
