import Cocoa
import PDFKit
import CoreImage

/// Custom PDFView implementing Negative.app's hardware-accelerated Core Image layer filters
/// combined with Preview's native annotation authoring, inline text editing, and selection interaction.
open class FilteredPDFView: PDFView, NSTextViewDelegate {

    // MARK: - Negative.app Filter Properties

    /// Active color transformation mode
    public var renderingMode: RenderingMode = .clear {
        didSet {
            guard oldValue != renderingMode else { return }
            changeRenderingMode()
        }
    }

    /// Automatically syncs with macOS Light Mode / Dark Mode (defaults to false to respect user selection)
    public var shouldSystemChangeColor: Bool = false {
        didSet {
            if shouldSystemChangeColor {
                updateForSystemAppearance()
            }
        }
    }

    // MARK: - Preview.app Markup Properties

    /// Active markup tool
    public var currentTool: MarkupTool = .select {
        didSet {
            updateToolState()
            NotificationCenter.default.post(name: .markupToolDidChangeNotification, object: currentTool)
        }
    }

    public var strokeColor: NSColor = .systemRed
    public var fillColor: NSColor? = .clear
    public var lineWidth: CGFloat = 2.0
    public var fontSize: CGFloat = 14.0

    // MARK: - Annotation Selection & PVSelectionHandlesLayer

    public var selectedAnnotation: PDFAnnotation? {
        didSet {
            if oldValue != selectedAnnotation {
                if activeTextEditor != nil && activeEditingAnnotation != selectedAnnotation {
                    endEditingTextAnnotation()
                }
                updateSelectionHandles()
                NotificationCenter.default.post(name: .annotationSelectionDidChangeNotification, object: selectedAnnotation)
                needsDisplay = true
            }
        }
    }

