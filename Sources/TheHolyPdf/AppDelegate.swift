import Cocoa
import PDFKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    public private(set) var windowControllers: [MainWindowController] = []
    private var didOpenInitialFiles: Bool = false
    private var currentOpenPanel: NSOpenPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        // Bring application to front
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)

        // When opened directly, prompt user with an Open dialog (typical macOS Preview launch behavior)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.windowControllers.isEmpty && !self.didOpenInitialFiles {
                self.showInitialOpenPanel()
            }
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        didOpenInitialFiles = true
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            if let doc = PDFDocument(url: url) {
                _ = createNewWindow(with: doc, title: url.lastPathComponent, representedURL: url)
            }
        }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        didOpenInitialFiles = true
        let url = URL(fileURLWithPath: filename)
        if let doc = PDFDocument(url: url) {
            _ = createNewWindow(with: doc, title: url.lastPathComponent, representedURL: url)
            return true
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if windowControllers.isEmpty {
                showInitialOpenPanel()
            } else {
                for wc in windowControllers {
                    wc.window?.makeKeyAndOrderFront(nil)
                }
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay open like Preview when windows are closed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Initial Open Document Prompt (cmd + O on launch)

    public func showInitialOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open PDF"
        panel.message = "Select a PDF document to open in TheHolyPdf:"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        // Accessory View providing an "Open Sample Document" button
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        let sampleBtn = NSButton(title: "Open Sample Document", target: self, action: #selector(openSampleFromPanel(_:)))
        sampleBtn.bezelStyle = .rounded
        sampleBtn.frame = NSRect(x: 10, y: 2, width: 200, height: 28)
        accessory.addSubview(sampleBtn)
        panel.accessoryView = accessory

        currentOpenPanel = panel
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { [weak self] response in
            guard let self = self else { return }
            self.currentOpenPanel = nil
            if response == .OK && !panel.urls.isEmpty {
                for url in panel.urls {
                    if let doc = PDFDocument(url: url) {
                        self.createNewWindow(with: doc, title: url.lastPathComponent, representedURL: url)
                    }
                }
            } else if self.windowControllers.isEmpty {
                // If user cancels and no window is open, open the sample document
                self.createNewWindow()
            }
        }
    }

    @objc private func openSampleFromPanel(_ sender: Any?) {
        currentOpenPanel?.cancel(nil)
        currentOpenPanel = nil
        createNewWindow()
    }

    // MARK: - Multi-Window Management

    @discardableResult
    public func createNewWindow(with document: PDFDocument? = nil, title: String? = nil, representedURL: URL? = nil) -> MainWindowController {
        let wc = MainWindowController()
        windowControllers.append(wc)

        let doc = document ?? SampleDocumentGenerator.createSampleDocument()
        let docTitle = title ?? (document == nil ? "Sample_Document.pdf" : "Untitled.pdf")

        wc.setDocument(doc, title: docTitle, representedURL: representedURL)
        wc.showWindow(nil)

        if let window = wc.window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)
        return wc
    }

    public func removeWindowController(_ wc: MainWindowController) {
        windowControllers.removeAll { $0 === wc }
    }

    // MARK: - Preview-style Top Menu Bar Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu ( TheHolyPdf)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "TheHolyPdf")
        appMenu.addItem(withTitle: "About TheHolyPdf", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings…", action: nil, keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide TheHolyPdf", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit TheHolyPdf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window (Sample Doc)", action: #selector(newSampleDocumentAction(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocumentAction(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Combine / Insert Pages from File…", action: #selector(combinePDFAction(_:)), keyEquivalent: "i")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save…", action: #selector(saveDocumentAction(_:)), keyEquivalent: "s")
        fileMenuItem.submenu = fileMenu

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        
        let ocrCopyItem = NSMenuItem(title: "Copy Text with OCR (Handwriting & Scans)", action: #selector(copyTextWithOCRAction(_:)), keyEquivalent: "c")
        ocrCopyItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(ocrCopyItem)

        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())

        // Find Submenu (Preview Find UX)
        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(withTitle: "Find…", action: #selector(findAction(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: "Find Next", action: #selector(findNextAction(_:)), keyEquivalent: "g")
        let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(findPreviousAction(_:)), keyEquivalent: "g")
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        findMenu.addItem(findPrevItem)
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)

        editMenu.addItem(NSMenuItem.separator())
        let deletePageItem = NSMenuItem(title: "Delete Page", action: #selector(deletePageAction(_:)), keyEquivalent: "\u{08}")
        editMenu.addItem(deletePageItem)
        let deleteAnnotItem = NSMenuItem(title: "Delete Annotation", action: #selector(deleteAnnotationAction(_:)), keyEquivalent: "\u{7f}")
        editMenu.addItem(deleteAnnotItem)
        editMenuItem.submenu = editMenu

        // 4. View Menu (Negative Rendering Modes & Preview Sidebars)
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let toggleSidebarItem = NSMenuItem(title: "Thumbnails Sidebar", action: #selector(toggleSidebarAction(_:)), keyEquivalent: "1")
        toggleSidebarItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleSidebarItem)

        let toggleMarkupItem = NSMenuItem(title: "Show Markup Toolbar", action: #selector(toggleMarkupAction(_:)), keyEquivalent: "a")
        toggleMarkupItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(toggleMarkupItem)

        viewMenu.addItem(NSMenuItem.separator())

        // Rendering Modes: Normal and Dark
        let clearMode = NSMenuItem(title: "Normal Mode", action: #selector(setClearModeAction(_:)), keyEquivalent: "1")
        viewMenu.addItem(clearMode)

        let darkMode = NSMenuItem(title: "Dark Mode", action: #selector(setDarkModeAction(_:)), keyEquivalent: "2")
        viewMenu.addItem(darkMode)

        viewMenu.addItem(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomInAction(_:)), keyEquivalent: "+")
        viewMenu.addItem(zoomInItem)
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutAction(_:)), keyEquivalent: "-")
        viewMenu.addItem(zoomOutItem)
        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(actualSizeAction(_:)), keyEquivalent: "0")
        viewMenu.addItem(actualSizeItem)
        let zoomToFitItem = NSMenuItem(title: "Zoom to Fit", action: #selector(zoomToFitAction(_:)), keyEquivalent: "9")
        viewMenu.addItem(zoomToFitItem)

        viewMenuItem.submenu = viewMenu

        // 5. Tools Menu (Preview-style Tools)
        let toolsMenuItem = NSMenuItem()
        mainMenu.addItem(toolsMenuItem)
        let toolsMenu = NSMenu(title: "Tools")

        toolsMenu.addItem(withTitle: "Text Selection", action: #selector(selectPointerToolAction(_:)), keyEquivalent: "")
        toolsMenu.addItem(NSMenuItem.separator())

        // Annotate Submenu
        let annotateMenuItem = NSMenuItem(title: "Annotate", action: nil, keyEquivalent: "")
        let annotateMenu = NSMenu(title: "Annotate")
        annotateMenu.addItem(withTitle: "Text Box", action: #selector(selectTextToolAction(_:)), keyEquivalent: "t")
        annotateMenu.addItem(withTitle: "Freehand Pen", action: #selector(selectPenToolAction(_:)), keyEquivalent: "p")
        annotateMenu.addItem(withTitle: "Highlight Text", action: #selector(selectHighlightToolAction(_:)), keyEquivalent: "h")
        annotateMenu.addItem(NSMenuItem.separator())
        annotateMenu.addItem(withTitle: "Rectangle", action: #selector(selectRectToolAction(_:)), keyEquivalent: "r")
        annotateMenu.addItem(withTitle: "Circle / Oval", action: #selector(selectCircleToolAction(_:)), keyEquivalent: "c")
        annotateMenu.addItem(withTitle: "Line", action: #selector(selectLineToolAction(_:)), keyEquivalent: "l")
        annotateMenuItem.submenu = annotateMenu
        toolsMenu.addItem(annotateMenuItem)

        toolsMenu.addItem(NSMenuItem.separator())
        let combineToolsItem = NSMenuItem(title: "Combine with Another PDF…", action: #selector(combinePDFAction(_:)), keyEquivalent: "i")
        combineToolsItem.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.addItem(combineToolsItem)

        let rotateRightItem = NSMenuItem(title: "Rotate Right", action: #selector(rotateRightAction(_:)), keyEquivalent: "r")
        rotateRightItem.keyEquivalentModifierMask = [.command]
        toolsMenu.addItem(rotateRightItem)

        let rotateLeftItem = NSMenuItem(title: "Rotate Left", action: #selector(rotateLeftAction(_:)), keyEquivalent: "l")
        rotateLeftItem.keyEquivalentModifierMask = [.command]
        toolsMenu.addItem(rotateLeftItem)

        let insertBlankItem = NSMenuItem(title: "Insert Blank Page", action: #selector(insertBlankPageAction(_:)), keyEquivalent: "n")
        insertBlankItem.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.addItem(insertBlankItem)

        toolsMenuItem.submenu = toolsMenu

        // 6. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // 7. Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "TheHolyPdf Help", action: #selector(showHelpAction(_:)), keyEquivalent: "?")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private var activeWindowController: MainWindowController? {
        if let keyWin = NSApp.keyWindow {
            return windowControllers.first { $0.window === keyWin }
        }
        return windowControllers.last
    }

    // MARK: - Menu Handlers

    @objc private func newSampleDocumentAction(_ sender: Any?) {
        _ = createNewWindow()
    }

    @objc private func openDocumentAction(_ sender: Any?) {
        showInitialOpenPanel()
    }

    @objc private func combinePDFAction(_ sender: Any?) {
        activeWindowController?.splitViewController.sidebarVC.insertPagesFromFileDialog()
    }

    @objc private func findAction(_ sender: Any?) {
        activeWindowController?.toggleSearchClicked(sender)
    }

    @objc private func findNextAction(_ sender: Any?) {
        activeWindowController?.findNext()
    }

    @objc private func findPreviousAction(_ sender: Any?) {
        activeWindowController?.findPrevious()
    }

    @objc private func copyTextWithOCRAction(_ sender: Any?) {
        activeWindowController?.copyTextWithOCRClicked(sender)
    }

    @objc private func saveDocumentAction(_ sender: Any?) {
        activeWindowController?.saveDocumentClicked(sender)
    }

    @objc private func toggleSidebarAction(_ sender: Any?) {
        activeWindowController?.splitViewController.toggleSidebar()
    }

    @objc private func toggleMarkupAction(_ sender: Any?) {
        activeWindowController?.toggleMarkupClicked(sender)
    }

    @objc private func deletePageAction(_ sender: Any?) {
        activeWindowController?.splitViewController.sidebarVC.deleteSelectedPages()
    }

    @objc private func deleteAnnotationAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.deleteSelectedAnnotation()
    }

    @objc private func rotateRightAction(_ sender: Any?) {
        activeWindowController?.splitViewController.sidebarVC.rotateSelectedPages(by: 90)
    }

    @objc private func rotateLeftAction(_ sender: Any?) {
        activeWindowController?.splitViewController.sidebarVC.rotateSelectedPages(by: -90)
    }

    @objc private func insertBlankPageAction(_ sender: Any?) {
        activeWindowController?.splitViewController.sidebarVC.insertBlankPage()
    }

    @objc private func selectPointerToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .select
    }

    @objc private func selectTextToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .text
    }

    @objc private func selectPenToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .freehand
    }

    @objc private func selectHighlightToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .highlight
    }

    @objc private func selectRectToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .rectangle
    }

    @objc private func selectCircleToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .circle
    }

    @objc private func selectLineToolAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.currentTool = .line
    }

    @objc private func setClearModeAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.renderingMode = .clear
        NotificationCenter.default.post(name: .changeRenderingModeNotification, object: RenderingMode.clear.rawValue)
    }

    @objc private func setDarkModeAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.pdfView.renderingMode = .dark
        NotificationCenter.default.post(name: .changeRenderingModeNotification, object: RenderingMode.dark.rawValue)
    }

    @objc private func zoomInAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.zoomIn()
    }

    @objc private func zoomOutAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.zoomOut()
    }

    @objc private func actualSizeAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.actualSize()
    }

    @objc private func zoomToFitAction(_ sender: Any?) {
        activeWindowController?.splitViewController.documentVC.zoomToFit()
    }

    @objc private func showHelpAction(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "TheHolyPdf Help"
        alert.informativeText = """
        • Search with Vision OCR: Press ⌘F (or click the 🔍 Search button) to find text across both vector and scanned/handwritten documents.
        • Copy Handwritten & Scanned Text: Press ⇧⌘C or right-click to copy text from any page via on-device Vision OCR.
        • Table of Contents / Outline: Click the Index icon (☰) in the sidebar to jump directly to document sections and chapters.
        • Multi-Document Support: Press ⌘O to open one or multiple PDF documents into separate windows.
        • Combine PDFs: Drag and drop any PDF from Finder directly into the thumbnail sidebar, or choose File > Combine / Insert Pages from File… (⇧⌘I).
        • Delete Pages: Click any page thumbnail and press Delete / Backspace (or ⌘⌫) to delete. Press ⌘Z to undo!
        • Color Modes: Press ⌘1 for Normal Mode and ⌘2 for Dark Mode.
        • Markup Toolbar: Press ⇧⌘A or click the pencil icon to toggle the annotation bar.
        """
        alert.addButton(withTitle: "OK")
        if let window = activeWindowController?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
