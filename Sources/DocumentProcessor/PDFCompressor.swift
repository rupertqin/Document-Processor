import Foundation
import AppKit
import Combine

// MARK: - Compression Presets

enum CompressionPreset: String, CaseIterable, Identifiable {
    case low = "低质量（最小体积）"
    case medium = "中质量（推荐）"
    case high = "高质量（保真）"
    case custom = "自定义"
    
    var id: String { rawValue }
    
    /// 应用到 PDFCompressor 的参数
    @MainActor
    func apply(to compressor: PDFCompressor) {
        switch self {
        case .low:
            compressor.resolution = 72
            compressor.forceJPEG = true
            compressor.jpegQuality = 20
            compressor.useGS = true
            compressor.useQPDF = true
        case .medium:
            compressor.resolution = 140
            compressor.forceJPEG = true
            compressor.jpegQuality = 30
            compressor.useGS = true
            compressor.useQPDF = true
        case .high:
            compressor.resolution = 200
            compressor.forceJPEG = false
            compressor.jpegQuality = 50
            compressor.useGS = true
            compressor.useQPDF = true
        case .custom:
            break
        }
    }
    
    /// 判断给定的压缩机参数是否匹配当前预设
    @MainActor
    func matches(_ compressor: PDFCompressor) -> Bool {
        switch self {
        case .low:
            return compressor.resolution == 72
                && compressor.forceJPEG == true
                && compressor.jpegQuality == 20
                && compressor.useGS == true
                && compressor.useQPDF == true
        case .medium:
            return compressor.resolution == 140
                && compressor.forceJPEG == true
                && compressor.jpegQuality == 30
                && compressor.useGS == true
                && compressor.useQPDF == true
        case .high:
            return compressor.resolution == 200
                && compressor.forceJPEG == false
                && compressor.jpegQuality == 50
                && compressor.useGS == true
                && compressor.useQPDF == true
        case .custom:
            return false
        }
    }
}

@MainActor
class PDFCompressor: ObservableObject {
    @Published var inputURL: URL?
    @Published var inputSize: String?
    @Published var isCompressing = false
    @Published var progress: Double = 0
    @Published var statusText = "准备就绪"
    @Published var result: CompressResult?
    @Published var missingTools: [String] = []
    @Published var isInstalling = false
    
    // MARK: - Batch Compression
    
    @Published var inputURLs: [URL] = []
    @Published var batchResults: [BatchResult] = []
    @Published var isBatchCompressing = false
    @Published var currentBatchIndex: Int = 0
    @Published var batchProgress: Double = 0
    
    struct BatchResult {
        let inputURL: URL
        let outputURL: URL?
        let originalSize: String
        let finalSize: String
        let compressionRatio: String
        let success: Bool
        let message: String
    }
    
    // MARK: - Compression Preset

    @Published var selectedPreset: CompressionPreset = .custom

    /// 标记当前是否正在应用预设，防止参数 onChange 触发 syncPresetSelection 造成循环
    private var isApplyingPreset = false

