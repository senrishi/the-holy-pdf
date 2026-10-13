import Cocoa
import PDFKit

/// Generates a rich multi-page test PDF document featuring text, shapes, and layouts
/// enabling instant verification of Negative's GPU filtering, Preview's markup, and thumbnail operations.
public enum SampleDocumentGenerator {

    public static func createSampleDocument() -> PDFDocument {
        let pdfData = NSMutableData()
        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Standard US Letter

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            return PDFDocument()
        }

        // ================= PAGE 1 =================
        context.beginPage(mediaBox: &pageRect)
        drawPage1(context: context, bounds: pageRect)
        context.endPage()

        // ================= PAGE 2 =================
        context.beginPage(mediaBox: &pageRect)
        drawPage2(context: context, bounds: pageRect)
        context.endPage()

        // ================= PAGE 3 =================
        context.beginPage(mediaBox: &pageRect)
        drawPage3(context: context, bounds: pageRect)
        context.endPage()

        // ================= PAGE 4 (Scanned / Handwritten Canvas) =================
        context.beginPage(mediaBox: &pageRect)
        drawPage4(context: context, bounds: pageRect)
        context.endPage()

        context.closePDF()

        let doc = PDFDocument(data: pdfData as Data) ?? PDFDocument()

        // Build Table of Contents / Outline for Topic-based Page Jumping
        let root = PDFOutline()

        let topic1 = PDFOutline()
        topic1.label = "1. Negative GPU Engine"
        if let p1 = doc.page(at: 0) {
            topic1.destination = PDFDestination(page: p1, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(topic1, at: 0)

        let topic2 = PDFOutline()
        topic2.label = "2. Vector & Color Inversion Test"
        if let p2 = doc.page(at: 1) {
            topic2.destination = PDFDestination(page: p2, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(topic2, at: 1)

        let topic3 = PDFOutline()
        topic3.label = "3. Page Management Canvas"
        if let p3 = doc.page(at: 2) {
            topic3.destination = PDFDestination(page: p3, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(topic3, at: 2)

        let topic4 = PDFOutline()
        topic4.label = "4. Handwritten & Scanned OCR Test"
        if let p4 = doc.page(at: 3) {
            topic4.destination = PDFDestination(page: p4, at: CGPoint(x: 0, y: 792))
        }
        root.insertChild(topic4, at: 3)

        doc.outlineRoot = root
        return doc
    }

    private static func drawPage1(context: CGContext, bounds: CGRect) {
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        // Header Background Banner
        let headerRect = NSRect(x: 40, y: bounds.height - 130, width: bounds.width - 80, height: 90)
        let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.22, alpha: 1.0).setFill()
        headerPath.fill()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        ("TheHolyPdf — Native Architecture" as NSString).draw(at: NSPoint(x: 60, y: bounds.height - 85), withAttributes: titleAttrs)

        // Subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0)
        ]
        ("Negative GPU Color Inversion + Preview Sidebar & Markup Architecture" as NSString).draw(at: NSPoint(x: 60, y: bounds.height - 110), withAttributes: subtitleAttrs)

        // Section 1: Overview
        var currentY: CGFloat = bounds.height - 170

        drawSectionHeading("1. Negative's Hardware-Accelerated Filtering Engine", at: NSPoint(x: 40, y: currentY))
        currentY -= 30

        let bodyText = """
        This PDF document demonstrates the exact rendering mechanism extracted from Negative.app (v2.0):
        • CALayer.filters: Inversion and Sharpening fragment shaders run in Core Animation composition passes.
        • Zero CPU re-rasterization: The underlying vector geometry and glyph coordinates are untouched.
        • Intact Text Selection: Select and copy text below; notice how cursor rects, hit-testing, and highlight contrast remain pristine even in Negative and Sepia modes!
        • Smooth 120Hz Inertial Scrolling: Document textures are transformed directly on Apple Silicon GPU pipelines.
        """
        drawParagraph(bodyText, at: NSPoint(x: 40, y: currentY), width: bounds.width - 80)
        currentY -= 110

        // Highlightable sample box
        let sampleBox = NSRect(x: 40, y: currentY - 70, width: bounds.width - 80, height: 70)
        let samplePath = NSBezierPath(roundedRect: sampleBox, xRadius: 8, yRadius: 8)
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1.0).setFill()
        samplePath.fill()
        NSColor(calibratedRed: 0.75, green: 0.82, blue: 0.92, alpha: 1.0).setStroke()
        samplePath.stroke()

        let quoteText = "“Try dragging across this text sentence to select it with your mouse, then click the Markup highlighter or draw a rectangle around it!”"
        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.25, blue: 0.45, alpha: 1.0)
        ]
        (quoteText as NSString).draw(in: sampleBox.insetBy(dx: 16, dy: 14), withAttributes: quoteAttrs)

        currentY -= 110

        // Section 2: Instructions
        drawSectionHeading("2. Preview.app Markup & Thumbnail Features", at: NSPoint(x: 40, y: currentY))
        currentY -= 30

        let markupInstructions = """
        • Markup Sub-toolbar: Click the pencil icon in the top toolbar to reveal the secondary accessory bar.
        • Native Annotations: Choose Text Box, Shapes (Rectangle, Circle, Line), or Freehand Pen to annotate.
        • Page Management: Select any page in the left PDFThumbnailView sidebar and press Delete (⌘⌫) to delete it!
        • Page Rotation & Insertion: Right-click any thumbnail to Rotate Left/Right or Insert Blank Pages.
        """
        drawParagraph(markupInstructions, at: NSPoint(x: 40, y: currentY), width: bounds.width - 80)
    }

