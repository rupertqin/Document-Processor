# Document Processor - macOS 原生文档处理工具

一个轻量的 macOS 原生应用，提供文档处理相关功能。

## 功能

### PDF 压缩

用 Ghostscript + qpdf 压缩 PDF 文件。

## 使用方法

### 1. 安装依赖（如未安装）

```bash
brew install ghostscript qpdf
```

### 2. 打开 Xcode 项目

```bash
open Document-processor.xcodeproj
```

### 3. 使用

1. 拖拽 PDF 到窗口，或点击选择文件
2. 调整压缩参数（DPI 分辨率、是否使用 gs/qpdf）
3. 点击 **开始压缩**
4. 压缩后的文件在原 PDF 同级目录生成 `xxx.compressed.pdf`

## 压缩原理

1. **Ghostscript** — 降采样图片分辨率、压缩字体、子集化
2. **qpdf** — 线性化 PDF，进一步减小体积

两步串行，效果叠加。
