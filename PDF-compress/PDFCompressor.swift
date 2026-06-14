import Foundation
import AppKit
import Combine

@MainActor
class PDFCompressor: ObservableObject {
    @Published var inputURL: URL?
    @Published var inputSize: String?
    @Published var resolution: Double = 140
    @Published var useGS = true
    @Published var useQPDF = true
    @Published var forceJPEG = true
    @Published var jpegQuality: Double = 30
    @Published var isCompressing = false
    @Published var progress: Double = 0
    @Published var statusText = "准备就绪"
    @Published var result: CompressResult?
    @Published var missingTools: [String] = []
    @Published var isInstalling = false

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
            missingTools.append("ghostscript")
            statusText = "缺少 ghostscript，请先安装"
            return
        }
        if useQPDF && !qpdfAvailable {
            missingTools.append("qpdf")
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

                let gsOutput = self.tempDir.appendingPathComponent("gs_output.pdf")

                if shouldUseGS {
                    await self.updateProgress(0.1, "正在压缩（gs）…")
                    let gsPath = try await self.findExecutable("gs", path: envPATH)

                    let gsResult = try await self.runProcessWithOutput(
                        executable: gsPath,
                        arguments: self.gsArgs(input: input, output: gsOutput, resolution: resolution, forceJPEG: shouldForceJPEG, jpegQuality: shouldJpegQuality),
                        path: envPATH
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
                    await self.updateProgress(0.6, "gs 完成，正在线性化（qpdf）…")
                } else {
                    try FileManager.default.copyItem(at: input, to: gsOutput)
                    await self.updateProgress(0.6, "正在线性化（qpdf）…")
                }

                if shouldUseQPDF {
                    let qpdfOutput = self.tempDir.appendingPathComponent("qpdf_output.pdf")
                    let qpdfPath = try await self.findExecutable("qpdf", path: envPATH)

                    let qpdfResult = try await self.runProcessWithOutput(
                        executable: qpdfPath,
                        arguments: ["--linearize", gsOutput.path, qpdfOutput.path],
                        path: envPATH
                    )

                    if !qpdfResult.stderr.isEmpty {
                        print("[qpdf stderr] \(qpdfResult.stderr)")
                    }

                    if !FileManager.default.fileExists(atPath: qpdfOutput.path) {
                        throw CompressError.processFailed("qpdf 未生成输出文件。stderr: \(qpdfResult.stderr)")
                    }

                    try FileManager.default.removeItem(at: gsOutput)
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
                    try FileManager.default.moveItem(at: gsOutput, to: outputURL)
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

    struct ProcessResult {
        let stdout: String
        let stderr: String
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

    private func gsArgs(input: URL, output: URL, resolution: Int, forceJPEG: Bool, jpegQuality: Int) -> [String] {
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
            "-dQUIET",
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
    private func gsQFactor(_ quality: Int) -> Double {
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

    // MARK: - Helpers

    private func formattedSize(_ bytes: UInt64?) -> String {
        guard let bytes = bytes, bytes > 0 else { return "未知" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

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