    private static func drawPage2(context: CGContext, bounds: CGRect) {
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        var currentY: CGFloat = bounds.height - 80
        drawSectionHeading("Vector Primitives & High-Contrast Visual Test", at: NSPoint(x: 40, y: currentY))
        currentY -= 35

        drawParagraph("The shapes below test color inversion and saturation handling between Normal, Negative, and Negative Sepia modes.", at: NSPoint(x: 40, y: currentY), width: bounds.width - 80)
        currentY -= 40

        // Draw colored geometric shapes
        let shapes = [
            (color: NSColor.systemBlue, name: "Sapphire"),
            (color: NSColor.systemRed, name: "Crimson"),
            (color: NSColor.systemGreen, name: "Emerald"),
            (color: NSColor.systemOrange, name: "Amber"),
            (color: NSColor.systemPurple, name: "Violet")
        ]

        let shapeWidth: CGFloat = 85
        let spacing: CGFloat = 18
        for (i, shape) in shapes.enumerated() {
            let x = 40 + CGFloat(i) * (shapeWidth + spacing)
            let rect = NSRect(x: x, y: currentY - 70, width: shapeWidth, height: 70)
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            shape.color.setFill()
            path.fill()

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            (shape.name as NSString).draw(at: NSPoint(x: x + 10, y: currentY - 45), withAttributes: labelAttrs)
        }

        currentY -= 130

        // Code block test
        drawSectionHeading("Swift Reverse-Engineering Assembly Reference", at: NSPoint(x: 40, y: currentY))
        currentY -= 25

        let codeBox = NSRect(x: 40, y: currentY - 180, width: bounds.width - 80, height: 180)
        let codeBg = NSBezierPath(roundedRect: codeBox, xRadius: 6, yRadius: 6)
        NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.15, alpha: 1.0).setFill()
        codeBg.fill()

