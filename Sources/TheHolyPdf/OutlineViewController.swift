import Cocoa
import PDFKit

/// Table of Contents / Outline View Controller providing topic-based page navigation
open class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    public weak var pdfView: FilteredPDFView? {
        didSet {
            reloadOutline()
        }
    }

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let placeholderLabel = NSTextField(labelWithString: "No Table of Contents in this document.\nUse Thumbnails or Search (⌘F) to navigate.")

    open override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        setupUI()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.autoresizesOutlineColumn = true
        outlineView.backgroundColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        view.addSubview(scrollView)

        // Placeholder for PDFs without outline metadata
        placeholderLabel.font = NSFont.systemFont(ofSize: 12)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isHidden = true
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
    }

    public func reloadOutline() {
        guard let doc = pdfView?.document, let root = doc.outlineRoot, root.numberOfChildren > 0 else {
            placeholderLabel.isHidden = false
            scrollView.isHidden = true
            return
        }

        placeholderLabel.isHidden = true
        scrollView.isHidden = false
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return pdfView?.document?.outlineRoot?.numberOfChildren ?? 0
        }
        if let outlineItem = item as? PDFOutline {
            return outlineItem.numberOfChildren
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return pdfView?.document?.outlineRoot?.child(at: index) as Any
        }
        if let outlineItem = item as? PDFOutline {
            return outlineItem.child(at: index) as Any
        }
        return ""
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let outlineItem = item as? PDFOutline {
            return outlineItem.numberOfChildren > 0
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let outlineItem = item as? PDFOutline else { return nil }

        let cellIdentifier = NSUserInterfaceItemIdentifier("OutlineCell")
        var cellView = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellIdentifier

            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 6
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(stack)

            let titleField = NSTextField(labelWithString: "")
            titleField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false

            let pageBadge = NSTextField(labelWithString: "")
            pageBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            pageBadge.textColor = .secondaryLabelColor
            pageBadge.translatesAutoresizingMaskIntoConstraints = false

            stack.addArrangedSubview(titleField)
            stack.addArrangedSubview(pageBadge)
            cellView?.textField = titleField

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                stack.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        cellView?.textField?.stringValue = outlineItem.label ?? "Untitled Topic"

        // Determine target page number
        var pageNumStr = ""
        if let dest = outlineItem.destination, let page = dest.page, let doc = pdfView?.document {
            let idx = doc.index(for: page)
            if idx != NSNotFound {
                pageNumStr = "p. \(idx + 1)"
            }
        } else if let action = outlineItem.action as? PDFActionGoTo, let page = action.destination.page, let doc = pdfView?.document {
            let idx = doc.index(for: page)
            if idx != NSNotFound {
                pageNumStr = "p. \(idx + 1)"
            }
        }

        if let stack = cellView?.subviews.first as? NSStackView, stack.arrangedSubviews.count >= 2,
           let badgeField = stack.arrangedSubviews[1] as? NSTextField {
            badgeField.stringValue = pageNumStr
        }

        return cellView
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let outlineItem = outlineView.item(atRow: selectedRow) as? PDFOutline,
              let pdfView = self.pdfView else { return }

        // Topic-wise page jump
        if let dest = outlineItem.destination {
            pdfView.go(to: dest)
        } else if let action = outlineItem.action as? PDFActionGoTo {
            pdfView.go(to: action.destination)
        }
    }
}
