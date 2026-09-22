import UIKit
import Vision

/// OCR de uma imagem (foto do cupom, print de recibo). Usado pelo app e pela extensão.
enum TextRecognizer {
    /// Linhas de texto de cima para baixo.
    static func lines(in imageData: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            guard let cg = UIImage(data: imageData)?.cgImage else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            // Vision usa origem embaixo à esquerda: maior Y = mais pra cima.
            return (request.results ?? [])
                .sorted { a, b in
                    abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01
                        ? a.boundingBox.midY > b.boundingBox.midY
                        : a.boundingBox.minX < b.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}
