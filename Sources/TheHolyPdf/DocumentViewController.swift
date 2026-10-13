import Cocoa
import PDFKit

/// Document View Controller hosting the FilteredPDFView and coordinating page display
open class DocumentViewController: NSViewController {

    public let pdfView = FilteredPDFView()

    open override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        self.view = container

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func pageDidChange(_ notification: Notification) {
        // Triggers UI update for page status
    }

    public func zoomIn() {
        pdfView.zoomIn(nil)
    }

    public func zoomOut() {
        pdfView.zoomOut(nil)
    }

    public func actualSize() {
        pdfView.scaleFactor = 1.0
        pdfView.autoScales = false
    }

    public func zoomToFit() {
        pdfView.autoScales = true
    }
}
