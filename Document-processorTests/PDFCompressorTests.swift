import XCTest
@testable import Document_processor

final class PDFCompressorTests: XCTestCase {

    // MARK: - CompressionPreset.apply Tests

    @MainActor
    func testPresetLowApply() {
        let compressor = PDFCompressor()
        CompressionPreset.low.apply(to: compressor)
        XCTAssertEqual(compressor.resolution, 72)
        XCTAssertTrue(compressor.forceJPEG)
        XCTAssertEqual(compressor.jpegQuality, 20)
        XCTAssertTrue(compressor.useGS)
        XCTAssertTrue(compressor.useQPDF)
    }

    @MainActor
    func testPresetMediumApply() {
        let compressor = PDFCompressor()
        CompressionPreset.medium.apply(to: compressor)
        XCTAssertEqual(compressor.resolution, 140)
        XCTAssertTrue(compressor.forceJPEG)
        XCTAssertEqual(compressor.jpegQuality, 30)
        XCTAssertTrue(compressor.useGS)
        XCTAssertTrue(compressor.useQPDF)
    }

    @MainActor
    func testPresetHighApply() {
        let compressor = PDFCompressor()
        CompressionPreset.high.apply(to: compressor)
        XCTAssertEqual(compressor.resolution, 200)
        XCTAssertFalse(compressor.forceJPEG)
        XCTAssertEqual(compressor.jpegQuality, 50)
        XCTAssertTrue(compressor.useGS)
        XCTAssertTrue(compressor.useQPDF)
    }

    @MainActor
    func testPresetCustomApplyDoesNothing() {
        let compressor = PDFCompressor()
        compressor.resolution = 100
        CompressionPreset.custom.apply(to: compressor)
        XCTAssertEqual(compressor.resolution, 100)
    }

    // MARK: - CompressionPreset.matches Tests

    @MainActor
    func testPresetMatchesLow() {
        let compressor = PDFCompressor()
        CompressionPreset.low.apply(to: compressor)
        XCTAssertTrue(CompressionPreset.low.matches(compressor))
        XCTAssertFalse(CompressionPreset.medium.matches(compressor))
    }

    @MainActor
    func testPresetMatchesMediumDefault() {
        let compressor = PDFCompressor()
        // 默认值恰好匹配 medium
        XCTAssertTrue(CompressionPreset.medium.matches(compressor))
    }

    @MainActor
    func testPresetMatchesHigh() {
        let compressor = PDFCompressor()
        CompressionPreset.high.apply(to: compressor)
        XCTAssertTrue(CompressionPreset.high.matches(compressor))
        XCTAssertFalse(CompressionPreset.medium.matches(compressor))
    }

    @MainActor
    func testPresetCustomNeverMatches() {
        let compressor = PDFCompressor()
        XCTAssertFalse(CompressionPreset.custom.matches(compressor))
    }

    // MARK: - gsQFactor Tests (nonisolated, pure function; init requires MainActor)

    @MainActor
    func testGsQFactorLowQuality() {
        let compressor = PDFCompressor()
        // quality 1 → 50.0 (5000/1/100)
        XCTAssertEqual(compressor.gsQFactor(1), 50.0, accuracy: 0.01)
        // quality 25 → 2.0 (5000/25/100)
        XCTAssertEqual(compressor.gsQFactor(25), 2.0, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorMediumQuality() {
        let compressor = PDFCompressor()
        // quality 50 → 1.0 (200-100/100)
        XCTAssertEqual(compressor.gsQFactor(50), 1.0, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorHighQuality() {
        let compressor = PDFCompressor()
        // quality 75 → 0.5 (200-150/100)
        XCTAssertEqual(compressor.gsQFactor(75), 0.5, accuracy: 0.01)
        // quality 100 → 0.1 (minimum, 200-200=0 → clamped to 0.1)
        XCTAssertEqual(compressor.gsQFactor(100), 0.1, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorClamping() {
        let compressor = PDFCompressor()
        // quality 0 → clamped to 1 → 50.0
        XCTAssertEqual(compressor.gsQFactor(0), 50.0, accuracy: 0.01)
        // quality 200 → clamped to 100 → 0.1
        XCTAssertEqual(compressor.gsQFactor(200), 0.1, accuracy: 0.01)
    }

    // MARK: - gsProgressParser Tests (nonisolated, static)

    func testGsProgressParserPageCount() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 0)
        // 解析总页数，返回 nil
        XCTAssertNil(parser("Processing pages 1 through 10."))
        // 解析当前页，返回进度
        guard let result = parser("Page 1") else {
            XCTFail("Expected progress result for 'Page 1'")
            return
        }
        XCTAssertEqual(result.0, 0.15, accuracy: 0.01) // 0.1 + (1/10)*0.5 = 0.15
    }

    func testGsProgressParserPageProgress() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 5)
        guard let result = parser("Page 3") else {
            XCTFail("Expected progress result for 'Page 3'")
            return
        }
        XCTAssertEqual(result.0, 0.4, accuracy: 0.01) // 0.1 + (3/5)*0.5 = 0.4
    }

    func testGsProgressParserUnknownLine() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 10)
        XCTAssertNil(parser("Some random output"))
        XCTAssertNil(parser(""))
    }

