import SwiftUI
import PhotosUI
import Vision
import UIKit

/// 截图识别改写：相册选图 → Vision 中文识别（准确模式）→ 可编辑文本 → 一键送入改写输入框
struct OCRView: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: 状态

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var recognizedText: String = ""
    @State private var isRecognizing = false
    @State private var errorMessage: String?

    private var trimmedText: String {
        recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 图片预览区
            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 160)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                            Text("选择一张聊天截图")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    )
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(
                    pickedImage == nil ? "从相册选择图片" : "换一张",
                    systemImage: "photo.badge.plus"
                )
            }
            .buttonStyle(.bordered)

            Divider()

            // 识别结果（可编辑）
            VStack(alignment: .leading, spacing: 8) {
                Text("识别结果（可修改）")
                    .font(.headline)
                TextEditor(text: $recognizedText)
                    .frame(minHeight: 160)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(alignment: .topTrailing) {
                        if isRecognizing {
                            ProgressView()
                                .padding(8)
                        }
                    }
            }

            Spacer()

            // 送入改写
            Button {
                sendToRewrite()
            } label: {
                Label("送去改写", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedText.isEmpty || isRecognizing)
            .padding(.bottom)
        }
        .padding()
        .navigationTitle("截图识别改写")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { newItem in
            loadPhoto(newItem)
        }
        .alert(
            "识别失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: 逻辑

    /// 读取所选图片并做 OCR 识别
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isRecognizing = true
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw NSError(
                        domain: "miaoyu.ocr",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "无法读取所选图片，请换一张试试。"]
                    )
                }
                pickedImage = image
                let text = await Self.recognizeText(in: image)
                recognizedText = text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "没有识别到文字，请换一张更清晰的截图。"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRecognizing = false
        }
    }

    /// Vision 中文文本识别（后台线程执行，避免卡 UI）
    private static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans"]   // 简体中文
        request.recognitionLevel = .accurate          // 准确模式

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let text = request.results?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n") ?? ""
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    /// 把识别文本送入改写页输入框并切换到「改写」Tab
    private func sendToRewrite() {
        guard !trimmedText.isEmpty else { return }
        appState.pendingRewriteText = trimmedText
        appState.selectedTab = .rewrite
        dismiss()
    }
}

#Preview {
    NavigationStack {
        OCRView()
    }
    .environmentObject(AppState())
}
