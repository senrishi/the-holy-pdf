import Cocoa
import PDFKit
import Vision

/// Struct representing a match found via Vision OCR on a scanned or handwritten page
public struct OCRMatch {
    public let page: PDFPage
    public let pageIndex: Int
    public let text: String
    public let boundingBoxInPage: NSRect
}

/// Vision-powered OCR engine providing handwriting and printed text extraction,
/// searchable text indexing, and clipboard copying mirroring Apple Preview's Live Text features.
public final class VisionOCRManager {

    public static let shared = VisionOCRManager()

    private let processingQueue = DispatchQueue(label: "TheHolyPdf.VisionOCRQueue", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    // MARK: - Page Text Extraction (Printed & Handwritten)

    /// Performs high-accuracy Vision text recognition on a PDFPage, recognizing both printed and handwritten text
    public func recognizeText(on page: PDFPage, completion: @escaping (String, [VNRecognizedTextObservation]) -> Void) {
        processingQueue.async {
            guard let cgImage = self.renderPageToCGImage(page) else {
                DispatchQueue.main.async {
                    completion("", [])
                }
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    DispatchQueue.main.async {
                        completion("", [])
                    }
                    return
                }

                var fullText = ""
                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        fullText += topCandidate.string + "\n"
                    }
                }

                DispatchQueue.main.async {
                    completion(fullText.trimmingCharacters(in: .whitespacesAndNewlines), observations)
                }
            }

            // Configure for maximum accuracy (handwriting + multiple language support)
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion("", [])
                }
            }
        }
    }

    /// Extracts all text from a page (including handwriting) and places it on the system clipboard
    public func copyTextToPasteboard(from page: PDFPage, completion: @escaping (Bool, String) -> Void) {
        // First, check if vector text exists
        let vectorString = page.string ?? ""
        if !vectorString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(vectorString, forType: .string)
            completion(true, vectorString)
            return
        }

        // Otherwise, run Vision OCR on scanned/handwritten content
        recognizeText(on: page) { text, _ in
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                completion(true, text)
            } else {
                completion(false, "")
            }
        }
    }

    // MARK: - OCR Search for Scanned/Handwritten Pages

    /// Searches for a text query across all pages using Vision OCR if native vector search finds no results
    public func searchDocument(query: String, in document: PDFDocument, onMatch: @escaping (OCRMatch) -> Void, onComplete: @escaping () -> Void) {
        let group = DispatchGroup()
        let cleanQuery = query.lowercased()

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            group.enter()

            self.recognizeText(on: page) { fullText, observations in
                let pageBounds = page.bounds(for: .mediaBox)

                for obs in observations {
                    if let topCandidate = obs.topCandidates(1).first {
                        let lineStr = topCandidate.string.lowercased()
                        if lineStr.contains(cleanQuery) {
                            // Convert Vision normalized bounding box (0.0 to 1.0) to PDF coordinates
                            let normRect = obs.boundingBox
                            let pdfRect = NSRect(
                                x: pageBounds.origin.x + normRect.origin.x * pageBounds.width,
                                y: pageBounds.origin.y + normRect.origin.y * pageBounds.height,
                                width: normRect.width * pageBounds.width,
                                height: normRect.height * pageBounds.height
                            )

                            let match = OCRMatch(
                                page: page,
                                pageIndex: pageIndex,
                                text: topCandidate.string,
                                boundingBoxInPage: pdfRect
                            )
                            onMatch(match)
                        }
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            onComplete()
        }
    }

    // MARK: - High-Resolution Page Rasterization

    private func renderPageToCGImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // 2x Retina resolution for sharp handwriting OCR
        let pixelWidth = Int(pageRect.width * scale)
        let pixelHeight = Int(pageRect.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        // White background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale and draw PDF page
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageRect.origin.x, y: -pageRect.origin.y)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
