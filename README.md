# PDF Compressor - macOS 原生 PDF 压缩工具

一个轻量的 macOS 原生应用，用 Ghostscript + qpdf 压缩 PDF 文件。

## 使用方法

### 1. 安装依赖（如未安装）

```bash
brew install ghostscript qpdf
```

### 2. 打开 Xcode 项目

```bash
# 方式一：直接用 Xcode 打开
open PDFCompressor.xcodeproj

# 方式二：先创建 Xcode 项目
```

如果还没有 Xcode 项目：

1. 打开 Xcode → **File → New → Project**
2. 选择 **macOS → App**，点 Next
3. Product Name: `PDFCompressor`，Interface: **SwiftUI**，Language: **Swift**
4. 点 Create，保存到 `PDFCompressor/` 目录
5. 用 `PDFCompressor/PDFCompressor/ContentView.swift` 替换生成的 ContentView.swift
6. 把 `PDFCompressor/PDFCompressor/PDFCompressor.swift` 拖进项目
7. 点击 Run ▶ 编译运行

### 3. 使用

1. 拖拽 PDF 到窗口，或点击选择文件
2. 调整压缩参数（DPI 分辨率、是否使用 gs/qpdf）
3. 点击 **开始压缩**
4. 压缩后的文件在原 PDF 同级目录生成 `xxx.compressed.pdf`

## 压缩原理

复用 `article-spider` 项目的相同逻辑：

1. **Ghostscript** — 降采样图片分辨率、压缩字体、子集化
2. **qpdf** — 线性化 PDF，进一步减小体积

两步串行，效果叠加。
