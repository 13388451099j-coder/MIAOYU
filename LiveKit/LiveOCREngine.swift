// MARK: - OCR 引擎（广播扩展与主 App 自检页共用的同一条识别路径）
//
// 为什么这么写（都是踩过的坑）：
// - 档位必须 `.accurate`：同源 Vision 冒烟实测，`.fast` 对中文几乎全瞎（6 条气泡只认出 1 个英文词），
//   `.accurate` 全对。代价是单帧更慢更吃内存，靠 2 秒节流摊平。
// - 帧必须先降采样：全屏 NV12 帧（1170×2532 ≈ 11.9MB）直接喂 accurate 档，
//   Vision 内部中间缓冲翻几倍，容易顶爆广播扩展 ~50MB 的 jetsam 上限。
//   缩到 720 宽单通道灰度（≈1.1MB）再识别。
// - 只用 vImage 缩放 plane0（NV12 的亮度平面本身就是灰度图），不建 CIContext——
//   那玩意自己就吃掉几十 MB，且要走一遍 RGB 转换。
// - 识别全程包 autoreleasepool，帧用完即还。

import Foundation
import Vision
import CoreVideo
import Accelerate

enum LiveOCREngine {

    /// 只识别聊天区：裁掉顶部状态栏 + 导航栏（合计约 12%）；底部裁剪默认 14%（输入条），
    /// 键盘开着时由广播扩展按键盘自报的面板高度抬高（见 `LiveScreenStore.setKeyboardPanel`）。
    /// 顶部 5% 不够——群聊名称显示在导航栏里（约在顶部 9-11% 处），居中显示会被判成「对方」
    /// 混进待回目标，提 12% 把状态栏 + 导航栏整条排除。
    ///
    /// 注意：设了 regionOfInterest 后结果的 boundingBox 是相对该区域的归一化坐标——
    /// 我们只用 midX 定左右、midY 排序，两种坐标系下结论一致。
    static func regionOfInterest(bottomCut: CGFloat = 0.14) -> CGRect {
        CGRect(x: 0, y: bottomCut, width: 1, height: max(0.2, 0.88 - bottomCut))
    }

    /// 广播扩展入口：直接吃 ReplayKit 的像素缓冲。
    static func recognize(pixelBuffer: CVPixelBuffer, bottomCut: CGFloat = 0.14) -> [LiveLine] {
        var lines: [LiveLine] = []
        autoreleasepool {
            let buffer = downscaledGray(pixelBuffer) ?? pixelBuffer
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            let request = makeRequest(bottomCut: bottomCut)
            try? handler.perform([request])
            lines = finish(request)
        }
        return lines
    }

    /// 主 App 自检页入口：静态图（截图 / 合成示例）走同一条识别与解析路径。
    static func recognize(cgImage: CGImage) -> [LiveLine] {
        var lines: [LiveLine] = []
        autoreleasepool {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            let request = makeRequest()
            try? handler.perform([request])
            lines = finish(request)
        }
        return lines
    }

    private static func makeRequest(bottomCut: CGFloat = 0.14) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.minimumTextHeight = 0.015
        request.regionOfInterest = regionOfInterest(bottomCut: bottomCut)
        return request
    }

    private static func finish(_ request: VNRecognizeTextRequest) -> [LiveLine] {
        let observations = (request.results ?? []).compactMap { o -> LiveChatParser.Observation? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            return LiveChatParser.Observation(text: text, boundingBox: o.boundingBox)
        }
        return LiveChatParser.parse(observations)
    }

    /// 缩到 ≤720 宽的单通道灰度 buffer。非 NV12（双平面 YCbCr）返回 nil，
    /// 调用方退回原 buffer：宁可多花内存，不牺牲正确性。
    private static func downscaledGray(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(src)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
              CVPixelBufferGetPlaneCount(src) > 0 else { return nil }

        let srcW = CVPixelBufferGetWidth(src)
        let srcH = CVPixelBufferGetHeight(src)
        let targetW = 720
        guard srcW > targetW else { return nil }
        var dst: CVPixelBuffer?
        let createStatus = CVPixelBufferCreate(
            kCFAllocatorDefault, targetW, Int(Double(srcH) / Double(srcW) * Double(targetW)),
            kCVPixelFormatType_OneComponent8, nil, &dst)
        guard createStatus == kCVReturnSuccess, let gray = dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(src, .readOnly) }
        var srcBuf = vImage_Buffer(
            data: CVPixelBufferGetBaseAddressOfPlane(src, 0),
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(src, 0)),
            width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(src, 0)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(src, 0))
        CVPixelBufferLockBaseAddress(gray, [])
        defer { CVPixelBufferUnlockBaseAddress(gray, []) }
        var dstBuf = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(gray),
            height: vImagePixelCount(CVPixelBufferGetHeight(gray)),
            width: vImagePixelCount(CVPixelBufferGetWidth(gray)),
            rowBytes: CVPixelBufferGetBytesPerRow(gray))
        let err = vImageScale_Planar8(&srcBuf, &dstBuf, nil,
                                      vImage_Flags(kvImageHighQualityResampling))
        return err == kvImageNoError ? gray : nil
    }
}
