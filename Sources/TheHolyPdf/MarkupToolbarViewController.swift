import Cocoa
import PDFKit

/// Preview-style Markup Sub-toolbar Controller
/// Implemented as an NSTitlebarAccessoryViewController sliding beneath the main window toolbar
open class MarkupToolbarViewController: NSTitlebarAccessoryViewController {

    public weak var pdfView: FilteredPDFView? {
        didSet {
            updateButtonHighlights()
            syncToolbarWithSelectedAnnotation()
        }
    }

    private var toolButtons: [MarkupTool: NSButton] = [:]
    private let strokeColorWell = NSColorWell()
    private let fillColorWell = NSColorWell()
    private let lineWidthPopUp = NSPopUpButton()
    private let fontSizePopUp = NSPopUpButton()
    private let deleteAnnotationButton = NSButton()

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.layoutAttribute = .bottom
        registerObservers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.layoutAttribute = .bottom
        registerObservers()
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMarkupToolDidChange(_:)),
            name: .markupToolDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAnnotationSelectionDidChange(_:)),
            name: .annotationSelectionDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    open override func loadView() {
        let accessoryView = NSVisualEffectView()
        accessoryView.material = .headerView
        accessoryView.blendingMode = .withinWindow
        accessoryView.state = .followsWindowActiveState
        accessoryView.wantsLayer = true

        // Bottom separator border (matching PVSubToolbarBackgroundView)
        let bottomBorder = CALayer()
        bottomBorder.backgroundColor = NSColor.separatorColor.cgColor
        bottomBorder.frame = CGRect(x: 0, y: 0, width: 2000, height: 1)
        bottomBorder.autoresizingMask = [.layerWidthSizable]
        accessoryView.layer?.addSublayer(bottomBorder)

        self.view = accessoryView
        setupSubtoolbarItems()
    }

    private func setupSubtoolbarItems() {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 6
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 16, bottom: 2, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 34)
        ])

        // 1. Tool Selection Buttons
        let tools: [MarkupTool] = [.select, .freehand, .text, .rectangle, .circle, .line, .highlight]
        for tool in tools {
            let button = createToolButton(for: tool)
            toolButtons[tool] = button
            stackView.addArrangedSubview(button)
        }

        stackView.addArrangedSubview(createDivider())

        // 2. Stroke Color Well
        let strokeLabel = NSTextField(labelWithString: "Stroke:")
        strokeLabel.font = NSFont.systemFont(ofSize: 11)
        strokeLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(strokeLabel)

        strokeColorWell.color = .systemRed
        strokeColorWell.target = self
        strokeColorWell.action = #selector(strokeColorChanged(_:))
        strokeColorWell.translatesAutoresizingMaskIntoConstraints = false
        strokeColorWell.widthAnchor.constraint(equalToConstant: 26).isActive = true
        strokeColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stackView.addArrangedSubview(strokeColorWell)

        // 3. Fill Color Well
        let fillLabel = NSTextField(labelWithString: "Fill:")
        fillLabel.font = NSFont.systemFont(ofSize: 11)
        fillLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(fillLabel)

        fillColorWell.color = .clear
        fillColorWell.target = self
        fillColorWell.action = #selector(fillColorChanged(_:))
        fillColorWell.translatesAutoresizingMaskIntoConstraints = false
        fillColorWell.widthAnchor.constraint(equalToConstant: 26).isActive = true
        fillColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stackView.addArrangedSubview(fillColorWell)

        stackView.addArrangedSubview(createDivider())

        // 4. Line Width Selector
        let widthLabel = NSTextField(labelWithString: "Width:")
        widthLabel.font = NSFont.systemFont(ofSize: 11)
        widthLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(widthLabel)

        lineWidthPopUp.pullsDown = false
        lineWidthPopUp.addItems(withTitles: ["1 pt", "2 pt", "3 pt", "5 pt", "8 pt"])
        lineWidthPopUp.selectItem(at: 1) // default 2 pt
        lineWidthPopUp.target = self
        lineWidthPopUp.action = #selector(lineWidthChanged(_:))
        lineWidthPopUp.font = NSFont.systemFont(ofSize: 11)
        stackView.addArrangedSubview(lineWidthPopUp)

        // 5. Font Size Selector
        let fontLabel = NSTextField(labelWithString: "Font:")
        fontLabel.font = NSFont.systemFont(ofSize: 11)
        fontLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(fontLabel)

        fontSizePopUp.pullsDown = false
        fontSizePopUp.addItems(withTitles: ["10 pt", "12 pt", "14 pt", "18 pt", "24 pt"])
        fontSizePopUp.selectItem(at: 2) // default 14 pt
        fontSizePopUp.target = self
        fontSizePopUp.action = #selector(fontSizeChanged(_:))
        fontSizePopUp.font = NSFont.systemFont(ofSize: 11)
        stackView.addArrangedSubview(fontSizePopUp)

        stackView.addArrangedSubview(createDivider())

        // 6. Delete Selected Annotation
        deleteAnnotationButton.bezelStyle = .texturedRounded
        deleteAnnotationButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Selected Annotation")
        deleteAnnotationButton.toolTip = "Delete Selected Annotation (⌫)"
        deleteAnnotationButton.target = self
        deleteAnnotationButton.action = #selector(deleteAnnotationClicked(_:))
        deleteAnnotationButton.isEnabled = false
        stackView.addArrangedSubview(deleteAnnotationButton)

        updateButtonHighlights()
    }

    private func createToolButton(for tool: MarkupTool) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .texturedRounded
        btn.setButtonType(.pushOnPushOff)
        btn.image = NSImage(systemSymbolName: tool.systemSymbolName, accessibilityDescription: tool.title)
        btn.toolTip = tool.title
        btn.tag = tool.rawValue
        btn.target = self
        btn.action = #selector(toolButtonClicked(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    private func createDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return box
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard let tool = MarkupTool(rawValue: sender.tag) else { return }
        pdfView?.currentTool = tool
        updateButtonHighlights()
    }

    @objc private func handleMarkupToolDidChange(_ notification: Notification) {
        updateButtonHighlights()
    }

    private func updateButtonHighlights() {
        let activeTool = pdfView?.currentTool ?? .select
        for (tool, button) in toolButtons {
            button.state = (tool == activeTool) ? .on : .off
        }
    }

    @objc private func handleAnnotationSelectionDidChange(_ notification: Notification) {
        syncToolbarWithSelectedAnnotation()
    }

    private func syncToolbarWithSelectedAnnotation() {
        guard let annotation = pdfView?.selectedAnnotation else {
            deleteAnnotationButton.isEnabled = false
            return
        }

        deleteAnnotationButton.isEnabled = true

        // Stroke / Font Color
        if annotation.type == "FreeText", let fontColor = annotation.fontColor {
            strokeColorWell.color = fontColor
        } else if annotation.color != .clear {
            strokeColorWell.color = annotation.color
        }

        // Fill Color
        if annotation.type == "FreeText" {
            fillColorWell.color = annotation.color
        } else if let interior = annotation.interiorColor {
            fillColorWell.color = interior
        }

        // Line Width
        if let border = annotation.border {
            let width = border.lineWidth
            let widths: [CGFloat] = [1.0, 2.0, 3.0, 5.0, 8.0]
            if let closestIdx = widths.enumerated().min(by: { abs($0.element - width) < abs($1.element - width) })?.offset {
                lineWidthPopUp.selectItem(at: closestIdx)
            }
        }

        // Font Size
        if annotation.type == "FreeText", let font = annotation.font {
            let size = font.pointSize
            let sizes: [CGFloat] = [10.0, 12.0, 14.0, 18.0, 24.0]
            if let closestIdx = sizes.enumerated().min(by: { abs($0.element - size) < abs($1.element - size) })?.offset {
                fontSizePopUp.selectItem(at: closestIdx)
            }
        }
    }

    @objc private func strokeColorChanged(_ sender: NSColorWell) {
        pdfView?.updateSelectedAnnotationStrokeColor(sender.color)
    }

    @objc private func fillColorChanged(_ sender: NSColorWell) {
        pdfView?.updateSelectedAnnotationFillColor(sender.color)
    }

    @objc private func lineWidthChanged(_ sender: NSPopUpButton) {
        let widths: [CGFloat] = [1.0, 2.0, 3.0, 5.0, 8.0]
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < widths.count {
            pdfView?.updateSelectedAnnotationLineWidth(widths[idx])
        }
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        let sizes: [CGFloat] = [10.0, 12.0, 14.0, 18.0, 24.0]
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < sizes.count {
            pdfView?.updateSelectedAnnotationFontSize(sizes[idx])
        }
    }

    @objc private func deleteAnnotationClicked(_ sender: Any?) {
        pdfView?.deleteSelectedAnnotation()
    }
}
