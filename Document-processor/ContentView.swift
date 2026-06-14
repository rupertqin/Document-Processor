import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressor = PDFCompressor()

    @State private var isTargeted = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // 拖拽区域
            dropZone
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // 缺失工具提示
            if !compressor.missingTools.isEmpty {
                missingToolsBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 选项
            if compressor.missingTools.isEmpty {
                optionsPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 批量队列
            if !compressor.inputURLs.isEmpty {
                batchFileList
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            // 底部
            bottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 360)
        // 预设联动：选择预设 → 应用参数
        .onChange(of: compressor.selectedPreset) { _, newValue in
            compressor.applyPreset(newValue)
        }
        // 预设联动：手动调参 → 同步预设标签
        .onChange(of: compressor.resolution) { _, _ in compressor.syncPresetSelection() }
        .onChange(of: compressor.useGS) { _, _ in compressor.syncPresetSelection() }
        .onChange(of: compressor.useQPDF) { _, _ in compressor.syncPresetSelection() }
        .onChange(of: compressor.forceJPEG) { _, _ in compressor.syncPresetSelection() }
        .onChange(of: compressor.jpegQuality) { _, _ in compressor.syncPresetSelection() }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            // 离开当前视图周期再修改状态，避免 Publishing changes 错误
            DispatchQueue.main.async {
                if urls.count == 1 {
                    compressor.load(urls[0])
                } else {
                    compressor.addInputURLs(urls)
                }
            }
        }
    }

    // MARK: - Missing Tools Banner

    private var missingToolsBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("缺少必要工具: \(compressor.missingTools.joined(separator: ", "))")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }

            HStack {
                Text("Ghostscript 和 qpdf 可通过 Homebrew 安装")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()

                if compressor.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text("安装中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Button("一键安装") {
                        compressor.installMissingTools()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("手动安装") {
                        let script = "tell application \"Terminal\"\nactivate\ndo script \"brew install ghostscript qpdf\"\nend tell"
                        if let appleScript = NSAppleScript(source: script) {
                            appleScript.executeAndReturnError(nil)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundColor(isTargeted || compressor.inputURL == nil ? .accentColor : .secondary.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .frame(height: 140)

            if let url = compressor.inputURL {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = compressor.inputSize {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    Text("拖拽 PDF 文件到此处")
                        .font(.headline)
                    Text("或点击选择文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("选择文件…") { showFilePicker = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()

            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    defer { group.leave() }
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       url.pathExtension.lowercased() == "pdf" {
                        urls.append(url)
                    }
                }
            }

            group.notify(queue: .main) {
                guard !urls.isEmpty else { return }
                // 用 async 确保完全离开当前视图更新周期
                DispatchQueue.main.async {
                    if urls.count == 1 {
                        compressor.load(urls[0])
                    } else {
                        compressor.addInputURLs(urls)
                    }
                }
            }

            return true
        }
        .onTapGesture {
            if compressor.inputURL == nil { showFilePicker = true }
        }
    }

    // MARK: - Options

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("快速预设")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $compressor.selectedPreset) {
                ForEach(CompressionPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 30)
        }
    }

    private var optionsPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("压缩选项")
                    .font(.headline)
                Spacer()
            }

            presetPicker

            HStack(spacing: 16) {
                // 分辨率
                VStack(alignment: .leading, spacing: 4) {
                    Text("图片分辨率 (DPI): \(Int(compressor.resolution))")
                        .font(.caption)
                    Slider(value: $compressor.resolution, in: 50...300, step: 10)
                        .frame(width: 180)
                }

                // JPEG 质量（仅 forceJPEG 时显示）
                if compressor.forceJPEG {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JPEG 质量: \(Int(compressor.jpegQuality))%")
                            .font(.caption)
                        Slider(value: $compressor.jpegQuality, in: 1...100, step: 1)
                            .frame(width: 140)
                        if compressor.jpegQuality > 60 {
                            Text("质量过高可能导致已压缩图片反而变大")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer()

                // 开关
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Ghostscript 压缩", isOn: $compressor.useGS)
                        .font(.caption)
                    Toggle("qpdf 线性化", isOn: $compressor.useQPDF)
                        .font(.caption)
                    Toggle("强制 JPEG 重编码", isOn: $compressor.forceJPEG)
                        .font(.caption)
                        .help("强制将图片以 JPEG 重新编码，否则由 Ghostscript 智能选择编码方式")
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Batch File List

    private var batchFileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("批量队列（\(compressor.inputURLs.count) 个文件）")
                    .font(.headline)
                Spacer()
                if compressor.isBatchCompressing {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(compressor.currentBatchIndex + 1)/\(compressor.inputURLs.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("清空") { compressor.clearBatch() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(compressor.isBatchCompressing)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(compressor.inputURLs.enumerated()), id: \.offset) { idx, url in
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if idx < compressor.batchResults.count {
                                let r = compressor.batchResults[idx]
                                if r.success {
                                    Text(r.compressionRatio)
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("失败")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            } else if compressor.isBatchCompressing && idx == compressor.currentBatchIndex {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Button(role: .destructive) {
                                compressor.inputURLs.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .disabled(compressor.isBatchCompressing)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(compressor.inputURLs.count) * 24 + 10, 150))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
        // 进度条
        if compressor.isCompressing || compressor.isInstalling || compressor.isBatchCompressing {
            ProgressView(value: compressor.isInstalling ? .none : (compressor.isBatchCompressing ? compressor.batchProgress : compressor.progress)) {
                Text(compressor.statusText)
                    .font(.caption)
            }
            .padding(.bottom, 12)
        }

            // 结果
            if let result = compressor.result {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("压缩前:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(compressor.inputSize ?? "")
                                .font(.caption)
                        }
                        HStack(spacing: 4) {
                            Text("压缩后:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.finalSize)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("(\(result.compressionRatio))")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.bottom, 8)
            }

            // 操作按钮
            HStack(spacing: 12) {
                // 批量模式
                if !compressor.inputURLs.isEmpty {
                    Button("清空队列") { compressor.clearBatch() }
                        .buttonStyle(.borderless)
                        .disabled(compressor.isBatchCompressing)

                    Spacer()

                    Button("压缩全部") { compressor.compressBatch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(compressor.isBatchCompressing || !compressor.missingTools.isEmpty)
                        .keyboardShortcut(.return)
                }
                // 单文件模式
                else if compressor.inputURL != nil {
                    Button("清除") { withAnimation { compressor.reset() } }
                        .buttonStyle(.borderless)

                    Spacer()

                    Button("开始压缩") { compressor.compress() }
                        .buttonStyle(.borderedProminent)
                        .disabled(compressor.isCompressing || !compressor.missingTools.isEmpty)
                        .keyboardShortcut(.return)
                }
            }
        }
    }
}
