import Cocoa
import PDFKit

/// Preview-style Find / Search Accessory Bar (mirroring PVSearchBannerViewController in Preview)
open class SearchBarViewController: NSTitlebarAccessoryViewController, NSSearchFieldDelegate {

    public weak var pdfView: FilteredPDFView?

    private let searchField = NSSearchField()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let ocrBadge = NSTextField(labelWithString: "OCR")
    private let doneButton = NSButton()

    private var nativeMatches: [PDFSelection] = []
    private var ocrMatches: [OCRMatch] = []
    private var currentMatchIndex: Int = 0

    public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.layoutAttribute = .bottom
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.layoutAttribute = .bottom
    }

    open override func loadView() {
        let accessoryView = NSVisualEffectView()
        accessoryView.material = .headerView
        accessoryView.blendingMode = .withinWindow
        accessoryView.state = .followsWindowActiveState
        accessoryView.wantsLayer = true

        let bottomLine = CALayer()
        bottomLine.backgroundColor = NSColor.separatorColor.cgColor
        bottomLine.frame = CGRect(x: 0, y: 0, width: 2000, height: 1)
        bottomLine.autoresizingMask = [.layerWidthSizable]
        accessoryView.layer?.addSublayer(bottomLine)

        self.view = accessoryView
        setupControls()
    }

    private func setupControls() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 16, bottom: 2, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 34)
        ])

        // Search Field
        searchField.placeholderString = "Find in document…"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(searchField)

        // Previous Match
        prevButton.bezelStyle = .texturedRounded
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Match")
        prevButton.toolTip = "Previous Match (⇧Return / ⇧⌘G)"
        prevButton.target = self
        prevButton.action = #selector(findPreviousClicked(_:))
        stack.addArrangedSubview(prevButton)

        // Next Match
        nextButton.bezelStyle = .texturedRounded
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Match")
        nextButton.toolTip = "Next Match (Return / ⌘G)"
        nextButton.target = self
        nextButton.action = #selector(findNextClicked(_:))
        stack.addArrangedSubview(nextButton)

        // Match Counter Label
        matchCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        matchCountLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(matchCountLabel)

        // OCR Badge (indicates handwriting/scanned text match)
        ocrBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        ocrBadge.textColor = .white
        ocrBadge.backgroundColor = NSColor.systemIndigo
        ocrBadge.drawsBackground = true
        ocrBadge.wantsLayer = true
        ocrBadge.layer?.cornerRadius = 4
        ocrBadge.isHidden = true
        stack.addArrangedSubview(ocrBadge)

        // Done / Dismiss Button
        doneButton.bezelStyle = .texturedRounded
        doneButton.title = "Done"
        doneButton.target = self
        doneButton.action = #selector(dismissSearchBar(_:))
        stack.addArrangedSubview(doneButton)
    }

    public func focusSearchField() {
        self.view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Search Execution

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        performSearch(query: sender.stringValue)
    }

    public func controlTextDidChange(_ obj: Notification) {
        performSearch(query: searchField.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Check if Shift is held
            if NSEvent.modifierFlags.contains(.shift) {
                findPrevious()
            } else {
                findNext()
            }
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismissSearchBar(nil)
            return true
        }
        return false
    }

    public func performSearch(query: String) {
        guard let pdfView = self.pdfView,
              let document = pdfView.document,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSearch()
            return
        }

        // 1. First, search standard PDF vector text
        let results = document.findString(query, withOptions: [.caseInsensitive])
        self.nativeMatches = results
        self.ocrMatches.removeAll()
        self.ocrBadge.isHidden = true

        if !results.isEmpty {
            self.currentMatchIndex = 0
            pdfView.highlightedSelections = results
            showCurrentMatch()
        } else {
            // 2. Fall back to Vision OCR for handwritten / scanned pages!
            self.matchCountLabel.stringValue = "Running OCR…"
            VisionOCRManager.shared.searchDocument(query: query, in: document, onMatch: { [weak self] ocrMatch in
                self?.ocrMatches.append(ocrMatch)
                self?.ocrBadge.isHidden = false
                self?.updateCountLabel()
            }, onComplete: { [weak self] in
                guard let self = self else { return }
                if self.ocrMatches.isEmpty {
                    self.matchCountLabel.stringValue = "0 matches"
                    self.ocrBadge.isHidden = true
                } else {
                    self.currentMatchIndex = 0
                    self.showCurrentMatch()
                }
            })
        }
    }

    private func showCurrentMatch() {
        guard let pdfView = self.pdfView else { return }

        if !nativeMatches.isEmpty {
            let current = nativeMatches[currentMatchIndex]
            pdfView.currentSelection = current
            pdfView.go(to: current)
            pdfView.scrollSelectionToVisible(nil)
            ocrBadge.isHidden = true
        } else if !ocrMatches.isEmpty {
            let current = ocrMatches[currentMatchIndex]
            let page = current.page
            pdfView.go(to: page)
            // Draw highlight rectangle around the handwritten match
            let highlight = PDFAnnotation(bounds: current.boundingBoxInPage, forType: .highlight, withProperties: nil)
            highlight.color = NSColor.systemYellow.withAlphaComponent(0.4)
            page.addAnnotation(highlight)
            pdfView.needsDisplay = true
            ocrBadge.isHidden = false
        }

        updateCountLabel()
    }

    private func updateCountLabel() {
        let total = nativeMatches.count + ocrMatches.count
        if total == 0 {
            matchCountLabel.stringValue = "0 matches"
        } else {
            matchCountLabel.stringValue = "\(currentMatchIndex + 1) of \(total)"
        }
    }

    public func findNext() {
        let total = nativeMatches.count + ocrMatches.count
        guard total > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % total
        showCurrentMatch()
    }

    public func findPrevious() {
        let total = nativeMatches.count + ocrMatches.count
        guard total > 0 else { return }
        currentMatchIndex = (currentMatchIndex - 1 + total) % total
        showCurrentMatch()
    }

    @objc private func findNextClicked(_ sender: Any?) {
        findNext()
    }

    @objc private func findPreviousClicked(_ sender: Any?) {
        findPrevious()
    }

    public func clearSearch() {
        nativeMatches.removeAll()
        ocrMatches.removeAll()
        currentMatchIndex = 0
        matchCountLabel.stringValue = ""
        ocrBadge.isHidden = true
        pdfView?.highlightedSelections = nil
        pdfView?.clearSelection()
    }

    @objc private func dismissSearchBar(_ sender: Any?) {
        clearSearch()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            self.isHidden = true
        }
        self.view.window?.makeFirstResponder(pdfView)
    }
}
