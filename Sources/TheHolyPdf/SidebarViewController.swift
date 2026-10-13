import Cocoa
import PDFKit

/// Custom collection view item matching Apple Preview's sidebar thumbnail presentation:
/// dynamic aspect ratio card, paper drop shadow, page index badge, and accent selection ring.
open class SidebarCollectionViewItem: NSCollectionViewItem {

    public static let identifier = NSUserInterfaceItemIdentifier("SidebarCollectionViewItem")

    public var pageIndex: Int = 0

    public let cardView = NSView()
    public let thumbnailImageView = NSImageView()
    public let pageLabel = NSTextField(labelWithString: "")

    open override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        // 1. Paper card for thumbnail
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 3.5
        cardView.layer?.masksToBounds = false
        cardView.layer?.borderWidth = 0.5
        cardView.layer?.borderColor = NSColor.separatorColor.cgColor
        cardView.layer?.backgroundColor = NSColor.white.cgColor

        // Preview document drop shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.shadowBlurRadius = 3.0
        cardView.shadow = shadow

        // 2. Thumbnail image view inside card
        thumbnailImageView.wantsLayer = true
        thumbnailImageView.layer?.cornerRadius = 3.0
        thumbnailImageView.layer?.masksToBounds = true
        thumbnailImageView.imageScaling = .scaleAxesIndependently

        cardView.addSubview(thumbnailImageView)

        // 3. Page number label below card
        pageLabel.alignment = .center
        pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.drawsBackground = false
        pageLabel.isBezeled = false
        pageLabel.isEditable = false
        pageLabel.isSelectable = false

        container.addSubview(cardView)
        container.addSubview(pageLabel)
    }

    open override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    public func updateSelectionAppearance() {
        if isSelected {
            cardView.layer?.borderColor = NSColor.controlAccentColor.cgColor
            cardView.layer?.borderWidth = 2.5
            pageLabel.textColor = NSColor.labelColor
            pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        } else {
            cardView.layer?.borderColor = NSColor.separatorColor.cgColor
            cardView.layer?.borderWidth = 0.5
            pageLabel.textColor = NSColor.secondaryLabelColor
            pageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }
    }

    public func configure(page: PDFPage, index: Int, targetSize: CGSize, cachedImage: NSImage?) {
        self.pageIndex = index
        self.pageLabel.stringValue = "\(index + 1)"
        updateSelectionAppearance()

        let thumbWidth = targetSize.width
        let thumbHeight = targetSize.height

        // Bottom: page label (height 16, y: 2)
        // Top: thumbnail card (y: 22, height: thumbHeight)
        cardView.frame = NSRect(x: 0, y: 22, width: thumbWidth, height: thumbHeight)
        thumbnailImageView.frame = cardView.bounds
        pageLabel.frame = NSRect(x: 0, y: 2, width: thumbWidth, height: 16)

        if let cached = cachedImage {
            thumbnailImageView.image = cached
        } else {
            thumbnailImageView.image = nil
        }
    }
}

/// Custom subclass of NSCollectionView supporting Preview's keyboard shortcuts, context menus,
/// and drag-and-drop PDF combining.
open class PreviewSidebarCollectionView: NSCollectionView {

