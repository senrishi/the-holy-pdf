import Cocoa

/// Rendering modes matching Negative.app's core engine
@objc public enum RenderingMode: Int, CaseIterable {
    case clear = 0          // Standard AppKit default appearance
    case negative = 1       // CIColorInvert + CISharpenLuminance
    case negativeSepia = 2  // CIColorInvert + CISharpenLuminance + CISepiaTone

    public var title: String {
        switch self {
        case .clear: return "Normal"
        case .negative: return "Negative"
        case .negativeSepia: return "Sepia"
        }
    }
}

extension Notification.Name {
    /// Notification posted when the user toggles the rendering mode
    public static let changeRenderingModeNotification = Notification.Name("pl.mackozer.negative.changeRenderingModeNotification")
    
    /// Notification posted when auto system appearance synchronization is toggled
    public static let shouldSystemChangeColorNotification = Notification.Name("pl.mackozer.negative.shouldSystemChangeColorModeNotification")
    
    /// Notification posted when active markup tool changes
    public static let markupToolDidChangeNotification = Notification.Name("TheHolyPdf.markupToolDidChangeNotification")
    
    /// Notification posted when document page count or layout changes
    public static let documentStructureDidChangeNotification = Notification.Name("TheHolyPdf.documentStructureDidChangeNotification")

    /// Notification posted when selected annotation changes
    public static let annotationSelectionDidChangeNotification = Notification.Name("TheHolyPdf.annotationSelectionDidChangeNotification")
}

/// Available interactive annotation tools mirroring Preview's Markup bar
@objc public enum MarkupTool: Int, CaseIterable {
    case select = 0
    case text = 1
    case freehand = 2
    case rectangle = 3
    case circle = 4
    case line = 5
    case highlight = 6
    case underline = 7
    case strikethrough = 8

    public var title: String {
        switch self {
        case .select: return "Selection / Pointer"
        case .text: return "Text Box"
        case .freehand: return "Pen / Draw"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle / Oval"
        case .line: return "Line"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .select: return "arrow.up.left"
        case .text: return "textformat"
        case .freehand: return "pencil.tip"
        case .rectangle: return "square"
        case .circle: return "circle"
        case .line: return "line.diagonal"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        }
    }
}
