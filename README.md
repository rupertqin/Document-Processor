# Document Processor

macOS 原生 PDF 压缩工具，基于 Ghostscript + qpdf，Swift/SwiftUI 构建。

## 功能

- **单文件压缩** — 拖拽或选择 PDF，一键压缩
- **批量压缩** — 同时拖入多个文件，队列式处理
- **三档预设** — 低质量 / 中质量（推荐）/ 高质量，一键切换
- **自定义参数** — 分辨率、JPEG 质量、编码方式均可微调
- **一键安装依赖** — 缺少 ghostscript/qpdf 时自动检测并提供 Homebrew 安装
- **防劣化保护** — 压缩后反而变大时自动保留原文件

## 安装依赖

应用首次启动会自动检测，也可手动安装：

```bash
brew install ghostscript qpdf
```

## 使用方法

1. 拖拽 PDF 到窗口，或点击 **选择文件**
2. 选择压缩预设或手动调整参数
3. 点击 **开始压缩**
4. 压缩后的文件在原 PDF 同级目录，命名为 `xxx.compressed.pdf`

批量模式：拖入多个文件后出现队列面板，点击 **压缩全部**。

## 压缩流程

```
原始 PDF
  │
  ├─ Step 1: qpdf --decrypt（修复与解密）
  │     消除隐藏的"所有者权限加密"，修复底层结构错误
  │     给 GS 一个干净、健康的输入
  │
  ├─ Step 2: Ghostscript（图片压缩）
  │     降采样图片分辨率、JPEG 重编码、字体压缩与子集化
  │
  └─ Step 3: qpdf --linearize（线性化）
        优化 PDF 流式加载，加快首屏打开速度
```

- Step 1 和 Step 3 由 **qpdf 线性化** 开关控制，关闭则跳过
- Step 2 由 **Ghostscript 压缩** 开关控制，关闭则跳过
- qpdf 是可选的，但推荐开启（修复损坏 PDF + 线性化优化）

## 参数说明

### 预设

| 预设 | 分辨率 (DPI) | 强制 JPEG | JPEG 质量 | 适用场景 |
|------|-------------|-----------|----------|---------|
| 低质量 | 72 | ✅ | 20% | 微信分享、邮件附件 |
| 中质量（推荐） | 140 | ✅ | 30% | 日常使用 |
| 高质量 | 200 | ❌ | 50% | 存档保留 |
| 自定义 | — | — | — | 手动微调 |

### 参数详解

- **图片分辨率 (DPI)** — 控制图片降采样目标分辨率，越低体积越小
- **强制 JPEG 重编码** — 开启时强制将所有图片以 JPEG 重新编码并应用 QFactor 质量控制；关闭时由 Ghostscript 自动选择编码方式
- **JPEG 质量** — 仅在"强制 JPEG 重编码"开启时生效。控制 JPEG 压缩强度，1% 最小体积，100% 最高保真。内部使用 IJG 标准 QFactor 映射：
  - quality < 50: `QFactor = 5000 / quality / 100`
  - quality ≥ 50: `QFactor = (200 - quality × 2) / 100`
  - QFactor 与质量**反相关**：QFactor 越小质量越高
- **Ghostscript 压缩** — 是否执行 GS 降采样/重编码步骤
- **qpdf 线性化** — 开启后同时执行前置解密修复 + 后置线性化

### 预设联动

- 选择预设 → 自动应用对应参数
- 手动调参 → 自动切换到"自定义"标签
- 点击"自定义" → 不修改当前参数（仅标签切换）

## 项目结构

```
Document-Processor/
├── Package.swift                     # SPM 包定义
├── Sources/
│   └── DocumentProcessor/
│       ├── App.swift                 # 应用入口（@main）
│       ├── ContentView.swift         # 主界面（SwiftUI）
│       ├── PDFCompressor.swift       # 核心压缩逻辑
│       └── Resources/
│           └── Assets.xcassets/      # 图标资源
├── Tests/
│   └── DocumentProcessorTests/
│       └── PDFCompressorTests.swift  # 单元测试（57 个用例）
├── .github/workflows/
│   └── swift.yml                     # CI: swift build + swift test
└── generate_icon.py                  # 图标生成脚本
```

## 开发

### 环境要求

- macOS 15.0+
- Xcode 16+
- Swift 6.0+

### 构建与运行

**命令行（SPM）**：

```bash
swift build
swift run
```

**Xcode**：`open Package.swift`，然后 `⌘R` 运行

### 运行测试

**命令行**：

```bash
swift test
```

**Xcode**：`⌘U` 或 `Product → Test`

### CI

推送到 `main` 分支或创建 PR 时，GitHub Actions 自动执行 `swift build` + `swift test`。

## 技术细节

### 防劣化机制

压缩完成后对比输出文件与原文件大小。若输出更大，自动用原文件替换输出，压缩比显示 `100.0% (防劣化)`。

### 线程安全

- `StderrBuffer` — `NSLock` 保护的线程安全缓冲区，用于 Process 回调中的 stderr 累积
- `ProgressParserState` — `@unchecked Sendable` 类，用于 `gsProgressParser` 闭包中的可变状态
- `_sizeFormatter` — `ByteCountFormatter` 扩展为 `@unchecked Sendable`，用于 `nonisolated` 的 `formattedSize`

### Swift 并发

项目使用 Swift 6 严格并发模式。所有访问 `@Published` 属性的方法均标注 `@MainActor`，纯计算方法（`gsQFactor`、`formattedSize`、`gsProgressParser`）标注 `nonisolated`。`gsProgressParser` 返回 `@Sendable` 闭包。