    public weak var sidebarController: SidebarViewController?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        registerForDraggedTypes([.fileURL])
    }

    open override var acceptsFirstResponder: Bool {
        return true
    }

    open override func keyDown(with event: NSEvent) {
        // Backspace (51) or Forward Delete (117)
        if event.keyCode == 51 || event.keyCode == 117 {
            sidebarController?.deleteSelectedPages()
            return
        }
        super.keyDown(with: event)
    }

    open override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: location) {
            selectionIndexPaths = [indexPath]
            sidebarController?.handleItemSelectionChanged()
        }

        let menu = NSMenu(title: "Page Actions")

        let deleteItem = NSMenuItem(title: "Delete Page", action: #selector(deletePageAction(_:)), keyEquivalent: "\u{08}")
        deleteItem.target = self
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let combineItem = NSMenuItem(title: "Combine with Another PDF…", action: #selector(combinePDFAction(_:)), keyEquivalent: "i")
        combineItem.keyEquivalentModifierMask = [.command, .shift]
        combineItem.target = self
        menu.addItem(combineItem)

        let insertBlankItem = NSMenuItem(title: "Insert Blank Page", action: #selector(insertBlankPageAction(_:)), keyEquivalent: "n")
        insertBlankItem.keyEquivalentModifierMask = [.command, .shift]
        insertBlankItem.target = self
        menu.addItem(insertBlankItem)

        menu.addItem(NSMenuItem.separator())

        let rotateRightItem = NSMenuItem(title: "Rotate Right", action: #selector(rotateRightAction(_:)), keyEquivalent: "r")
        rotateRightItem.keyEquivalentModifierMask = .command
        rotateRightItem.target = self
        menu.addItem(rotateRightItem)

        let rotateLeftItem = NSMenuItem(title: "Rotate Left", action: #selector(rotateLeftAction(_:)), keyEquivalent: "l")
        rotateLeftItem.keyEquivalentModifierMask = .command
        rotateLeftItem.target = self
        menu.addItem(rotateLeftItem)

        return menu
    }

    @objc private func deletePageAction(_ sender: Any?) {
        sidebarController?.deleteSelectedPages()
    }

    @objc private func combinePDFAction(_ sender: Any?) {
        sidebarController?.insertPagesFromFileDialog()
    }

    @objc private func insertBlankPageAction(_ sender: Any?) {
        sidebarController?.insertBlankPage()
    }

    @objc private func rotateRightAction(_ sender: Any?) {
        sidebarController?.rotateSelectedPages(by: 90)
    }

    @objc private func rotateLeftAction(_ sender: Any?) {
        sidebarController?.rotateSelectedPages(by: -90)
    }

    // MARK: - Drag and Drop PDF Combining

    open override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let types = sender.draggingPasteboard.types, types.contains(.fileURL) {
            return .copy
        }
        return []
    }

    open override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return false }

        let dropLocation = convert(sender.draggingLocation, from: nil)
        let targetIndex = indexPathForItem(at: dropLocation)?.item
        sidebarController?.combinePDFs(from: pdfURLs, at: targetIndex)
        return true
    }
}

/// Sidebar View Controller matching Apple Preview's PVThumbnailSidebarController architecture:
/// high-performance NSCollectionView with dynamic aspect-ratio sizing, synchronized scrolling,
/// Table of Contents outline jumping, and page operations.
open class SidebarViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {

    public weak var pdfView: FilteredPDFView? {
        didSet {
            thumbnailCache.removeAllObjects()
            collectionView.reloadData()
            outlineVC.pdfView = pdfView
            updateHeader()
            DispatchQueue.main.async { [weak self] in
                self?.synchronizeSelectionWithPDFView()
            }
        }
    }

    public let collectionView = PreviewSidebarCollectionView()
    public let scrollView = NSScrollView()
    public let outlineVC = OutlineViewController()

    private let thumbnailCache = NSCache<NSNumber, NSImage>()
    private let thumbnailQueue = DispatchQueue(label: "TheHolyPdf.ThumbnailQueue", qos: .userInteractive, attributes: .concurrent)

    private let headerBar = NSVisualEffectView()
    private let modeSegmentedControl = NSSegmentedControl()
    private let combineButton = NSButton()
    private let deleteButton = NSButton()

    private var isProgrammaticSelection: Bool = false
    private var lastRecordedWidth: CGFloat = 0

    public var selectedPages: [PDFPage] {
        guard let doc = pdfView?.document else { return [] }
        let selectedIndices = collectionView.selectionIndexPaths.map { $0.item }.sorted()
        if !selectedIndices.isEmpty {
            return selectedIndices.compactMap { doc.page(at: $0) }
        }
        if let current = pdfView?.currentPage {
            return [current]
        }
        return []
    }

