import Cocoa
import PDFKit

/// Main Window Controller managing Preview-style Toolbar, Titlebar Accessories, and Document Window Lifecycle
open class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate, NSTextFieldDelegate {

    public let splitViewController = MainSplitViewController()
    public let markupAccessoryVC = MarkupToolbarViewController()
    public let searchAccessoryVC = SearchBarViewController()

    private var renderingSegmentedControl: NSSegmentedControl!
    private var pageNumberInputField: NSTextField!
    private var pageTotalLabel: NSTextField!
    private var markupToolbarButton: NSButton!
    private var allToolbarViews: [NSView] = []

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TheHolyPdf"
        // Hide standard window title to prevent overlapping toolbar items!
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.minSize = NSSize(width: 760, height: 520)
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentViewController = splitViewController

        setupToolbar()
        setupMarkupAccessory()
        setupSearchAccessory()
        setupNotificationObservers()
        updateWindowAppearance(for: splitViewController.documentVC.pdfView.renderingMode)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMarkupAccessory() {
        guard let window = self.window else { return }

        markupAccessoryVC.pdfView = splitViewController.documentVC.pdfView
        markupAccessoryVC.layoutAttribute = .bottom
        markupAccessoryVC.isHidden = true // Toggled via ⇧⌘A or pencil button

        window.addTitlebarAccessoryViewController(markupAccessoryVC)
    }

