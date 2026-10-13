import Cocoa
import PDFKit

/// Main split view controller dividing the thumbnail sidebar and document canvas
open class MainSplitViewController: NSSplitViewController {

    public let sidebarVC = SidebarViewController()
    public let documentVC = DocumentViewController()

    public private(set) var sidebarSplitItem: NSSplitViewItem!
    public private(set) var documentSplitItem: NSSplitViewItem!

    open override func viewDidLoad() {
        super.viewDidLoad()

        // Configure Split Items
        sidebarSplitItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarSplitItem.minimumThickness = 120
        sidebarSplitItem.maximumThickness = 360
        sidebarSplitItem.preferredThicknessFraction = 0.17
        sidebarSplitItem.canCollapse = true
        sidebarSplitItem.holdingPriority = .defaultLow + 1

        documentSplitItem = NSSplitViewItem(viewController: documentVC)

        self.addSplitViewItem(sidebarSplitItem)
        self.addSplitViewItem(documentSplitItem)

        // Connect views
        sidebarVC.pdfView = documentVC.pdfView

        self.splitView.dividerStyle = .thin
    }

    open override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        if let wc = self.view.window?.windowController as? MainWindowController {
            wc.enforceDarkAppearanceOnWindowHierarchy()
        }
    }

    public func toggleSidebar() {
        sidebarSplitItem.animator().isCollapsed.toggle()
        DispatchQueue.main.async { [weak self] in
            if let wc = self?.view.window?.windowController as? MainWindowController {
                wc.enforceDarkAppearanceOnWindowHierarchy()
            }
        }
    }
}
