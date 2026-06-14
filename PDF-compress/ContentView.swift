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
            if compressor.inputURL != nil && compressor.missingTools.isEmpty {
                optionsPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            // 底部
            bottomBar
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 360)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result {
                compressor.load(url)
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
            guard let item = providers.first else { return false }
            item.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data = data as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { compressor.load(url) }
                }
            }
            return true
        }
        .onTapGesture {
            if compressor.inputURL == nil { showFilePicker = true }
        }
    }

    // MARK: - Options

    private var optionsPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("压缩选项")
                    .font(.headline)
                Spacer()
            }

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

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // 进度条
            if compressor.isCompressing || compressor.isInstalling {
                ProgressView(value: compressor.isInstalling ? .none : compressor.progress) {
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
                if compressor.inputURL != nil {
                    Button("清除") {
                        withAnimation { compressor.reset() }
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("开始压缩") {
                        compressor.compress()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(compressor.isCompressing || !compressor.missingTools.isEmpty)
                    .keyboardShortcut(.return)
                }
            }
        }
    }
}
