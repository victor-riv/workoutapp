import UIKit
import Vision
enum WorkoutTextRecognizer {
static func recognizeText(in image: UIImage) async -> String? {
await Task.detached(priority: .userInitiated) {
guard let cgImage = image.cgImage else { return nil as String? }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])
let observations = request.results as? [VNRecognizedTextObservation] ?? []
let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
}.value
}
}