    /// 应用预设参数（由视图层 .onChange 调用）
    func applyPreset(_ preset: CompressionPreset) {
        guard preset != .custom else { return }
        isApplyingPreset = true
        preset.apply(to: self)
        // 延迟重置标志，确保参数的 .onChange 不会误触发 syncPresetSelection
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingPreset = false
        }
    }

    /// 根据当前各项参数同步更新 selectedPreset（由视图层参数 .onChange 调用）
    func syncPresetSelection() {
        guard !isApplyingPreset else { return }
        for preset in CompressionPreset.allCases where preset != .custom {
            if preset.matches(self) {
                if selectedPreset != preset {
                    selectedPreset = preset
                }
                return
            }
        }
        if selectedPreset != .custom {
            selectedPreset = .custom
        }
    }

    @Published var resolution: Double = 140
    @Published var useGS = true
    @Published var useQPDF = true
    @Published var forceJPEG = true
    @Published var jpegQuality: Double = 30

    struct CompressResult {
        let outputURL: URL
        let finalSize: String
        let compressionRatio: String
    }

    private let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pdfcompressor", isDirectory: true)

    /// 常见 Homebrew 路径，GUI 应用不继承 shell PATH
    private let brewPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    /// 构建含 Homebrew 路径的 PATH
    private var expandedPATH: String {
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let allPaths = brewPaths + existing.split(separator: ":").map(String.init)
        let unique = Array(NSOrderedSet(array: allPaths)) as! [String]
        return unique.joined(separator: ":")
    }

    // MARK: - Tool Detection

    func checkTools() {
        var missing: [String] = []
        if findExecutablePath("gs") == nil { missing.append("ghostscript") }
        if findExecutablePath("qpdf") == nil { missing.append("qpdf") }
        missingTools = missing
    }

    private nonisolated func findExecutablePath(_ name: String) -> String? {
        for dir in brewPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    func installMissingTools() {
        guard !missingTools.isEmpty else { return }
        isInstalling = true
        statusText = "正在安装 \(missingTools.joined(separator: " 和 "))…"

        let packages = missingTools
        let envPATH = expandedPATH

        Task.detached { [weak self] in
            guard let self else { return }

            // 用 brew 安装缺失的工具
            let brewPath = self.findExecutablePath("brew") ?? "/opt/homebrew/bin/brew"
            do {
                let result = try await self.runProcessWithOutput(
                    executable: URL(fileURLWithPath: brewPath),
                    arguments: ["install"] + packages,
                    path: envPATH
                )
                print("[brew install] stdout: \(result.stdout)")
                if !result.stderr.isEmpty {
                    print("[brew install] stderr: \(result.stderr)")
                }
            } catch {
                await self.installFailed("安装失败: \(error.localizedDescription)")
                return
            }

            // 重新检测
            var stillMissing: [String] = []
            if self.findExecutablePath("gs") == nil { stillMissing.append("ghostscript") }
            if self.findExecutablePath("qpdf") == nil { stillMissing.append("qpdf") }

            await self.installComplete(stillMissing: stillMissing)
        }
    }

    @MainActor
    private func installComplete(stillMissing: [String]) {
        isInstalling = false
        missingTools = stillMissing
        if stillMissing.isEmpty {
            statusText = "安装完成 ✓ 准备就绪"
        } else {
            statusText = "安装后仍缺少: \(stillMissing.joined(separator: ", "))"
        }
    }

    @MainActor
    private func installFailed(_ message: String) {
        isInstalling = false
        statusText = message
    }

    // MARK: - Load / Reset

    func load(_ url: URL) {
        inputURL = url
        inputSize = formattedSize(try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0)
        resetState()
        checkTools()
    }

    func reset() {
        inputURL = nil
        inputSize = nil
        resetState()
    }

    private func resetState() {
        result = nil
        progress = 0
        isCompressing = false
        statusText = "准备就绪"
    }

    // MARK: - Compress

    func compress() {
        guard let input = inputURL else { return }

        // 再次确认工具可用
        checkTools()
        let gsAvailable = findExecutablePath("gs") != nil
        let qpdfAvailable = findExecutablePath("qpdf") != nil

        if useGS && !gsAvailable {
            if !missingTools.contains("ghostscript") { missingTools.append("ghostscript") }
            statusText = "缺少 ghostscript，请先安装"
            return
        }
        if useQPDF && !qpdfAvailable {
            if !missingTools.contains("qpdf") { missingTools.append("qpdf") }
            statusText = "缺少 qpdf，请先安装"
            return
        }

        result = nil
        isCompressing = true
        progress = 0
        statusText = "准备中…"

        let outputURL = input.deletingLastPathComponent()
            .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent).compressed.pdf")
        let inputSize = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? UInt64) ?? 0

        let shouldUseGS = useGS
        let shouldUseQPDF = useQPDF
        let shouldForceJPEG = forceJPEG
        let shouldJpegQuality = Int(jpegQuality)
        let envPATH = expandedPATH
        let resolution = Int(self.resolution)

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                // 清理旧临时文件
                try? FileManager.default.removeItem(at: self.tempDir)
                try FileManager.default.createDirectory(at: self.tempDir, withIntermediateDirectories: true)

                // 先将原文件复制到临时目录，后续操作全部在临时目录内进行，绝不移动/删除原文件
                let workingInput = self.tempDir.appendingPathComponent("working_input.pdf")
                try FileManager.default.copyItem(at: input, to: workingInput)
                var currentInput = workingInput

                // Step 1: qpdf 前置修复与解密 — 消除隐藏加密、修复结构错误，给 GS 一个干净的输入
                if shouldUseQPDF {
                    await self.updateProgress(0.05, "正在修复与解密（qpdf）…")
                    let sanitized = self.tempDir.appendingPathComponent("sanitized.pdf")
                    let qpdfPath = try await self.findExecutable("qpdf", path: envPATH)

                    let sanitizeResult = try await self.runProcessWithOutput(
                        executable: qpdfPath,
                        arguments: ["--decrypt", currentInput.path, sanitized.path],
                        path: envPATH
                    )
                    if !sanitizeResult.stderr.isEmpty {
                        print("[qpdf --decrypt stderr] \(sanitizeResult.stderr)")
                    }
                    if FileManager.default.fileExists(atPath: sanitized.path) {
                        currentInput = sanitized
                        print("[qpdf --decrypt] 修复完成，使用 sanitized 作为后续输入")
                    } else {
                        print("[qpdf --decrypt] 未生成输出，使用原始输入继续")
                    }
                }

                // Step 2: Ghostscript 压缩
                let gsOutput = self.tempDir.appendingPathComponent("gs_output.pdf")

                if shouldUseGS {
                    await self.updateProgress(0.1, "正在压缩（gs）…")
                    let gsPath = try await self.findExecutable("gs", path: envPATH)

                    let gsResult = try await self.runProcessWithProgress(
                        executable: gsPath,
                        arguments: self.gsArgs(input: currentInput, output: gsOutput, resolution: resolution, forceJPEG: shouldForceJPEG, jpegQuality: shouldJpegQuality),
                        path: envPATH,
                        progressParser: PDFCompressor.gsProgressParser(totalPages: 0)
                    )

                    if !gsResult.stderr.isEmpty {
                        print("[gs stderr] \(gsResult.stderr)")
                    }

                    // 验证 gs 输出文件
                    if !FileManager.default.fileExists(atPath: gsOutput.path) {
                        throw CompressError.processFailed("gs 未生成输出文件。stderr: \(gsResult.stderr)")
                    }
                    let gsSize = (try? FileManager.default.attributesOfItem(atPath: gsOutput.path)[.size] as? UInt64) ?? 0
                    if gsSize == 0 {
                        throw CompressError.processFailed("gs 输出文件为空。stderr: \(gsResult.stderr)")
                    }

                    print("[gs] 输入: \(inputSize) bytes → 输出: \(gsSize) bytes")
                    currentInput = gsOutput
                    await self.updateProgress(0.6, "gs 完成，正在线性化（qpdf）…")
                } else {
                    // 不用 GS 时，currentInput 保持不变（可能是 sanitized.pdf 或原始 input）
                    await self.updateProgress(0.6, "正在线性化（qpdf）…")
                }

                // Step 3: qpdf 线性化（优化流式加载）
                if shouldUseQPDF {
                    let qpdfOutput = self.tempDir.appendingPathComponent("qpdf_output.pdf")
                    let qpdfPath = try await self.findExecutable("qpdf", path: envPATH)

                    let qpdfResult = try await self.runProcessWithOutput(
                        executable: qpdfPath,
                        arguments: ["--linearize", currentInput.path, qpdfOutput.path],
                        path: envPATH
                    )

                    if !qpdfResult.stderr.isEmpty {
                        print("[qpdf stderr] \(qpdfResult.stderr)")
                    }

                    if !FileManager.default.fileExists(atPath: qpdfOutput.path) {
                        throw CompressError.processFailed("qpdf 未生成输出文件。stderr: \(qpdfResult.stderr)")
                    }

                    try? FileManager.default.removeItem(at: gsOutput)
                    await self.updateProgress(0.9, "写入结果…")

                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    try FileManager.default.moveItem(at: qpdfOutput, to: outputURL)
                } else {
                    await self.updateProgress(0.9, "写入结果…")
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    try FileManager.default.moveItem(at: currentInput, to: outputURL)
                }

                try? FileManager.default.removeItem(at: self.tempDir)

                let finalSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0

                // 防劣化防线：压缩后反而变大则保留原文件
                if finalSize > inputSize && inputSize > 0 {
                    print("[防劣化] 压缩后文件反而变大 (\(finalSize) > \(inputSize))，保留原文件")
                    try? FileManager.default.removeItem(at: outputURL)
                    try FileManager.default.copyItem(at: input, to: outputURL)
                    let ratio = "100.0% (防劣化)"
                    await self.finish(outputURL: outputURL, finalSize: inputSize, inputSize: inputSize, ratio: ratio)
                } else {
                    let ratio = inputSize > 0 ? String(format: "%.1f%%", Double(finalSize) / Double(inputSize) * 100) : "—"
                    print("[result] 输入: \(inputSize) bytes → 输出: \(finalSize) bytes (\(ratio))")
                    await self.finish(outputURL: outputURL, finalSize: finalSize, inputSize: inputSize, ratio: ratio)
                }
            } catch {
                try? FileManager.default.removeItem(at: self.tempDir)
                await self.fail(error)
            }
        }
    }

    // MARK: - Process Runner (non-blocking, captures stderr)

    /// 运行外部进程，并实时解析 stderr 进度（支持 Ghostscript 页码进度）
    /// - Parameter progressParser: 解析 stderr 每一行，返回 (进度 0.0-1.0, 状态文本)，无法识别则返回 nil
    private func runProcessWithProgress(
        executable: URL,
        arguments: [String],
        path: String,
        progressParser: (@Sendable (String) -> (Double, String)?)? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ["PATH": path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let errHandle = errPipe.fileHandleForReading
            let outHandle = outPipe.fileHandleForReading

            let stderrLines = StderrBuffer()

            // 实时读取 stderr
            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stderrLines.append(chunk)
                if let parser = progressParser {
                    for line in chunk.components(separatedBy: "\n") where !line.isEmpty {
                        if let (prog, text) = parser(line) {
                            Task { @MainActor in
                                self.progress = prog
                                self.statusText = text
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                errHandle.readabilityHandler = nil
                outHandle.readabilityHandler = nil

                let outData = outHandle.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: ProcessResult(stdout: stdout, stderr: stderrLines.value))
                } else {
                    continuation.resume(throwing: CompressError.processFailed(
                        "\(executable.lastPathComponent) 退出码: \(proc.terminationStatus)\n\(stderrLines.value)"
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    struct ProcessResult {
        let stdout: String
        let stderr: String
    }

    /// Ghostscript stderr 进度解析器
    /// 解析 "Processing pages 1 through N" 获取总页数，解析 "Page M" 获取当前进度
    nonisolated static func gsProgressParser(totalPages: Int) -> @Sendable (String) -> (Double, String)? {
        let state = ProgressParserState()
        state.total = totalPages
        let pagesRegex = try? NSRegularExpression(pattern: "Processing pages \\d+ through (\\d+)")
        return { line in
            // 解析总页数："Processing pages 1 through 10."
            if line.contains("Processing pages") {
                if let regex = pagesRegex,
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    state.total = Int(line[range]) ?? state.total
                }
                return nil
            }
            // 解析当前页："Page 1"
            if line.hasPrefix("Page ") {
                let numStr = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let num = Int(numStr) {
                    state.current = num
                }
                let total = state.total
                let current = state.current
                let prog = total > 0 ? Double(current) / Double(total) : 0
                let scaled = 0.1 + prog * 0.5  // gs 阶段占 0.1~0.6
                return (scaled, "正在压缩（gs）… 第 \(current)/\(total) 页")
            }
            return nil
        }
    }

    private func runProcessWithOutput(executable: URL, arguments: [String], path: String) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ["PATH": path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { _ in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: ProcessResult(stdout: stdout, stderr: stderr))
                } else {
                    continuation.resume(throwing: CompressError.processFailed(
                        "\(executable.lastPathComponent) 退出码: \(process.terminationStatus)\n\(stderr)"
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Ghostscript args

    nonisolated func gsArgs(input: URL, output: URL, resolution: Int, forceJPEG: Bool, jpegQuality: Int) -> [String] {
        var args = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=/default",
            // Average 降噪 + Threshold 1.2 避免无意义重压
            // forceJPEG 时 Threshold=1.0 强制重压，否则 1.2 避免无意义重压
            "-dDownsampleColorImages=true",
            "-dColorImageDownsampleType=/Average",
            "-dColorImageDownsampleThreshold=\(forceJPEG ? "1.0" : "1.2")",
            "-dColorImageResolution=\(resolution)",
            "-dDownsampleGrayImages=true",
            "-dGrayImageDownsampleType=/Average",
            "-dGrayImageDownsampleThreshold=\(forceJPEG ? "1.0" : "1.2")",
            "-dGrayImageResolution=\(resolution)",
            "-dDownsampleMonoImages=true",
            "-dMonoImageDownsampleType=/Subsample",
            "-dMonoImageDownsampleThreshold=\(forceJPEG ? "1.0" : "1.2")",
            "-dMonoImageResolution=\(resolution)",
            "-dDetectDuplicateImages=true",
            "-dCompressPages=true",
        ]
        if forceJPEG {
            args += [
                "-dPassThroughJPEGImages=false",
                "-dAutoFilterColorImages=false",
                "-sColorImageFilter=DCTEncode",
                "-dAutoFilterGrayImages=false",
                "-sGrayImageFilter=DCTEncode",
            ]
        } else {
            args += [
                "-dAutoFilterColorImages=true",
                "-dAutoFilterGrayImages=true",
            ]
        }
        args += [
            "-dCompressFonts=true",
            "-dSubsetFonts=true",
            "-dNOPAUSE",
            "-dNOPROMPT",
            "-dBATCH",
            "-sOutputFile=\(output.path)",
        ]
        if forceJPEG {
            let qFactor = gsQFactor(jpegQuality)
            let dictStr = "<< /ColorImageDict << /QFactor \(qFactor) >> /GrayImageDict << /QFactor \(qFactor) >> >> setdistillerparams"
            args += ["-c", dictStr, "-f", input.path]
            print("[gs args] forceJPEG=\(forceJPEG), jpegQuality=\(jpegQuality) (QFactor: \(qFactor)), resolution=\(resolution)")
        } else {
            args += [input.path]
            print("[gs args] forceJPEG=\(forceJPEG), resolution=\(resolution)")
        }
        return args
    }

    /// JPEGQ (0-100) → Ghostscript QFactor (IJG 标准非线性映射)
    /// quality 1 → 50.0 (极低), quality 50 → 1.0 (中等), quality 100 → 0.1 (极高)
    nonisolated func gsQFactor(_ quality: Int) -> Double {
        let q = max(1, min(100, quality))
        let scale: Double
        if q < 50 {
            scale = 5000.0 / Double(q)
        } else {
            scale = 200.0 - Double(q * 2)
        }
        return max(0.1, scale / 100.0)
    }

    // MARK: - Find Executable

    private func findExecutable(_ name: String, path: String) async throws -> URL {
        // 先在 Homebrew 常见路径直接查找
        if let found = findExecutablePath(name) {
            print("[find] \(name) → \(found)")
            return URL(fileURLWithPath: found)
        }

        // 兜底：用 which 查找
        let result = try await runProcessWithOutput(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", name],
            path: path
        )
        let found = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !found.isEmpty else {
            throw CompressError.notFound("未找到 \(name)，请先安装: brew install \(name == "gs" ? "ghostscript" : "qpdf")")
        }
        print("[find] \(name) → \(found)")
        return URL(fileURLWithPath: found)
    }

    // MARK: - UI Updates (must be on MainActor)

    @MainActor
    private func updateProgress(_ value: Double, _ text: String) {
        progress = value
        statusText = text
    }

    @MainActor
    private func finish(outputURL: URL, finalSize: UInt64, inputSize: UInt64, ratio: String) {
        progress = 1.0
        statusText = "完成 ✓ (压缩至 \(ratio))"
        result = CompressResult(
            outputURL: outputURL,
            finalSize: formattedSize(finalSize),
            compressionRatio: ratio
        )
        isCompressing = false
    }

    @MainActor
    private func fail(_ error: Error) {
        statusText = "失败: \(error.localizedDescription)"
        isCompressing = false
        print("[error] \(error.localizedDescription)")
    }

    // MARK: - Batch Compression

    /// 添加文件到批量压缩队列（自动去重）
    func addInputURLs(_ urls: [URL]) {
        let existing = Set(inputURLs.map { $0.path })
        let new = urls.filter { !existing.contains($0.path) }
        guard !new.isEmpty else { return }
        inputURLs.append(contentsOf: new)
        if inputURL == nil, let first = inputURLs.first {
            load(first)   // 自动加载第一个文件到预览
        }
        checkTools()
    }

    /// 清空批量队列
    func clearBatch() {
        inputURLs.removeAll()
        batchResults.removeAll()
        currentBatchIndex = 0
        batchProgress = 0
    }

    /// 开始批量压缩
    func compressBatch() {
        guard !inputURLs.isEmpty, !isBatchCompressing else { return }
        isBatchCompressing = true
        currentBatchIndex = 0
        batchProgress = 0
        batchResults.removeAll()
        statusText = "准备批量压缩…"

        Task.detached { [weak self] in
            guard let self else { return }
            await self.runBatch()
        }
    }

    private func runBatch() async {
        let envPATH = expandedPATH
        let shouldUseGS = useGS && findExecutablePath("gs") != nil
        let shouldUseQPDF = useQPDF && findExecutablePath("qpdf") != nil
        let shouldForceJPEG = forceJPEG
        let shouldJpegQuality = Int(jpegQuality)
        let resolution = Int(self.resolution)

        for (idx, input) in inputURLs.enumerated() {
            await MainActor.run {
                self.currentBatchIndex = idx
                self.batchProgress = Double(idx) / Double(self.inputURLs.count)
                self.statusText = "批量压缩中 (\(idx+1)/\(self.inputURLs.count))…"
            }

            let outputURL = input.deletingLastPathComponent()
                .appendingPathComponent("\(input.deletingPathExtension().lastPathComponent).compressed.pdf")

            do {
                // 清理临时目录
                try? FileManager.default.removeItem(at: tempDir)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                // 先将原文件复制到临时目录，绝不移动/删除原文件
                let workingInput = tempDir.appendingPathComponent("working_input.pdf")
                try FileManager.default.copyItem(at: input, to: workingInput)
                var currentInput = workingInput

                // Step 1: qpdf 前置修复与解密
                if shouldUseQPDF {
                    await MainActor.run { self.statusText = "批量压缩中 (\(idx+1)/\(self.inputURLs.count)) 修复解密…" }
                    let sanitized = tempDir.appendingPathComponent("sanitized.pdf")
                    let qpdfPath = try await findExecutable("qpdf", path: envPATH)
                    _ = try await runProcessWithOutput(
                        executable: qpdfPath,
                        arguments: ["--decrypt", currentInput.path, sanitized.path],
                        path: envPATH
                    )
                    if FileManager.default.fileExists(atPath: sanitized.path) {
                        currentInput = sanitized
                    }
                }

                // Step 2: GS 压缩
                let gsOutput = tempDir.appendingPathComponent("gs_output.pdf")

                if shouldUseGS {
                    await MainActor.run { self.statusText = "批量压缩中 (\(idx+1)/\(self.inputURLs.count)) gs…" }
                    let gsPath = try await findExecutable("gs", path: envPATH)
                    _ = try await runProcessWithProgress(
                        executable: gsPath,
                        arguments: gsArgs(input: currentInput, output: gsOutput, resolution: resolution, forceJPEG: shouldForceJPEG, jpegQuality: shouldJpegQuality),
                        path: envPATH,
                        progressParser: PDFCompressor.gsProgressParser(totalPages: 0)
                    )
                    guard FileManager.default.fileExists(atPath: gsOutput.path),
                          (try? FileManager.default.attributesOfItem(atPath: gsOutput.path)[.size] as? UInt64) ?? 0 > 0 else {
                        throw CompressError.processFailed("gs 未生成有效输出")
                    }
                    currentInput = gsOutput
                }

                // Step 3: qpdf 线性化
                let finalOutput: URL
                if shouldUseQPDF {
                    await MainActor.run { self.statusText = "批量压缩中 (\(idx+1)/\(self.inputURLs.count)) qpdf…" }
                    let qpdfOutput = tempDir.appendingPathComponent("qpdf_output.pdf")
                    let qpdfPath = try await findExecutable("qpdf", path: envPATH)
                    _ = try await runProcessWithProgress(
                        executable: qpdfPath,
                        arguments: ["--linearize", currentInput.path, qpdfOutput.path],
                        path: envPATH
                    )
                    guard FileManager.default.fileExists(atPath: qpdfOutput.path) else {
                        throw CompressError.processFailed("qpdf 未生成有效输出")
                    }
                    finalOutput = qpdfOutput
                } else {
                    finalOutput = currentInput
                }

                // 写入结果（含防劣化保护）
                let inputSize = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? UInt64) ?? 0

                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: finalOutput, to: outputURL)
                try? FileManager.default.removeItem(at: tempDir)

                // 防劣化：压缩后反而变大则替换为原文件
                let finalSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
                if finalSize > inputSize && inputSize > 0 {
                    try? FileManager.default.removeItem(at: outputURL)
                    try FileManager.default.copyItem(at: input, to: outputURL)
                }

                let actualSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
                let ratio = inputSize > 0 ? String(format: "%.1f%%", Double(actualSize) / Double(inputSize) * 100) : "—"

                await MainActor.run {
                    self.batchResults.append(BatchResult(
                        inputURL: input, outputURL: outputURL,
                        originalSize: self.formattedSize(inputSize),
                        finalSize: self.formattedSize(actualSize),
                        compressionRatio: ratio, success: true, message: "完成"
                    ))
                }

            } catch {
                await MainActor.run {
                    self.batchResults.append(BatchResult(
                        inputURL: input, outputURL: input,
                        originalSize: "—", finalSize: "—",
                        compressionRatio: "—", success: false,
                        message: error.localizedDescription
                    ))
                }
            }
        }

        await MainActor.run {
            self.isBatchCompressing = false
            self.batchProgress = 1.0
            let ok = self.batchResults.filter { $0.success }.count
            self.statusText = "批量完成（\(ok)/\(self.inputURLs.count) 成功）"
        }
    }

    // MARK: - Helpers

    nonisolated func formattedSize(_ bytes: UInt64?) -> String {
        guard let bytes = bytes, bytes > 0 else { return "未知" }
        return _sizeFormatter.string(fromByteCount: Int64(bytes))
    }
}

/// Thread-safe shared ByteCountFormatter (outside MainActor class)
private let _sizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

extension ByteCountFormatter: @unchecked Sendable {}

enum CompressError: LocalizedError {
    case notFound(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let msg): return msg
        case .processFailed(let msg): return msg
        }
    }
}

/// Thread-safe stderr accumulator for Process callbacks
private final class StderrBuffer: @unchecked Sendable {
    private var content = ""
    private let lock = NSLock()

    func append(_ string: String) {
        lock.lock()
        content += string
        lock.unlock()
    }

    var value: String {
        lock.lock()
        let result = content
        lock.unlock()
        return result
    }
}

/// Thread-safe state for progress parser (captured by @Sendable closure)
private final class ProgressParserState: @unchecked Sendable {
    var total: Int = 0
    var current: Int = 0
}
