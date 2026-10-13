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
        sidebarSplitItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarSplitItem.minimumThickness = 120
        sidebarSplitItem.maximumThickness = 360
        sidebarSplitItem.preferredThicknessFraction = 0.17
        sidebarSplitItem.canCollapse = true

        documentSplitItem = NSSplitViewItem(viewController: documentVC)

        self.addSplitViewItem(sidebarSplitItem)
        self.addSplitViewItem(documentSplitItem)

        // Connect views
        sidebarVC.pdfView = documentVC.pdfView

        self.splitView.dividerStyle = .thin
    }

    public func toggleSidebar() {
        sidebarSplitItem.animator().isCollapsed.toggle()
    }
}
