import XCTest
@testable import DocumentProcessor

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
        compressor.resolution = 99
        compressor.forceJPEG = false
        compressor.jpegQuality = 77
        CompressionPreset.custom.apply(to: compressor)
        XCTAssertEqual(compressor.resolution, 99)
        XCTAssertFalse(compressor.forceJPEG)
        XCTAssertEqual(compressor.jpegQuality, 77)
    }

    // MARK: - CompressionPreset.matches Tests

    @MainActor
    func testPresetMatchesLow() {
        let compressor = PDFCompressor()
        CompressionPreset.low.apply(to: compressor)
        XCTAssertTrue(CompressionPreset.low.matches(compressor))
        XCTAssertFalse(CompressionPreset.medium.matches(compressor))
        XCTAssertFalse(CompressionPreset.high.matches(compressor))
        XCTAssertFalse(CompressionPreset.custom.matches(compressor))
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

    @MainActor
    func testPresetMatchesPartialMismatch() {
        // resolution 对了但 forceJPEG 不对
        let compressor = PDFCompressor()
        compressor.resolution = 72
        compressor.forceJPEG = false // low 要求 true
        XCTAssertFalse(CompressionPreset.low.matches(compressor))
    }

    // MARK: - gsQFactor Tests

    @MainActor
    func testGsQFactorLowQuality() {
        let compressor = PDFCompressor()
        // quality 1 → 50.0 (5000/1/100)
        XCTAssertEqual(compressor.gsQFactor(1), 50.0, accuracy: 0.01)
        // quality 10 → 5.0 (5000/10/100)
        XCTAssertEqual(compressor.gsQFactor(10), 5.0, accuracy: 0.01)
        // quality 25 → 2.0 (5000/25/100)
        XCTAssertEqual(compressor.gsQFactor(25), 2.0, accuracy: 0.01)
        // quality 49 → ~1.02 (5000/49/100)
        XCTAssertEqual(compressor.gsQFactor(49), 1.02, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorBoundary50() {
        let compressor = PDFCompressor()
        // quality 50 是分界点，两个分支都应得到 1.0
        XCTAssertEqual(compressor.gsQFactor(50), 1.0, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorHighQuality() {
        let compressor = PDFCompressor()
        // quality 75 → 0.5 (200-150)/100
        XCTAssertEqual(compressor.gsQFactor(75), 0.5, accuracy: 0.01)
        // quality 90 → 0.2 (200-180)/100
        XCTAssertEqual(compressor.gsQFactor(90), 0.2, accuracy: 0.01)
        // quality 94 → 0.12 (200-188)/100
        XCTAssertEqual(compressor.gsQFactor(94), 0.12, accuracy: 0.01)
        // quality 95 → 0.1 (200-190)/100 = 0.1, 恰好等于下限
        XCTAssertEqual(compressor.gsQFactor(95), 0.1, accuracy: 0.01)
        // quality 99 → raw 0.02 被 max(0.1, ...) clamp 到 0.1
        XCTAssertEqual(compressor.gsQFactor(99), 0.1, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorMaxQualityClamped() {
        let compressor = PDFCompressor()
        // quality 100 → 0.0 clamped to 0.1
        XCTAssertEqual(compressor.gsQFactor(100), 0.1, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorClampingBelowMin() {
        let compressor = PDFCompressor()
        // quality 0 → clamped to 1 → 50.0
        XCTAssertEqual(compressor.gsQFactor(0), 50.0, accuracy: 0.01)
        // quality -10 → clamped to 1 → 50.0
        XCTAssertEqual(compressor.gsQFactor(-10), 50.0, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorClampingAboveMax() {
        let compressor = PDFCompressor()
        // quality 200 → clamped to 100 → 0.1
        XCTAssertEqual(compressor.gsQFactor(200), 0.1, accuracy: 0.01)
        // quality 999 → clamped to 100 → 0.1
        XCTAssertEqual(compressor.gsQFactor(999), 0.1, accuracy: 0.01)
    }

    @MainActor
    func testGsQFactorMonotonicallyNonIncreasing() {
        let compressor = PDFCompressor()
        // QFactor 应随 quality 单调不递增（0.1 下限 clamp 导致 quality ≥ 95 后值相同）
        var prev = compressor.gsQFactor(1)
        for q in 2...100 {
            let current = compressor.gsQFactor(q)
            XCTAssertLessThanOrEqual(current, prev + 0.001, "QFactor not non-increasing at quality=\(q)")
            prev = current
        }
        // 最终值应等于下限 0.1
        XCTAssertEqual(prev, 0.1, accuracy: 0.01)
    }

    // MARK: - gsProgressParser Tests

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
        XCTAssertNil(parser("Loading font..."))
    }

    func testGsProgressParserPageWithKnownTotal() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 20)
        XCTAssertNil(parser("Processing pages 1 through 20."))
        guard let result = parser("Page 10") else {
            XCTFail("Expected progress result for 'Page 10'")
            return
        }
        XCTAssertEqual(result.0, 0.35, accuracy: 0.01) // 0.1 + (10/20)*0.5 = 0.35
    }

    func testGsProgressParserTotalPagesOverride() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 5)
        // 先覆盖总页数
        XCTAssertNil(parser("Processing pages 1 through 100."))
        // 之后 Page 1 应该用新总数 100
        guard let result = parser("Page 1") else {
            XCTFail("Expected progress result")
            return
        }
        XCTAssertEqual(result.0, 0.105, accuracy: 0.01) // 0.1 + (1/100)*0.5 = 0.105
    }

    func testGsProgressParserLastPage() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 10)
        guard let result = parser("Page 10") else {
            XCTFail("Expected progress result")
            return
        }
        XCTAssertEqual(result.0, 0.6, accuracy: 0.01) // 0.1 + (10/10)*0.5 = 0.6
    }

    func testGsProgressParserStatusText() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 5)
        guard let result = parser("Page 2") else {
            XCTFail("Expected progress result")
            return
        }
        XCTAssertTrue(result.1.contains("2"))
        XCTAssertTrue(result.1.contains("5"))
    }

    func testGsProgressParserZeroTotalPages() {
        let parser = PDFCompressor.gsProgressParser(totalPages: 0)
        // totalPages=0 时，直接解析 "Page 1" 但 total 仍为 0，prog=0
        guard let result = parser("Page 1") else {
            XCTFail("Expected progress result")
            return
        }
        // 先解析 "Processing pages 1 through 10" 更新 total
        // 但这里没先解析，所以 total=0, prog=0, scaled=0.1
        XCTAssertEqual(result.0, 0.1, accuracy: 0.01)
    }

    // MARK: - formattedSize Tests

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
    func testFormattedSizeBytes() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(500)
        XCTAssertNotEqual(result, "未知")
        XCTAssertFalse(result.isEmpty)
    }

    @MainActor
    func testFormattedSizeKilobytes() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(1024)
        XCTAssertNotEqual(result, "未知")
    }

    @MainActor
    func testFormattedSizeMegabytes() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(1024 * 1024 * 5)
        XCTAssertNotEqual(result, "未知")
    }

    @MainActor
    func testFormattedSizeGigabytes() {
        let compressor = PDFCompressor()
        let result = compressor.formattedSize(UInt64(1024) * 1024 * 1024 * 2)
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

    func testCompressErrorEmptyMessage() {
        XCTAssertEqual(CompressError.notFound("").errorDescription, "")
        XCTAssertEqual(CompressError.processFailed("").errorDescription, "")
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
    func testApplyPresetLowOverwritesCustom() {
        let compressor = PDFCompressor()
        compressor.resolution = 200
        compressor.jpegQuality = 80
        compressor.applyPreset(.low)
        XCTAssertEqual(compressor.resolution, 72)
        XCTAssertEqual(compressor.jpegQuality, 20)
    }

    @MainActor
    func testSyncPresetSelectionMatchesMediumByDefault() {
        let compressor = PDFCompressor()
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

    @MainActor
    func testSyncPresetSelectionMatchesLowAfterApply() {
        let compressor = PDFCompressor()
        CompressionPreset.low.apply(to: compressor)
        compressor.syncPresetSelection()
        XCTAssertEqual(compressor.selectedPreset, .low)
    }

    @MainActor
    func testSyncPresetSelectionMatchesHighAfterApply() {
        let compressor = PDFCompressor()
        CompressionPreset.high.apply(to: compressor)
        compressor.syncPresetSelection()
        XCTAssertEqual(compressor.selectedPreset, .high)
    }

    // MARK: - CompressionPreset.allCases / Identifiable Tests

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
        XCTAssertEqual(CompressionPreset.high.id, CompressionPreset.high.rawValue)
        XCTAssertEqual(CompressionPreset.custom.id, CompressionPreset.custom.rawValue)
    }

    func testCompressionPresetRawValues() {
        XCTAssertEqual(CompressionPreset.low.rawValue, "低质量（最小体积）")
        XCTAssertEqual(CompressionPreset.medium.rawValue, "中质量（推荐）")
        XCTAssertEqual(CompressionPreset.high.rawValue, "高质量（保真）")
        XCTAssertEqual(CompressionPreset.custom.rawValue, "自定义")
    }

    // MARK: - gsArgs Tests

    @MainActor
    func testGsArgsForceJPEGTrueContainsDCTEncode() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: true, jpegQuality: 30)

        XCTAssertTrue(args.contains("-sColorImageFilter=DCTEncode"))
        XCTAssertTrue(args.contains("-sGrayImageFilter=DCTEncode"))
        XCTAssertTrue(args.contains("-dAutoFilterColorImages=false"))
        XCTAssertTrue(args.contains("-dAutoFilterGrayImages=false"))
        XCTAssertTrue(args.contains("-dPassThroughJPEGImages=false"))
    }

    @MainActor
    func testGsArgsForceJPEGFalseContainsAutoFilter() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 200, forceJPEG: false, jpegQuality: 50)

        XCTAssertTrue(args.contains("-dAutoFilterColorImages=true"))
        XCTAssertTrue(args.contains("-dAutoFilterGrayImages=true"))
        XCTAssertFalse(args.contains("-sColorImageFilter=DCTEncode"))
        XCTAssertFalse(args.contains("QFactor"))
    }

    @MainActor
    func testGsArgsResolutionApplied() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 72, forceJPEG: true, jpegQuality: 20)

        XCTAssertTrue(args.contains("-dColorImageResolution=72"))
        XCTAssertTrue(args.contains("-dGrayImageResolution=72"))
        XCTAssertTrue(args.contains("-dMonoImageResolution=72"))
    }

    @MainActor
    func testGsArgsThresholdForceJPEG() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")

        let argsJPEG = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: true, jpegQuality: 30)
        XCTAssertTrue(argsJPEG.contains("-dColorImageDownsampleThreshold=1.0"))
        XCTAssertTrue(argsJPEG.contains("-dGrayImageDownsampleThreshold=1.0"))
        XCTAssertTrue(argsJPEG.contains("-dMonoImageDownsampleThreshold=1.0"))

        let argsNoJPEG = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: false, jpegQuality: 30)
        XCTAssertTrue(argsNoJPEG.contains("-dColorImageDownsampleThreshold=1.2"))
        XCTAssertTrue(argsNoJPEG.contains("-dGrayImageDownsampleThreshold=1.2"))
        XCTAssertTrue(argsNoJPEG.contains("-dMonoImageDownsampleThreshold=1.2"))
    }

    @MainActor
    func testGsArgsForceJPEGContainsQFactor() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: true, jpegQuality: 30)

        // QFactor for quality 30 → 5000/30/100 ≈ 1.667
        let qFactor = compressor.gsQFactor(30)
        let qFactorStr = String(format: "QFactor %@", String(format: "%.2f", qFactor))
        XCTAssertTrue(args.contains { $0.contains("QFactor") }, "Args should contain QFactor when forceJPEG=true")
    }

    @MainActor
    func testGsArgsCommonParams() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: true, jpegQuality: 30)

        XCTAssertTrue(args.contains("-sDEVICE=pdfwrite"))
        XCTAssertTrue(args.contains("-dCompatibilityLevel=1.4"))
        XCTAssertTrue(args.contains("-dDetectDuplicateImages=true"))
        XCTAssertTrue(args.contains("-dCompressFonts=true"))
        XCTAssertTrue(args.contains("-dSubsetFonts=true"))
        XCTAssertTrue(args.contains("-dNOPAUSE"))
        XCTAssertTrue(args.contains("-dBATCH"))
    }

    @MainActor
    func testGsArgsOutputFile() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: true, jpegQuality: 30)

        XCTAssertTrue(args.contains("-sOutputFile=/tmp/out.pdf"))
    }

    @MainActor
    func testGsArgsForceJPEGFalseInputPath() {
        let compressor = PDFCompressor()
        let input = URL(fileURLWithPath: "/tmp/test.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")
        let args = compressor.gsArgs(input: input, output: output, resolution: 140, forceJPEG: false, jpegQuality: 50)

        // forceJPEG=false 时，input path 是最后一个参数
        XCTAssertTrue(args.last == "/tmp/test.pdf")
    }

    // MARK: - PDFCompressor Default Values Tests

    @MainActor
    func testDefaultValues() {
        let compressor = PDFCompressor()
        XCTAssertEqual(compressor.resolution, 140)
        XCTAssertEqual(compressor.jpegQuality, 30)
        XCTAssertTrue(compressor.useGS)
        XCTAssertTrue(compressor.useQPDF)
        XCTAssertTrue(compressor.forceJPEG)
        XCTAssertNil(compressor.inputURL)
        XCTAssertNil(compressor.inputSize)
        XCTAssertFalse(compressor.isCompressing)
        XCTAssertEqual(compressor.progress, 0)
        XCTAssertEqual(compressor.statusText, "准备就绪")
        XCTAssertNil(compressor.result)
        XCTAssertTrue(compressor.missingTools.isEmpty)
        XCTAssertFalse(compressor.isInstalling)
        XCTAssertTrue(compressor.inputURLs.isEmpty)
        XCTAssertTrue(compressor.batchResults.isEmpty)
        XCTAssertFalse(compressor.isBatchCompressing)
    }

    // MARK: - PDFCompressor Reset Tests

    @MainActor
    func testResetClearsInput() {
        let compressor = PDFCompressor()
        // 模拟加载状态
        compressor.statusText = "完成"
        compressor.isCompressing = true
        compressor.progress = 0.5
        compressor.reset()

        XCTAssertNil(compressor.inputURL)
        XCTAssertNil(compressor.inputSize)
        XCTAssertNil(compressor.result)
        XCTAssertEqual(compressor.progress, 0)
        XCTAssertFalse(compressor.isCompressing)
        XCTAssertEqual(compressor.statusText, "准备就绪")
    }

    // MARK: - Batch Operations Tests

    @MainActor
    func testAddInputURLsDeduplicates() {
        let compressor = PDFCompressor()
        let url1 = URL(fileURLWithPath: "/tmp/test1.pdf")
        let url2 = URL(fileURLWithPath: "/tmp/test2.pdf")

        compressor.addInputURLs([url1, url2])
        XCTAssertEqual(compressor.inputURLs.count, 2)

        // 添加重复的 url1
        compressor.addInputURLs([url1])
        XCTAssertEqual(compressor.inputURLs.count, 2)
    }

    @MainActor
    func testClearBatch() {
        let compressor = PDFCompressor()
        compressor.addInputURLs([URL(fileURLWithPath: "/tmp/test1.pdf")])
        compressor.batchResults = [PDFCompressor.BatchResult(
            inputURL: URL(fileURLWithPath: "/tmp/test1.pdf"),
            outputURL: nil, originalSize: "1 MB", finalSize: "500 KB",
            compressionRatio: "50%", success: true, message: "完成"
        )]
        compressor.currentBatchIndex = 1
        compressor.batchProgress = 0.5

        compressor.clearBatch()

        XCTAssertTrue(compressor.inputURLs.isEmpty)
        XCTAssertTrue(compressor.batchResults.isEmpty)
        XCTAssertEqual(compressor.currentBatchIndex, 0)
        XCTAssertEqual(compressor.batchProgress, 0)
    }

    // MARK: - BatchResult Tests

    func testBatchResultSuccess() {
        let result = PDFCompressor.BatchResult(
            inputURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/a.compressed.pdf"),
            originalSize: "1 MB", finalSize: "500 KB",
            compressionRatio: "50%", success: true, message: "完成"
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.message, "完成")
        XCTAssertNotNil(result.outputURL)
    }

    func testBatchResultFailure() {
        let result = PDFCompressor.BatchResult(
            inputURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            outputURL: nil, originalSize: "—", finalSize: "—",
            compressionRatio: "—", success: false, message: "gs 失败"
        )
        XCTAssertFalse(result.success)
        XCTAssertNil(result.outputURL)
        XCTAssertEqual(result.message, "gs 失败")
    }

    // MARK: - CompressResult Tests

    @MainActor
    func testCompressResult() {
        let url = URL(fileURLWithPath: "/tmp/out.pdf")
        let result = PDFCompressor.CompressResult(
            outputURL: url, finalSize: "500 KB", compressionRatio: "50%"
        )
        XCTAssertEqual(result.outputURL, url)
        XCTAssertEqual(result.finalSize, "500 KB")
        XCTAssertEqual(result.compressionRatio, "50%")
    }
}