    open override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        setupUI()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.sidebarController = self
        outlineVC.pdfView = pdfView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStructureChanged(_:)),
            name: .documentStructureDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePDFViewPageChanged(_:)),
            name: .PDFViewPageChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    open override func viewDidLayout() {
        super.viewDidLayout()
        let currentWidth = view.bounds.width
        if abs(currentWidth - lastRecordedWidth) > 1.0 {
            lastRecordedWidth = currentWidth
            thumbnailCache.removeAllObjects()
            collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    private func setupUI() {
        // 1. Header Bar: Inset below safeAreaLayoutGuide so it NEVER overlaps macOS traffic light buttons
        headerBar.material = .headerView
        headerBar.blendingMode = .withinWindow
        headerBar.state = .followsWindowActiveState
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        let bottomLine = CALayer()
        bottomLine.backgroundColor = NSColor.separatorColor.cgColor
        bottomLine.frame = CGRect(x: 0, y: 0, width: 1000, height: 1)
        bottomLine.autoresizingMask = [.layerWidthSizable]
        headerBar.wantsLayer = true
        headerBar.layer?.addSublayer(bottomLine)

        // Mode Switcher: Thumbnails vs Table of Contents (Outline)
        modeSegmentedControl.segmentCount = 2
        modeSegmentedControl.setImage(NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "Thumbnails")!, forSegment: 0)
        modeSegmentedControl.setImage(NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Table of Contents")!, forSegment: 1)
        modeSegmentedControl.setToolTip("Thumbnails", forSegment: 0)
        modeSegmentedControl.setToolTip("Table of Contents / Index", forSegment: 1)
        modeSegmentedControl.selectedSegment = 0
        modeSegmentedControl.target = self
        modeSegmentedControl.action = #selector(modeSegmentChanged(_:))
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // Combine / Insert PDF (+) Button
        combineButton.bezelStyle = .inline
        combineButton.image = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: "Combine PDFs")
        combineButton.isBordered = false
        combineButton.target = self
        combineButton.action = #selector(handleCombineClicked(_:))
        combineButton.toolTip = "Combine / Insert Pages from Another PDF… (⇧⌘I)"
        combineButton.translatesAutoresizingMaskIntoConstraints = false

        // Delete Page (🗑) Button
        deleteButton.bezelStyle = .inline
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Selected Page")
        deleteButton.isBordered = false
        deleteButton.target = self
        deleteButton.action = #selector(handleDeleteClicked(_:))
        deleteButton.toolTip = "Delete Selected Page (Delete / Backspace / ⌘⌫)"
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        headerBar.addSubview(modeSegmentedControl)
        headerBar.addSubview(combineButton)
        headerBar.addSubview(deleteButton)

        // 2. Collection View Configuration (Preview PVThumbnailSidebarController)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .vertical
        flowLayout.minimumLineSpacing = 12
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 14, right: 12)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(SidebarCollectionViewItem.self, forItemWithIdentifier: SidebarCollectionViewItem.identifier)

        scrollView.documentView = collectionView

        // 3. Outline View Configuration
        self.addChild(outlineVC)
        outlineVC.view.translatesAutoresizingMaskIntoConstraints = false
        outlineVC.view.isHidden = true

        view.addSubview(headerBar)
        view.addSubview(scrollView)
        view.addSubview(outlineVC.view)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 32),

            modeSegmentedControl.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 10),
            modeSegmentedControl.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -10),
            deleteButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),

            combineButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            combineButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            combineButton.widthAnchor.constraint(equalToConstant: 20),
            combineButton.heightAnchor.constraint(equalToConstant: 20),

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            outlineVC.view.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            outlineVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outlineVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outlineVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        let isOutline = (sender.selectedSegment == 1)
        scrollView.isHidden = isOutline
        outlineVC.view.isHidden = !isOutline
        combineButton.isHidden = isOutline
        deleteButton.isHidden = isOutline

        if isOutline {
            outlineVC.reloadOutline()
        }
    }

    public func updateHeader() {
        guard let document = pdfView?.document else {
            deleteButton.isEnabled = false
            return
        }
        let total = document.pageCount
        deleteButton.isEnabled = total > 1
        outlineVC.reloadOutline()
    }

    @objc private func handleDocumentStructureChanged(_ notification: Notification) {
        thumbnailCache.removeAllObjects()
        collectionView.reloadData()
        updateHeader()
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeSelectionWithPDFView()
        }
    }

    @objc private func handlePDFViewPageChanged(_ notification: Notification) {
        guard !isProgrammaticSelection else { return }
        DispatchQueue.main.async { [weak self] in
            self?.synchronizeSelectionWithPDFView()
        }
    }

    private func synchronizeSelectionWithPDFView() {
        guard let pdfView = self.pdfView,
              let doc = pdfView.document,
              let currentPage = pdfView.currentPage else { return }

        let index = doc.index(for: currentPage)
        guard index != NSNotFound && index < doc.pageCount else { return }

        // Guard against out of bounds if collectionView has not laid out items yet
        guard collectionView.numberOfSections > 0 && index < collectionView.numberOfItems(inSection: 0) else {
            return
        }

        let targetIndexPath = IndexPath(item: index, section: 0)
        if collectionView.selectionIndexPaths != [targetIndexPath] {
            collectionView.selectionIndexPaths = [targetIndexPath]
            collectionView.scrollToItems(at: [targetIndexPath], scrollPosition: .centeredVertically)
        }
        updateHeader()
    }

    public func handleItemSelectionChanged() {
        guard let first = collectionView.selectionIndexPaths.first,
              let doc = pdfView?.document,
              first.item < doc.pageCount,
              let page = doc.page(at: first.item) else { return }

        isProgrammaticSelection = true
        pdfView?.go(to: page)
        isProgrammaticSelection = false
        updateHeader()
    }

    @objc private func handleCombineClicked(_ sender: Any?) {
        insertPagesFromFileDialog()
    }

    @objc private func handleDeleteClicked(_ sender: Any?) {
        deleteSelectedPages()
    }

    // MARK: - NSCollectionViewDataSource

    public func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return pdfView?.document?.pageCount ?? 0
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(withIdentifier: SidebarCollectionViewItem.identifier, for: indexPath) as? SidebarCollectionViewItem else {
            return NSCollectionViewItem()
        }

        let pageIndex = indexPath.item
        guard let doc = pdfView?.document, pageIndex < doc.pageCount,
              let page = doc.page(at: pageIndex) else {
            return item
        }

        // Available card width inside collection view (insets: left 12, right 12)
        let availableWidth = max(70, collectionView.bounds.width - 24)
        let pageBounds = page.bounds(for: .mediaBox)
        let aspect = max(0.2, pageBounds.width / max(1, pageBounds.height))
        let thumbHeight = round(availableWidth / aspect)
        let thumbSize = CGSize(width: availableWidth, height: thumbHeight)

        let cached = thumbnailCache.object(forKey: NSNumber(value: pageIndex))
        item.configure(page: page, index: pageIndex, targetSize: thumbSize, cachedImage: cached)

        if cached == nil {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let pixelSize = CGSize(width: availableWidth * scale, height: thumbHeight * scale)
            let cacheKey = NSNumber(value: pageIndex)

            thumbnailQueue.async { [weak self, weak item] in
                let thumbImage = page.thumbnail(of: pixelSize, for: .mediaBox)
                DispatchQueue.main.async {
                    self?.thumbnailCache.setObject(thumbImage, forKey: cacheKey)
                    if item?.pageIndex == pageIndex {
                        item?.thumbnailImageView.image = thumbImage
                    }
                }
            }
        }

        return item
    }

    // MARK: - NSCollectionViewDelegateFlowLayout

    public func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        let availableWidth = max(70, collectionView.bounds.width - 24)
        guard let doc = pdfView?.document, indexPath.item < doc.pageCount,
              let page = doc.page(at: indexPath.item) else {
            return NSSize(width: availableWidth, height: round(availableWidth * 1.3) + 22)
        }
        let pageBounds = page.bounds(for: .mediaBox)
        let aspect = max(0.2, pageBounds.width / max(1, pageBounds.height))
        let thumbHeight = round(availableWidth / aspect)
        return NSSize(width: availableWidth, height: thumbHeight + 22)
    }

    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        handleItemSelectionChanged()
    }

    // MARK: - Page Deletion with Guaranteed Refresh & Undo

    public func deleteSelectedPages() {
        guard let pdfView = self.pdfView,
              let document = pdfView.document else { return }

        var pagesToDelete: [PDFPage] = []
        let selected = selectedPages
        if !selected.isEmpty {
            pagesToDelete = selected
        } else if let current = pdfView.currentPage {
            pagesToDelete = [current]
        }

        guard !pagesToDelete.isEmpty else { return }

        // Prevent removing all pages
        if document.pageCount <= pagesToDelete.count {
            let alert = NSAlert()
            alert.messageText = "Cannot Delete All Pages"
            alert.informativeText = "A PDF document must contain at least one page."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = self.view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }

        var records: [(page: PDFPage, index: Int)] = []
        for page in pagesToDelete {
            let idx = document.index(for: page)
            if idx != NSNotFound {
                records.append((page: page, index: idx))
            }
        }
        guard !records.isEmpty else { return }

        records.sort { $0.index > $1.index }
        let earliestDeletedIndex = records.last!.index
        let targetLandingIndex = max(0, min(earliestDeletedIndex, document.pageCount - records.count - 1))

        for record in records {
            document.removePage(at: record.index)
        }

        self.undoManager?.registerUndo(withTarget: self) { target in
            for r in records.sorted(by: { $0.index < $1.index }) {
                document.insert(r.page, at: min(r.index, document.pageCount))
            }
            target.refreshAfterDocumentStructureChange(landingIndex: earliestDeletedIndex)
        }
        self.undoManager?.setActionName("Delete Page")

        refreshAfterDocumentStructureChange(landingIndex: targetLandingIndex)
    }

    // MARK: - Combine / Insert PDFs

    public func insertPagesFromFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Combine"
        panel.message = "Select one or more PDF files to combine with this document:"

        let targetWindow = self.view.window ?? NSApp.mainWindow ?? NSApp.windows.first
        guard let window = targetWindow else { return }

        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK {
                self?.combinePDFs(from: panel.urls)
            }
        }
    }

    public func combinePDFs(from urls: [URL], at targetIndex: Int? = nil) {
        guard let pdfView = self.pdfView, let document = pdfView.document else { return }

        let insertionPoint: Int
        if let explicit = targetIndex {
            insertionPoint = explicit
        } else if let current = pdfView.currentPage {
            insertionPoint = document.index(for: current) + 1
        } else {
            insertionPoint = document.pageCount
        }

        var currentIndex = insertionPoint
        var insertedRecords: [(page: PDFPage, index: Int)] = []

        for url in urls {
            guard let externalDoc = PDFDocument(url: url) else { continue }
            for i in 0..<externalDoc.pageCount {
                guard let page = externalDoc.page(at: i) else { continue }
                document.insert(page, at: currentIndex)
                insertedRecords.append((page: page, index: currentIndex))
                currentIndex += 1
            }
        }

        guard !insertedRecords.isEmpty else { return }

        self.undoManager?.registerUndo(withTarget: self) { target in
            for r in insertedRecords.reversed() {
                document.removePage(at: r.index)
            }
            target.refreshAfterDocumentStructureChange(landingIndex: max(0, insertionPoint - 1))
        }
        self.undoManager?.setActionName("Combine PDFs")

        refreshAfterDocumentStructureChange(landingIndex: insertionPoint)
    }

    public func rotateSelectedPages(by degrees: Int) {
        guard let pdfView = self.pdfView, pdfView.document != nil else { return }

        let targetPages = selectedPages
        for page in targetPages {
            let currentRotation = page.rotation
            let newRotation = (currentRotation + degrees + 360) % 360
            page.rotation = newRotation

            self.undoManager?.registerUndo(withTarget: self) { target in
                page.rotation = currentRotation
                target.thumbnailCache.removeAllObjects()
                target.collectionView.reloadData()
            }
        }
        self.undoManager?.setActionName("Rotate Page")
        thumbnailCache.removeAllObjects()
        collectionView.reloadData()
        pdfView.needsDisplay = true
    }

    public func insertBlankPage() {
        guard let pdfView = self.pdfView, let document = pdfView.document else { return }

        let targetIndex: Int
        if let current = pdfView.currentPage {
            targetIndex = document.index(for: current) + 1
        } else {
            targetIndex = document.pageCount
        }

        let defaultPageSize = document.page(at: 0)?.bounds(for: .mediaBox).size ?? CGSize(width: 612, height: 792)
        let blankImage = NSImage(size: defaultPageSize)
        blankImage.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: defaultPageSize).fill()
        blankImage.unlockFocus()

        if let newPage = PDFPage(image: blankImage) {
            document.insert(newPage, at: targetIndex)

            self.undoManager?.registerUndo(withTarget: self) { target in
                document.removePage(at: targetIndex)
                target.refreshAfterDocumentStructureChange(landingIndex: max(0, targetIndex - 1))
            }
            self.undoManager?.setActionName("Insert Blank Page")

            refreshAfterDocumentStructureChange(landingIndex: targetIndex)
        }
    }

    public func refreshAfterDocumentStructureChange(landingIndex: Int) {
        guard let pdfView = self.pdfView, let document = pdfView.document else { return }

        thumbnailCache.removeAllObjects()
        pdfView.layoutDocumentView()

        if landingIndex >= 0 && landingIndex < document.pageCount,
           let page = document.page(at: landingIndex) {
            pdfView.go(to: page)
        }

        collectionView.reloadData()

        let validLanding = max(0, min(landingIndex, document.pageCount - 1))
        let targetIndexPath = IndexPath(item: validLanding, section: 0)
        collectionView.selectionIndexPaths = [targetIndexPath]
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.collectionView.numberOfSections > 0 && validLanding < self.collectionView.numberOfItems(inSection: 0) {
                self.collectionView.scrollToItems(at: [targetIndexPath], scrollPosition: .centeredVertically)
            }
        }

        updateHeader()
        NotificationCenter.default.post(name: .documentStructureDidChangeNotification, object: document)
    }
}