    private func setupSearchAccessory() {
        guard let window = self.window else { return }

        searchAccessoryVC.pdfView = splitViewController.documentVC.pdfView
        searchAccessoryVC.layoutAttribute = .bottom
        searchAccessoryVC.isHidden = true // Toggled via ⌘F or magnifying glass

        window.addTitlebarAccessoryViewController(searchAccessoryVC)
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePageStatus),
            name: .PDFViewPageChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePageStatus),
            name: .documentStructureDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRenderingModeDidChange(_:)),
            name: .changeRenderingModeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - NSWindowDelegate (Multi-window Management)

    public func windowWillClose(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.removeWindowController(self)
    }

    public func windowDidResize(_ notification: Notification) {
        updateWindowAppearance(for: splitViewController.documentVC.pdfView.renderingMode)
    }

    // MARK: - Toolbar Setup (Matching Preview UI/UX)

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "TheHolyPdf.MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        self.window?.toolbar = toolbar
    }

    // Toolbar Item Identifiers
    private static let sidebarItemID = NSToolbarItem.Identifier("SidebarToggle")
    private static let pageNavItemID = NSToolbarItem.Identifier("PageNav")
    private static let renderingModeItemID = NSToolbarItem.Identifier("RenderingMode")
    private static let zoomItemID = NSToolbarItem.Identifier("ZoomGroup")
    private static let markupItemID = NSToolbarItem.Identifier("MarkupToggle")
    private static let searchItemID = NSToolbarItem.Identifier("SearchToggle")
    private static let combinePDFItemID = NSToolbarItem.Identifier("CombinePDF")
    private static let openFileItemID = NSToolbarItem.Identifier("OpenFile")
    private static let saveFileItemID = NSToolbarItem.Identifier("SaveFile")

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.sidebarItemID,
            Self.pageNavItemID,
            .flexibleSpace,
            Self.renderingModeItemID,
            .flexibleSpace,
            Self.zoomItemID,
            Self.markupItemID,
            Self.searchItemID,
            Self.combinePDFItemID,
            Self.openFileItemID,
            Self.saveFileItemID
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            Self.sidebarItemID,
            Self.pageNavItemID,
            .flexibleSpace,
            Self.renderingModeItemID,
            .flexibleSpace,
            Self.zoomItemID,
            Self.markupItemID,
            Self.searchItemID,
            Self.combinePDFItemID,
            Self.openFileItemID
        ]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case Self.sidebarItemID:
            item.label = "Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Hide/Show Sidebar (⌥⌘1)"
            let btn = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")!, target: self, action: #selector(toggleSidebarClicked(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn

        case Self.pageNavItemID:
            item.label = "Navigation"
            item.paletteLabel = "Page Navigation"
            item.toolTip = "Previous / Next Page or Jump Directly to Page"

            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 3
            stack.alignment = .centerY

            let prevBtn = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Page")!, target: self, action: #selector(prevPageClicked(_:)))
            prevBtn.bezelStyle = .texturedRounded
            prevBtn.toolTip = "Previous Page (Page Up)"

            pageNumberInputField = NSTextField()
            pageNumberInputField.alignment = .center
            pageNumberInputField.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            pageNumberInputField.stringValue = "1"
            pageNumberInputField.delegate = self
            pageNumberInputField.target = self
            pageNumberInputField.action = #selector(pageNumberFieldAction(_:))
            pageNumberInputField.translatesAutoresizingMaskIntoConstraints = false
            pageNumberInputField.widthAnchor.constraint(equalToConstant: 38).isActive = true

            pageTotalLabel = NSTextField(labelWithString: "of 1")
            pageTotalLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            pageTotalLabel.textColor = .secondaryLabelColor

            let nextBtn = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Page")!, target: self, action: #selector(nextPageClicked(_:)))
            nextBtn.bezelStyle = .texturedRounded
            nextBtn.toolTip = "Next Page (Page Down)"

            stack.addArrangedSubview(prevBtn)
            stack.addArrangedSubview(pageNumberInputField)
            stack.addArrangedSubview(pageTotalLabel)
            stack.addArrangedSubview(nextBtn)
            item.view = stack

        case Self.renderingModeItemID:
            item.label = "Mode"
            item.paletteLabel = "Color Mode"
            item.toolTip = "Switch between Normal, Negative (Invert), and Sepia"
            let seg = NSSegmentedControl(labels: ["Normal", "Negative", "Sepia"], trackingMode: .selectOne, target: self, action: #selector(renderingModeChanged(_:)))
            seg.selectedSegment = 0
            self.renderingSegmentedControl = seg
            item.view = seg

        case Self.zoomItemID:
            item.label = "Zoom"
            item.paletteLabel = "Zoom Controls"
            let seg = NSSegmentedControl(images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out")!,
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In")!,
                NSImage(systemSymbolName: "arrow.up.left.and.down.right.magnifyingglass", accessibilityDescription: "Zoom to Fit")!
            ], trackingMode: .momentary, target: self, action: #selector(zoomSegmentClicked(_:)))
            item.view = seg

        case Self.markupItemID:
            item.label = "Markup"
            item.paletteLabel = "Toggle Markup Toolbar"
            item.toolTip = "Toggle Markup Accessory Bar (⇧⌘A)"
            let btn = NSButton(image: NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Markup")!, target: self, action: #selector(toggleMarkupClicked(_:)))
            btn.bezelStyle = .texturedRounded
            btn.setButtonType(.pushOnPushOff)
            self.markupToolbarButton = btn
            item.view = btn

        case Self.searchItemID:
            item.label = "Search"
            item.paletteLabel = "Find in Document"
            item.toolTip = "Find Text & OCR Handwriting (⌘F)"
            let btn = NSButton(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!, target: self, action: #selector(toggleSearchClicked(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn

        case Self.combinePDFItemID:
            item.label = "Combine"
            item.paletteLabel = "Combine PDFs"
            item.toolTip = "Combine / Insert Pages from Another PDF… (⇧⌘I)"
            let btn = NSButton(image: NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: "Combine PDFs")!, target: self, action: #selector(combinePDFClicked(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn

        case Self.openFileItemID:
            item.label = "Open"
            item.paletteLabel = "Open PDF"
            item.toolTip = "Open PDF Document (⌘O)"
            let btn = NSButton(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Open")!, target: self, action: #selector(openDocumentClicked(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn

        case Self.saveFileItemID:
            item.label = "Save"
            item.paletteLabel = "Save PDF"
            item.toolTip = "Save Annotated PDF (⌘S)"
            let btn = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")!, target: self, action: #selector(saveDocumentClicked(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn

        default:
            return nil
        }

        if let v = item.view, !allToolbarViews.contains(where: { $0 === v }) {
            allToolbarViews.append(v)
            v.appearance = NSAppearance(named: .darkAqua)
        }

        return item
    }

    // MARK: - Actions

    @objc private func toggleSidebarClicked(_ sender: Any?) {
        splitViewController.toggleSidebar()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateWindowAppearance(for: self.splitViewController.documentVC.pdfView.renderingMode)
        }
    }

    @objc private func renderingModeChanged(_ sender: NSSegmentedControl) {
        if let mode = RenderingMode(rawValue: sender.selectedSegment) {
            splitViewController.documentVC.pdfView.renderingMode = mode
            updateWindowAppearance(for: mode)
        }
    }

    @objc private func prevPageClicked(_ sender: Any?) {
        splitViewController.documentVC.pdfView.goToPreviousPage(nil)
    }

    @objc private func nextPageClicked(_ sender: Any?) {
        splitViewController.documentVC.pdfView.goToNextPage(nil)
    }

    @objc private func pageNumberFieldAction(_ sender: NSTextField) {
        guard let doc = splitViewController.documentVC.pdfView.document else { return }
        if let pageNum = Int(sender.stringValue), pageNum >= 1, pageNum <= doc.pageCount {
            if let page = doc.page(at: pageNum - 1) {
                splitViewController.documentVC.pdfView.go(to: page)
            }
        } else {
            updatePageStatus()
        }
    }

    @objc private func zoomSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: splitViewController.documentVC.zoomOut()
        case 1: splitViewController.documentVC.zoomIn()
        case 2: splitViewController.documentVC.zoomToFit()
        default: break
        }
    }

    @objc public func toggleMarkupClicked(_ sender: Any?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            markupAccessoryVC.isHidden.toggle()
        }
        markupToolbarButton?.state = markupAccessoryVC.isHidden ? .off : .on

        if markupAccessoryVC.isHidden {
            splitViewController.documentVC.pdfView.currentTool = .select
        }
    }

    @objc public func toggleSearchClicked(_ sender: Any?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            searchAccessoryVC.isHidden.toggle()
        }
        if !searchAccessoryVC.isHidden {
            searchAccessoryVC.focusSearchField()
        } else {
            searchAccessoryVC.clearSearch()
            self.window?.makeFirstResponder(splitViewController.documentVC.pdfView)
        }
    }

    public func findNext() {
        if searchAccessoryVC.isHidden {
            searchAccessoryVC.isHidden = false
            searchAccessoryVC.focusSearchField()
        } else {
            searchAccessoryVC.findNext()
        }
    }

    public func findPrevious() {
        if searchAccessoryVC.isHidden {
            searchAccessoryVC.isHidden = false
            searchAccessoryVC.focusSearchField()
        } else {
            searchAccessoryVC.findPrevious()
        }
    }

    @objc public func copyTextWithOCRClicked(_ sender: Any?) {
        splitViewController.documentVC.pdfView.copyPageTextWithOCR()
    }

    @objc public func combinePDFClicked(_ sender: Any?) {
        splitViewController.sidebarVC.insertPagesFromFileDialog()
    }

    @objc public func openDocumentClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: self.window!) { [weak self] response in
            if response == .OK {
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                for (i, url) in panel.urls.enumerated() {
                    if i == 0 && (self?.splitViewController.documentVC.pdfView.document == nil) {
                        self?.loadDocument(from: url)
                    } else {
                        // Open in new independent window!
                        if let doc = PDFDocument(url: url) {
                            appDelegate.createNewWindow(with: doc, title: url.lastPathComponent, representedURL: url)
                        }
                    }
                }
            }
        }
    }

    @objc public func saveDocumentClicked(_ sender: Any?) {
        guard let document = splitViewController.documentVC.pdfView.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Annotated_Document.pdf"
        panel.beginSheetModal(for: self.window!) { response in
            if response == .OK, let url = panel.url {
                document.write(to: url)
            }
        }
    }

    public func loadDocument(from url: URL) {
        if let doc = PDFDocument(url: url) {
            setDocument(doc, title: url.lastPathComponent, representedURL: url)
        }
    }

    public func setDocument(_ document: PDFDocument, title: String, representedURL: URL? = nil) {
        splitViewController.documentVC.pdfView.document = document
        splitViewController.sidebarVC.pdfView = splitViewController.documentVC.pdfView
        searchAccessoryVC.pdfView = splitViewController.documentVC.pdfView
        searchAccessoryVC.clearSearch()

        self.window?.title = title
        if let url = representedURL {
            self.window?.representedURL = url
        }
        self.window?.subtitle = "\(document.pageCount) pages"

        updatePageStatus()
    }

    @objc public func updatePageStatus() {
        guard let doc = splitViewController.documentVC.pdfView.document else {
            pageNumberInputField?.stringValue = "0"
            pageTotalLabel?.stringValue = "of 0"
            return
        }
        let total = doc.pageCount
        let currentIdx: Int
        if let current = splitViewController.documentVC.pdfView.currentPage {
            currentIdx = doc.index(for: current) + 1
        } else {
            currentIdx = 1
        }

        pageNumberInputField?.stringValue = "\(currentIdx)"
        pageTotalLabel?.stringValue = "of \(total)"
        self.window?.subtitle = "\(total) pages"
        splitViewController.sidebarVC.updateHeader()
    }

    @objc private func handleRenderingModeDidChange(_ notification: Notification) {
        if let raw = notification.object as? Int, let mode = RenderingMode(rawValue: raw) {
            renderingSegmentedControl?.selectedSegment = raw
            updateWindowAppearance(for: mode)
        }
    }

    public func updateWindowAppearance(for mode: RenderingMode) {
        guard let window = self.window else { return }
        let darkAppearance = NSAppearance(named: .darkAqua)
        let bgColor: NSColor

        switch mode {
        case .clear:
            bgColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        case .negative, .negativeSepia:
            bgColor = NSColor.black
        }

        NSApp.appearance = darkAppearance
        window.appearance = darkAppearance
        window.backgroundColor = bgColor
        splitViewController.view.appearance = darkAppearance

        for view in allToolbarViews {
            view.appearance = darkAppearance
            if let stack = view as? NSStackView {
                for sub in stack.arrangedSubviews {
                    sub.appearance = darkAppearance
                }
            }
        }

        enforceDarkAppearanceOnWindowHierarchy()
    }

    public func enforceDarkAppearanceOnWindowHierarchy() {
        guard let window = self.window else { return }
        let darkAppearance = NSAppearance(named: .darkAqua)
        window.appearance = darkAppearance
        if let themeFrame = window.contentView?.superview {
            applyAppearanceRecursively(to: themeFrame, appearance: darkAppearance)
        }
    }

    private func applyAppearanceRecursively(to view: NSView, appearance: NSAppearance?) {
        view.appearance = appearance
        for subview in view.subviews {
            applyAppearanceRecursively(to: subview, appearance: appearance)
        }
    }
}