        let codeSnippet = """
        // Reconstructed from Negative.app (IMP: 0x10000c810)
        case .negative:
            self.pdfView.backgroundColor = NSColor.white
            let invert = CIFilter(name: "CIColorInvert")!
            let sharpen = CIFilter(name: "CISharpenLuminance")!
            self.pdfView.layer?.filters = [invert, sharpen]

        case .negativeSepia:
            self.pdfView.backgroundColor = NSColor.white
            let sepia = CIFilter(name: "CISepiaTone")!
            self.pdfView.layer?.filters = [invert, sharpen, sepia]
        """

        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.65, alpha: 1.0)
        ]
        (codeSnippet as NSString).draw(in: codeBox.insetBy(dx: 14, dy: 14), withAttributes: codeAttrs)
    }

    private static func drawPage3(context: CGContext, bounds: CGRect) {
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        var currentY: CGFloat = bounds.height - 80
        drawSectionHeading("Page 3: Deletion & Management Test Canvas", at: NSPoint(x: 40, y: currentY))
        currentY -= 35

        let text = """
        This is an extra page included specifically to test PDF page deletion and reordering:

        1. Look at the PDFThumbnailView in the left sidebar.
        2. Click on Page 3's thumbnail to highlight it.
        3. Press Delete or Backspace on your keyboard (or click the Trash button in the sidebar header).
        4. Notice that Page 3 is instantly deleted, and the document page count updates seamlessly.
        5. Press ⌘Z (Undo) to instantly restore Page 3 back into the document!
        """
        drawParagraph(text, at: NSPoint(x: 40, y: currentY), width: bounds.width - 80)
        currentY -= 170

        // Large test area for freehand markup
        let testBox = NSRect(x: 40, y: 80, width: bounds.width - 80, height: currentY - 80)
        let testPath = NSBezierPath(roundedRect: testBox, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.98, alpha: 1.0).setFill()
        testPath.fill()
        NSColor(calibratedWhite: 0.8, alpha: 1.0).setStroke()
        testPath.stroke()

        let promptAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        ("— Open the Markup bar and draw shapes or freehand ink here —" as NSString).draw(at: NSPoint(x: bounds.width / 2 - 190, y: (currentY + 80) / 2), withAttributes: promptAttrs)
    }

    private static func drawSectionHeading(_ text: String, at point: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawParagraph(_ text: String, at point: NSPoint, width: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]

        let rect = NSRect(x: point.x, y: point.y - 120, width: width, height: 120)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func drawPage4(context: CGContext, bounds: CGRect) {
        // Render handwritten simulation into a bitmap raster image
        // Because it is blitted as an image, there are no PDF text glyphs on this page.
        // This exercises on-device Vision OCR search and OCR text copying!
        let scale: CGFloat = 2.0
        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let bitmapCtx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }

        bitmapCtx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1.0))
        bitmapCtx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        bitmapCtx.scaleBy(x: scale, y: scale)

        let nsContext = NSGraphicsContext(cgContext: bitmapCtx, flipped: false)
        let prevContext = NSGraphicsContext.current
        NSGraphicsContext.current = nsContext

        // Ruled paper lines
        NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.96, alpha: 0.85).setStroke()
        let linePath = NSBezierPath()
        var lineY: CGFloat = 80
        while lineY < bounds.height - 100 {
            linePath.move(to: NSPoint(x: 40, y: lineY))
            linePath.line(to: NSPoint(x: bounds.width - 40, y: lineY))
            lineY += 28
        }
        linePath.lineWidth = 1.0
        linePath.stroke()

        // Red margin line
        NSColor(calibratedRed: 0.95, green: 0.6, blue: 0.6, alpha: 0.8).setStroke()
        let marginPath = NSBezierPath()
        marginPath.move(to: NSPoint(x: 80, y: 40))
        marginPath.line(to: NSPoint(x: 80, y: bounds.height - 40))
        marginPath.lineWidth = 1.5
        marginPath.stroke()

        // Handwritten-style cursive / casual notes
        let font = NSFont(name: "Noteworthy-Bold", size: 17) ?? NSFont.systemFont(ofSize: 17, weight: .medium)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.1, green: 0.18, blue: 0.45, alpha: 1.0)
        ]

        let titleFont = NSFont(name: "Noteworthy-Bold", size: 23) ?? NSFont.systemFont(ofSize: 23, weight: .bold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.3, alpha: 1.0)
        ]

        ("Lab Notes: Scanned & Handwritten OCR Test Canvas" as NSString).draw(at: NSPoint(x: 95, y: bounds.height - 85), withAttributes: titleAttrs)

        let notes = """
        Meeting Notes — Architecture & Reverse Engineering:
        • Negative.app uses Core Image GPU filters on CALayer (CIColorInvert).
        • Vision OCR runs locally on Apple Neural Engine to extract text.
        • This page is a rasterized bitmap image with NO vector font text!
        • Try pressing ⌘F and search for: "handwritten" or "reverse engineering".
        • Try pressing ⇧⌘C to copy this handwritten text straight to clipboard!
        • Drag any external PDF into the sidebar to combine documents.
        """

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 10
        var fullAttrs = textAttrs
        fullAttrs[.paragraphStyle] = style
        (notes as NSString).draw(in: NSRect(x: 95, y: bounds.height - 350, width: bounds.width - 130, height: 250), withAttributes: fullAttrs)

        NSGraphicsContext.current = prevContext

        if let cgImage = bitmapCtx.makeImage() {
            context.draw(cgImage, in: bounds)
        }
    }
}