    func testGsProgressParserPageWithKnownTotal() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 20)
        // 先解析总页数（覆盖初始值）
        XCTAssertNil(parser("Processing pages 1 through 20."))
        // 解析中间页
        guard let result = parser("Page 10") else {
            XCTFail("Expected progress result for 'Page 10'")
            return
        }
        XCTAssertEqual(result.0, 0.35, accuracy: 0.01) // 0.1 + (10/20)*0.5 = 0.35
    }

    // MARK: - formattedSize Tests (nonisolated; init requires MainActor)

    @MainActor
    func testFormattedSizeZeroReturnsUnknown() {
        let compressor = PDFCompressor()
        XCTAssertEqual(compressor.formattedSize(0), "未知")
    }

    @MainActor
    func testFormattedSizeNilReturnsUnknown() {
        let compressor = PDFCompressor()
        XCTAssertEqual(compressor.formattedSize(nil), "未知")
    }

    @MainActor
    func testFormattedSizePositiveValue() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(1024)
        XCTAssertNotEqual(result, "未知")
        XCTAssertTrue(result.contains("1") || result.contains("KB"))
    }

    @MainActor
    func testFormattedSizeLargeValue() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(1024 * 1024 * 5)
        XCTAssertNotEqual(result, "未知")
    }

    // MARK: - CompressError Tests

    func testCompressErrorNotFound() {
        let error = CompressError.notFound("test tool not found")
        XCTAssertEqual(error.errorDescription, "test tool not found")
    }

    func testCompressErrorProcessFailed() {
        let error = CompressError.processFailed("exit code 1")
        XCTAssertEqual(error.errorDescription, "exit code 1")
    }

    // MARK: - applyPreset / syncPresetSelection Tests

    @MainActor
    func testApplyPresetSkipsCustom() {
        let compressor = PDFCompressor()
        compressor.resolution = 99
        compressor.applyPreset(.custom)
        XCTAssertEqual(compressor.resolution, 99)
    }

    @MainActor
    func testSyncPresetSelectionMatchesMediumByDefault() {
        let compressor = PDFCompressor()
        // 默认值：resolution=140, forceJPEG=true, jpegQuality=30 → 匹配 medium
        compressor.syncPresetSelection()
        XCTAssertEqual(compressor.selectedPreset, .medium)
    }

    @MainActor
    func testSyncPresetSelectionCustomWhenNoMatch() {
        let compressor = PDFCompressor()
        compressor.resolution = 99
        compressor.syncPresetSelection()
        XCTAssertEqual(compressor.selectedPreset, .custom)
    }

    // MARK: - CompressionPreset.allCases Tests

    func testCompressionPresetAllCases() {
        let allCases = CompressionPreset.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.low))
        XCTAssertTrue(allCases.contains(.medium))
        XCTAssertTrue(allCases.contains(.high))
        XCTAssertTrue(allCases.contains(.custom))
    }

    func testCompressionPresetIdentifiable() {
        XCTAssertEqual(CompressionPreset.low.id, CompressionPreset.low.rawValue)
        XCTAssertEqual(CompressionPreset.medium.id, CompressionPreset.medium.rawValue)
    }
}