    /// Preview-style selection overlay layer with border and manipulation knobs
    private lazy var selectionHandlesLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = NSColor.controlAccentColor.cgColor
        layer.lineWidth = 1.5
        layer.zPosition = 1100
        return layer
    }()

    /// Overlay layer used for live rubber-band drawing preview without dirtying the PDF
    private lazy var previewLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = NSColor.systemBlue.cgColor
        layer.lineWidth = 2.0
        layer.lineDashPattern = [4, 4]
        layer.zPosition = 1000
        return layer
    }()

    // MARK: - Interactive State

    // Annotation dragging / moving
    private var isDraggingAnnotation: Bool = false
    private var dragAnnotationStartMouseInPage: NSPoint = .zero
    private var dragAnnotationInitialBounds: NSRect = .zero
    private var dragAnnotationInitialPage: PDFPage?

    // Shape creation rubber-banding
    private var dragStartPointInView: NSPoint = .zero
    private var dragStartPointInPage: NSPoint = .zero
    private var dragCurrentPointInPage: NSPoint = .zero
    private var freehandPointsInPage: [NSPoint] = []
    private var activePageForDrawing: PDFPage?
    private var isCurrentlyDrawing: Bool = false

    // Inline Text Editor (Preview AKTextEditorController equivalent)
    private var activeTextEditor: NSTextView?
    private var activeEditingAnnotation: PDFAnnotation?
    private var activeEditingPage: PDFPage?
    private var originalAnnotationText: String?
    private var isCommittingTextEdit: Bool = false

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonSetup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        self.wantsLayer = true
        self.autoScales = true
        self.displayMode = .singlePageContinuous
        self.displaysPageBreaks = true

        // Ensure layers are attached for markup
        if let rootLayer = self.layer {
            rootLayer.addSublayer(previewLayer)
            rootLayer.addSublayer(selectionHandlesLayer)
        }

        // Apply initial rendering mode
        changeRenderingMode()

        // Notification registration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRenderingModeNotification(_:)),
            name: .changeRenderingModeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShouldSystemChangeColorNotification(_:)),
            name: .shouldSystemChangeColorNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewScaleOrPageChange(_:)),
            name: .PDFViewScaleChanged,
            object: self
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleViewScaleOrPageChange(_:)),
            name: .PDFViewPageChanged,
            object: self
        )
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollView = self.enclosingScrollView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    open override func layout() {
        super.layout()
        previewLayer.frame = self.bounds
        selectionHandlesLayer.frame = self.bounds
        updateSelectionHandles()
        updateActiveTextEditorFrame()
    }

    @objc private func handleViewScaleOrPageChange(_ notification: Notification) {
        updateSelectionHandles()
        updateActiveTextEditorFrame()
    }

    @objc private func handleScrollViewBoundsDidChange(_ notification: Notification) {
        updateSelectionHandles()
        updateActiveTextEditorFrame()
    }

    // MARK: - Exact Negative.app Rendering Engine
    // Reconstructed from Negative.app disassembly (CocoaPDFView.changeRenderingMode: at 0x10000c810)

    @objc public func changeRenderingMode() {
        guard let hostLayer = self.layer else { return }

        switch renderingMode {
        case .clear:
            // 1. Remove all Core Animation filters
            hostLayer.filters = nil
            // 2. High-contrast dark slate background behind crisp white PDF pages
            self.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
            setPageShadowsEnabled(true)
            self.pageBreakMargins = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        case .dark:
            // 1. Set background to pure white (inverts to pitch black #000000)
            self.backgroundColor = NSColor.white
            setPageShadowsEnabled(false)
            self.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            // 2. CIColorInvert + CISharpenLuminance
            guard let invertFilter = CIFilter(name: "CIColorInvert"),
                  let sharpenFilter = CIFilter(name: "CISharpenLuminance") else { return }

            sharpenFilter.setValue(1.5, forKey: "inputSharpness")
            hostLayer.filters = [invertFilter, sharpenFilter]
        }

        NotificationCenter.default.post(name: .changeRenderingModeNotification, object: renderingMode.rawValue)
        self.needsDisplay = true
    }

    private func setPageShadowsEnabled(_ enabled: Bool) {
        let sel = Selector(("enablePageShadows:"))
        typealias EnablePageShadowsFunc = @convention(c) (AnyObject, Selector, Bool) -> Void
        if let method = class_getInstanceMethod(type(of: self), sel) {
            let imp = method_getImplementation(method)
            let fn = unsafeBitCast(imp, to: EnablePageShadowsFunc.self)
            fn(self, sel, enabled)
        }
    }

    // MARK: - macOS Appearance Monitoring (Negative.app CocoaPDFView.viewDidChangeEffectiveAppearance at 0x10000c20c)

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard shouldSystemChangeColor else { return }
        updateForSystemAppearance()
    }

    private func isSystemDarkMode() -> Bool {
        let appearance = NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func updateForSystemAppearance() {
        guard shouldSystemChangeColor else { return }
        let isDark = isSystemDarkMode()
        if isDark && renderingMode == .clear {
            renderingMode = .dark
        }
    }

    @objc private func handleRenderingModeNotification(_ notification: Notification) {
        guard (notification.object as? FilteredPDFView) !== self else { return }
        if let modeValue = notification.object as? Int,
           let mode = RenderingMode(rawValue: modeValue),
           mode != self.renderingMode {
            self.renderingMode = mode
        }
    }

    @objc private func handleShouldSystemChangeColorNotification(_ notification: Notification) {
        if let flag = notification.object as? Bool {
            self.shouldSystemChangeColor = flag
        }
    }

    // MARK: - Tool State & Cursor Management

    private func updateToolState() {
        previewLayer.path = nil
        isCurrentlyDrawing = false

        switch currentTool {
        case .select:
            NSCursor.arrow.set()
        case .text, .rectangle, .circle, .line, .freehand:
            NSCursor.crosshair.set()
        case .highlight, .underline, .strikethrough:
            NSCursor.iBeam.set()
        }
    }

    open override func resetCursorRects() {
        super.resetCursorRects()
        switch currentTool {
        case .select:
            break
        case .text, .rectangle, .circle, .line, .freehand:
            addCursorRect(self.bounds, cursor: .crosshair)
        case .highlight, .underline, .strikethrough:
            addCursorRect(self.bounds, cursor: .iBeam)
        }
    }

    // MARK: - Hit-Testing Annotations

    /// Finds any annotation near point with hit tolerance
    public func findAnnotation(at pointInPage: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        // 1. Direct hit test from PDFKit
        if let direct = page.annotation(at: pointInPage) {
            return direct
        }

        // 2. Tolerance hit test within 8pt padding for lines and fine borders
        let tolerance: CGFloat = 8.0
        let testRect = NSRect(
            x: pointInPage.x - tolerance,
            y: pointInPage.y - tolerance,
            width: tolerance * 2.0,
            height: tolerance * 2.0
        )

        for annotation in page.annotations.reversed() {
            if annotation.bounds.intersects(testRect) {
                return annotation
            }
        }
        return nil
    }

    // MARK: - Mouse Event Handling

    open override func mouseDown(with event: NSEvent) {
        let locationInView = self.convert(event.locationInWindow, from: nil)

        // 1. If currently editing text inline and clicked outside, commit and close editor first
        if let editor = activeTextEditor {
            if !editor.frame.contains(locationInView) {
                endEditingTextAnnotation()
            } else {
                super.mouseDown(with: event)
                return
            }
        }

        guard let page = self.page(for: locationInView, nearest: false) else {
            self.selectedAnnotation = nil
            super.mouseDown(with: event)
            return
        }

        let locationInPage = self.convert(locationInView, to: page)

        // 2. Check if user clicked an existing annotation
        if let hitAnnotation = findAnnotation(at: locationInPage, on: page) {
            // If user double-clicked FreeText OR clicked already selected FreeText, begin inline editing
            if hitAnnotation.type == "FreeText" && (event.clickCount >= 2 || selectedAnnotation == hitAnnotation) {
                beginEditingTextAnnotation(hitAnnotation, on: page)
                return
            }

            // Select this annotation
            self.selectedAnnotation = hitAnnotation

            // If in selection mode or text tool, initiate drag-to-move
            if currentTool == .select || currentTool == .text {
                self.isDraggingAnnotation = true
                self.dragAnnotationStartMouseInPage = locationInPage
                self.dragAnnotationInitialBounds = hitAnnotation.bounds
                self.dragAnnotationInitialPage = page
                return
            }
        }

        // 3. User clicked empty page in select mode -> deselect and let super handle
        if currentTool == .select {
            self.selectedAnnotation = nil
            super.mouseDown(with: event)
            return
        }

        // 4. In active markup mode -> start rubber-band drawing for new annotation
        self.selectedAnnotation = nil
        self.activePageForDrawing = page
        self.dragStartPointInView = locationInView
        self.dragStartPointInPage = locationInPage
        self.dragCurrentPointInPage = locationInPage
        self.isCurrentlyDrawing = true

        if currentTool == .freehand {
            self.freehandPointsInPage = [dragStartPointInPage]
        }

        // If text markup tool, apply immediately if text is selected
        if currentTool == .highlight || currentTool == .underline || currentTool == .strikethrough {
            if let selection = self.currentSelection, let str = selection.string, !str.isEmpty {
                applyTextMarkup(to: selection, tool: currentTool)
                self.clearSelection()
                self.isCurrentlyDrawing = false
                return
            }
        }
    }

    open override func mouseDragged(with event: NSEvent) {
        // 1. Moving an existing annotation
        if isDraggingAnnotation, let annotation = selectedAnnotation, let page = dragAnnotationInitialPage {
            let locationInView = self.convert(event.locationInWindow, from: nil)
            let currentPointInPage = self.convert(locationInView, to: page)
            let deltaX = currentPointInPage.x - dragAnnotationStartMouseInPage.x
            let deltaY = currentPointInPage.y - dragAnnotationStartMouseInPage.y

            var newBounds = dragAnnotationInitialBounds
            newBounds.origin.x += deltaX
            newBounds.origin.y += deltaY
            annotation.bounds = newBounds

            updateSelectionHandles()
            self.needsDisplay = true
            return
        }

        // 2. Rubber-banding a new annotation
        if isCurrentlyDrawing, let page = activePageForDrawing {
            let locationInView = self.convert(event.locationInWindow, from: nil)
            self.dragCurrentPointInPage = self.convert(locationInView, to: page)

            if currentTool == .freehand {
                self.freehandPointsInPage.append(dragCurrentPointInPage)
                updateFreehandPreview()
            } else {
                updateShapePreview(fromViewPoint: dragStartPointInView, toViewPoint: locationInView)
            }
            return
        }

        super.mouseDragged(with: event)
    }

    open override func mouseUp(with event: NSEvent) {
        // 1. Finalize dragging existing annotation
        if isDraggingAnnotation {
            isDraggingAnnotation = false
            if let annotation = selectedAnnotation {
                let oldBounds = dragAnnotationInitialBounds
                let newBounds = annotation.bounds
                if oldBounds != newBounds {
                    self.undoManager?.registerUndo(withTarget: self) { target in
                        annotation.bounds = oldBounds
                        target.updateSelectionHandles()
                        target.needsDisplay = true
                    }
                    self.undoManager?.setActionName("Move Annotation")
                }
            }
            return
        }

        // 2. Finalize creating new annotation
        if isCurrentlyDrawing, let page = activePageForDrawing {
            defer {
                previewLayer.path = nil
                isCurrentlyDrawing = false
                freehandPointsInPage.removeAll()
                activePageForDrawing = nil
            }

            switch currentTool {
            case .select:
                break

            case .text:
                createTextAnnotation(on: page)
                switchToSelectTool()

            case .rectangle:
                createShapeAnnotation(on: page, type: .square)
                switchToSelectTool()

            case .circle:
                createShapeAnnotation(on: page, type: .circle)
                switchToSelectTool()

            case .line:
                createLineAnnotation(on: page)
                switchToSelectTool()

            case .freehand:
                createInkAnnotation(on: page)
                // Stay in freehand tool for consecutive strokes

            case .highlight:
                if let selection = self.currentSelection, let str = selection.string, !str.isEmpty {
                    applyTextMarkup(to: selection, tool: .highlight)
                    self.clearSelection()
                } else {
                    createShapeAnnotation(on: page, type: .square, isHighlightFallback: true)
                }
                switchToSelectTool()

            case .underline:
                if let selection = self.currentSelection, let str = selection.string, !str.isEmpty {
                    applyTextMarkup(to: selection, tool: .underline)
                    self.clearSelection()
                }
                switchToSelectTool()

            case .strikethrough:
                if let selection = self.currentSelection, let str = selection.string, !str.isEmpty {
                    applyTextMarkup(to: selection, tool: .strikethrough)
                    self.clearSelection()
                }
                switchToSelectTool()
            }

            self.needsDisplay = true
            return
        }

        super.mouseUp(with: event)
    }

    private func switchToSelectTool() {
        self.currentTool = .select
    }

    // MARK: - Annotation Creation (Preview Parity)

    private func createTextAnnotation(on page: PDFPage) {
        var rectInPage = normalizedRect(p1: dragStartPointInPage, p2: dragCurrentPointInPage)
        if rectInPage.width < 20 || rectInPage.height < 15 {
            rectInPage = NSRect(
                x: dragStartPointInPage.x,
                y: dragStartPointInPage.y - 34,
                width: 140,
                height: 34
            )
        }

        let annotation = PDFAnnotation(bounds: rectInPage, forType: .freeText, withProperties: nil)
        annotation.contents = "Text"
        annotation.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        annotation.fontColor = strokeColor
        annotation.color = (fillColor == .clear) ? .clear : (fillColor ?? .clear)

        commitAnnotation(annotation, to: page)

        // Immediately enter inline text editing matching Preview's instant editing UX
        beginEditingTextAnnotation(annotation, on: page)
    }

    private func createShapeAnnotation(on page: PDFPage, type: PDFAnnotationSubtype, isHighlightFallback: Bool = false) {
        var rectInPage = normalizedRect(p1: dragStartPointInPage, p2: dragCurrentPointInPage)
        if rectInPage.width < 5 || rectInPage.height < 5 {
            let w: CGFloat = (type == .circle) ? 100.0 : 140.0
            let h: CGFloat = (type == .circle) ? 100.0 : 90.0
            rectInPage = NSRect(
                x: dragStartPointInPage.x - w / 2.0,
                y: dragStartPointInPage.y - h / 2.0,
                width: w,
                height: h
            )
        }

        let annotation = PDFAnnotation(bounds: rectInPage, forType: type, withProperties: nil)
        if isHighlightFallback {
            annotation.color = .clear
            annotation.interiorColor = strokeColor.withAlphaComponent(0.35)
        } else {
            annotation.color = strokeColor
            annotation.interiorColor = (fillColor == .clear || fillColor == nil) ? .clear : fillColor
            let border = PDFBorder()
            border.lineWidth = lineWidth
            annotation.border = border
        }

        commitAnnotation(annotation, to: page)
    }

    private func createLineAnnotation(on page: PDFPage) {
        let p1 = dragStartPointInPage
        var p2 = dragCurrentPointInPage

        let dist = hypot(p2.x - p1.x, p2.y - p1.y)
        if dist < 5.0 {
            // Default horizontal line of length 120 pt when user simply clicks
            p2 = CGPoint(x: p1.x + 120.0, y: p1.y)
        }

        let minX = min(p1.x, p2.x)
        let minY = min(p1.y, p2.y)
        let maxX = max(p1.x, p2.x)
        let maxY = max(p1.y, p2.y)
        let padding = max(lineWidth * 2.5, 12.0)
        let bounds = NSRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2.0,
            height: (maxY - minY) + padding * 2.0
        )

        let annotation = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
        // PDFKit line coordinates: startPoint and endPoint MUST be relative to bounds.origin
        annotation.startPoint = CGPoint(x: p1.x - bounds.origin.x, y: p1.y - bounds.origin.y)
        annotation.endPoint = CGPoint(x: p2.x - bounds.origin.x, y: p2.y - bounds.origin.y)
        // Also set explicit /L array for absolute PDF rendering
        annotation.setValue([p1.x, p1.y, p2.x, p2.y], forAnnotationKey: PDFAnnotationKey(rawValue: "/L"))
        annotation.color = strokeColor

        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border

        commitAnnotation(annotation, to: page)
    }

    private func createInkAnnotation(on page: PDFPage) {
        guard freehandPointsInPage.count >= 2 else { return }

        var minX = freehandPointsInPage[0].x
        var maxX = minX
        var minY = freehandPointsInPage[0].y
        var maxY = minY

        for p in freehandPointsInPage {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let padding = max(lineWidth * 2.0, 10.0)
        let bounds = NSRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2.0,
            height: (maxY - minY) + padding * 2.0
        )

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = strokeColor
        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border

        let path = NSBezierPath()
        path.move(to: freehandPointsInPage[0])
        for i in 1..<freehandPointsInPage.count {
            path.line(to: freehandPointsInPage[i])
        }

        annotation.add(path)
        commitAnnotation(annotation, to: page)
    }

    public func applyTextMarkup(to selection: PDFSelection, tool: MarkupTool) {
        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            guard !bounds.isEmpty else { continue }

            let subType: PDFAnnotationSubtype
            switch tool {
            case .highlight: subType = .highlight
            case .underline: subType = .underline
            case .strikethrough: subType = .strikeOut
            default: subType = .highlight
            }

            let annotation = PDFAnnotation(bounds: bounds, forType: subType, withProperties: nil)
            annotation.color = strokeColor
            commitAnnotation(annotation, to: page)
        }
    }

    private func commitAnnotation(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        self.selectedAnnotation = annotation

        self.undoManager?.registerUndo(withTarget: self) { target in
            page.removeAnnotation(annotation)
            if target.selectedAnnotation == annotation {
                target.selectedAnnotation = nil
            }
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Add Annotation")

        self.needsDisplay = true
    }

    public func deleteSelectedAnnotation() {
        if activeTextEditor != nil {
            endEditingTextAnnotation()
        }
        guard let annotation = selectedAnnotation,
              let page = annotation.page else { return }

        page.removeAnnotation(annotation)
        self.selectedAnnotation = nil

        self.undoManager?.registerUndo(withTarget: self) { target in
            page.addAnnotation(annotation)
            target.selectedAnnotation = annotation
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Delete Annotation")

        self.needsDisplay = true
    }

    // MARK: - Selected Annotation Attribute Modifications

    public func updateSelectedAnnotationStrokeColor(_ color: NSColor) {
        self.strokeColor = color
        guard let annotation = selectedAnnotation else { return }

        let oldColor = annotation.color
        let oldFontColor = annotation.fontColor

        if annotation.type == "FreeText" {
            annotation.fontColor = color
        } else {
            annotation.color = color
        }

        self.undoManager?.registerUndo(withTarget: self) { target in
            if annotation.type == "FreeText" {
                annotation.fontColor = oldFontColor
            } else {
                annotation.color = oldColor
            }
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Change Stroke Color")
        self.needsDisplay = true
    }

    public func updateSelectedAnnotationFillColor(_ color: NSColor) {
        self.fillColor = color
        guard let annotation = selectedAnnotation else { return }

        let oldColor = annotation.color
        let oldInterior = annotation.interiorColor

        if annotation.type == "FreeText" {
            annotation.color = color
        } else {
            annotation.interiorColor = (color == .clear) ? .clear : color
        }

        self.undoManager?.registerUndo(withTarget: self) { target in
            if annotation.type == "FreeText" {
                annotation.color = oldColor
            } else {
                annotation.interiorColor = oldInterior
            }
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Change Fill Color")
        self.needsDisplay = true
    }

    public func updateSelectedAnnotationLineWidth(_ width: CGFloat) {
        self.lineWidth = width
        guard let annotation = selectedAnnotation, let border = annotation.border else { return }

        let oldWidth = border.lineWidth
        border.lineWidth = width
        annotation.border = border

        self.undoManager?.registerUndo(withTarget: self) { target in
            border.lineWidth = oldWidth
            annotation.border = border
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Change Line Width")
        self.needsDisplay = true
    }

    public func updateSelectedAnnotationFontSize(_ size: CGFloat) {
        self.fontSize = size
        guard let annotation = selectedAnnotation, annotation.type == "FreeText" else { return }

        let oldFont = annotation.font
        annotation.font = NSFont.systemFont(ofSize: size, weight: .regular)

        self.undoManager?.registerUndo(withTarget: self) { target in
            annotation.font = oldFont
            target.needsDisplay = true
        }
        self.undoManager?.setActionName("Change Font Size")
        self.needsDisplay = true
    }

    // MARK: - Inline Text Editing (Preview AKTextEditorController Architecture)

    public func beginEditingTextAnnotation(_ annotation: PDFAnnotation, on page: PDFPage) {
        if activeTextEditor != nil {
            endEditingTextAnnotation()
        }
        guard annotation.type == "FreeText" else { return }

        self.selectedAnnotation = annotation
        self.activeEditingAnnotation = annotation
        self.activeEditingPage = page
        self.originalAnnotationText = annotation.contents

        let frameInView = self.convert(annotation.bounds, from: page)
        let safeFrame = NSRect(
            x: frameInView.origin.x,
            y: frameInView.origin.y,
            width: max(frameInView.width, 100),
            height: max(frameInView.height, 28)
        )

        let textView = NSTextView(frame: safeFrame)
        textView.string = annotation.contents ?? ""
        textView.font = annotation.font ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = annotation.fontColor ?? strokeColor
        textView.backgroundColor = (annotation.color == .clear) ? NSColor.textBackgroundColor : annotation.color
        textView.drawsBackground = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = self
        textView.wantsLayer = true
        textView.layer?.borderWidth = 1.5
        textView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        textView.layer?.cornerRadius = 3.0
        textView.layer?.shadowColor = NSColor.black.cgColor
        textView.layer?.shadowOpacity = 0.15
        textView.layer?.shadowRadius = 3.0
        textView.focusRingType = .none

        // Temporarily clear rendered text in the PDF to prevent ghosting while editing
        annotation.contents = ""
        self.needsDisplay = true

        self.addSubview(textView)
        self.activeTextEditor = textView

        self.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
        selectionHandlesLayer.path = nil
    }

    public func endEditingTextAnnotation() {
        guard !isCommittingTextEdit else { return }
        isCommittingTextEdit = true
        defer { isCommittingTextEdit = false }

        guard let textView = activeTextEditor,
              let annotation = activeEditingAnnotation,
              let page = activeEditingPage else {
            activeTextEditor?.removeFromSuperview()
            activeTextEditor = nil
            activeEditingAnnotation = nil
            activeEditingPage = nil
            return
        }

        let enteredText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let prevText = originalAnnotationText ?? ""

        if enteredText.isEmpty && (prevText == "Text" || prevText.isEmpty || prevText == "Click to Edit Note") {
            // Delete empty/placeholder text annotation just like Preview
            page.removeAnnotation(annotation)
            self.selectedAnnotation = nil
            self.undoManager?.registerUndo(withTarget: self) { target in
                page.addAnnotation(annotation)
                target.selectedAnnotation = annotation
                target.needsDisplay = true
            }
        } else {
            let finalString = textView.string
            annotation.contents = finalString

            // Dynamically fit bounds if text requires larger bounding box
            let font = annotation.font ?? NSFont.systemFont(ofSize: fontSize)
            let textSize = (finalString as NSString).size(withAttributes: [.font: font])
            var bounds = annotation.bounds
            let neededWidth = max(bounds.width, textSize.width + 16)
            let neededHeight = max(bounds.height, textSize.height + 10)
            if neededWidth > bounds.width || neededHeight > bounds.height {
                bounds.size.width = neededWidth
                bounds.size.height = neededHeight
                annotation.bounds = bounds
            }

            if prevText != finalString {
                self.undoManager?.registerUndo(withTarget: self) { target in
                    annotation.contents = prevText
                    target.needsDisplay = true
                }
                self.undoManager?.setActionName("Edit Text")
            }
        }

        textView.removeFromSuperview()
        self.activeTextEditor = nil
        self.activeEditingAnnotation = nil
        self.activeEditingPage = nil
        self.originalAnnotationText = nil

        self.window?.makeFirstResponder(self)
        updateSelectionHandles()
        self.needsDisplay = true
    }

    private func updateActiveTextEditorFrame() {
        guard let editor = activeTextEditor,
              let annotation = activeEditingAnnotation,
              let page = activeEditingPage else { return }

        let frameInView = self.convert(annotation.bounds, from: page)
        editor.frame = NSRect(
            x: frameInView.origin.x,
            y: frameInView.origin.y,
            width: max(frameInView.width, 100),
            height: max(frameInView.height, 28)
        )
    }

    // NSTextViewDelegate
    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape key
            endEditingTextAnnotation()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if let event = NSApp.currentEvent,
               event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
                return false // Insert newline
            } else {
                endEditingTextAnnotation()
                return true
            }
        }
        if selector == #selector(NSResponder.insertTab(_:)) {
            endEditingTextAnnotation()
            return true
        }
        return false
    }

    // MARK: - PVSelectionHandlesLayer (Preview-Style Visual Selection)

    public func updateSelectionHandles() {
        selectionHandlesLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard activeTextEditor == nil,
              let annotation = selectedAnnotation,
              let page = annotation.page else {
            selectionHandlesLayer.path = nil
            return
        }

        let boundsInView = self.convert(annotation.bounds, from: page)

        if annotation.type == "Line" {
            // Endpoints for line
            let p1InPage = CGPoint(
                x: annotation.bounds.origin.x + annotation.startPoint.x,
                y: annotation.bounds.origin.y + annotation.startPoint.y
            )
            let p2InPage = CGPoint(
                x: annotation.bounds.origin.x + annotation.endPoint.x,
                y: annotation.bounds.origin.y + annotation.endPoint.y
            )

            let p1InView = self.convert(p1InPage, from: page)
            let p2InView = self.convert(p2InPage, from: page)

            let linePath = CGMutablePath()
            linePath.move(to: p1InView)
            linePath.addLine(to: p2InView)
            selectionHandlesLayer.path = linePath
            selectionHandlesLayer.lineDashPattern = [3, 3]

            addKnob(at: p1InView)
            addKnob(at: p2InView)
        } else {
            // Bounding box for shapes and text
            let rectPath = CGPath(rect: boundsInView, transform: nil)
            selectionHandlesLayer.path = rectPath
            selectionHandlesLayer.lineDashPattern = nil

            // 4 Corner knobs
            addKnob(at: CGPoint(x: boundsInView.minX, y: boundsInView.minY))
            addKnob(at: CGPoint(x: boundsInView.maxX, y: boundsInView.minY))
            addKnob(at: CGPoint(x: boundsInView.minX, y: boundsInView.maxY))
            addKnob(at: CGPoint(x: boundsInView.maxX, y: boundsInView.maxY))

            // 4 Edge center knobs
            addKnob(at: CGPoint(x: boundsInView.midX, y: boundsInView.minY))
            addKnob(at: CGPoint(x: boundsInView.midX, y: boundsInView.maxY))
            addKnob(at: CGPoint(x: boundsInView.minX, y: boundsInView.midY))
            addKnob(at: CGPoint(x: boundsInView.maxX, y: boundsInView.midY))
        }
    }

    private func addKnob(at center: CGPoint) {
        let knobSize: CGFloat = 8.0
        let knob = CALayer()
        knob.bounds = CGRect(x: 0, y: 0, width: knobSize, height: knobSize)
        knob.position = center
        knob.backgroundColor = NSColor.white.cgColor
        knob.borderColor = NSColor.controlAccentColor.cgColor
        knob.borderWidth = 1.5
        knob.cornerRadius = knobSize / 2.0
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.25
        knob.shadowOffset = CGSize(width: 0, height: -1)
        knob.shadowRadius = 1.5
        selectionHandlesLayer.addSublayer(knob)
    }

    // MARK: - Live Vector Preview Helpers

    private func updateShapePreview(fromViewPoint p1: NSPoint, toViewPoint p2: NSPoint) {
        let rect = NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )

        let path = CGMutablePath()
        switch currentTool {
        case .circle:
            path.addEllipse(in: rect)
        case .line:
            path.move(to: p1)
            path.addLine(to: p2)
        default:
            path.addRect(rect)
        }

        previewLayer.strokeColor = strokeColor.cgColor
        previewLayer.path = path
    }

    private func updateFreehandPreview() {
        guard let page = activePageForDrawing, freehandPointsInPage.count >= 2 else { return }

        let path = CGMutablePath()
        let startViewPt = self.convert(freehandPointsInPage[0], from: page)
        path.move(to: startViewPt)

        for i in 1..<freehandPointsInPage.count {
            let viewPt = self.convert(freehandPointsInPage[i], from: page)
            path.addLine(to: viewPt)
        }

        previewLayer.strokeColor = strokeColor.cgColor
        previewLayer.lineWidth = lineWidth
        previewLayer.path = path
    }

    private func normalizedRect(p1: NSPoint, p2: NSPoint) -> NSRect {
        return NSRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }

    // MARK: - Key Events

    open override func keyDown(with event: NSEvent) {
        if activeTextEditor != nil {
            super.keyDown(with: event)
            return
        }

        // Backspace (51) or Forward Delete (117)
        if event.keyCode == 51 || event.keyCode == 117 {
            if selectedAnnotation != nil {
                deleteSelectedAnnotation()
                return
            }
        }

        // Escape (53)
        if event.keyCode == 53 {
            if selectedAnnotation != nil {
                selectedAnnotation = nil
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - OCR Text Extraction (Scanned & Handwritten Pages)

    @objc public func copyPageTextWithOCR(_ sender: Any? = nil) {
        guard let page = self.currentPage else { return }

        VisionOCRManager.shared.copyTextToPasteboard(from: page) { [weak self] success, extractedText in
            guard let self = self else { return }
            if success && !extractedText.isEmpty {
                let lineCount = extractedText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
                self.showHUDToast(message: "✓ Copied \(lineCount) lines via OCR to Clipboard")
            } else {
                self.showHUDToast(message: "No text recognized on current page")
            }
        }
    }

    public func showHUDToast(message: String) {
        let toast = NSTextField(labelWithString: "  \(message)  ")
        toast.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        toast.textColor = .white
        toast.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        toast.drawsBackground = true
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 14
        toast.alignment = .center
        toast.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -36),
            toast.heightAnchor.constraint(equalToConstant: 30),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                toast.animator().alphaValue = 0.0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    // MARK: - Context Menu

    open override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        menu.addItem(NSMenuItem.separator())
        let ocrItem = NSMenuItem(
            title: "Copy Page Text with OCR (Handwriting & Scans)",
            action: #selector(copyPageTextWithOCR(_:)),
            keyEquivalent: "C"
        )
        ocrItem.keyEquivalentModifierMask = [.command, .shift]
        ocrItem.target = self
        menu.addItem(ocrItem)

        return menu
    }
}
