# TheHolyPdf

A native macOS AppKit application combining the **hardware-accelerated Core Image rendering engine of Negative.app** with the **UI/UX, thumbnail sidebar, and markup architecture of Apple Preview**.

---

## Architecture Overview

```
                                  [NSApplication]
                                         │
                                  [AppDelegate]
                                         │
                              [MainWindowController]
                                         │
                    ┌────────────────────┴────────────────────┐
                    ▼                                         ▼
         [MainSplitViewController]           [MarkupToolbarViewController]
                    │                        (NSTitlebarAccessoryViewController)
          ┌─────────┴─────────┐              (Text, Pen, Shapes, Color Wells)
          ▼                   ▼
[SidebarViewController] [DocumentViewController]
  (PDFThumbnailView)           │
  (Select, Delete,      [FilteredPDFView]
   Rotate, Add Pages)   (Negative's CALayer Filter Engine)
```

---

## Key Features & Reverse-Engineered Implementations

### 1. Negative's Exact Rendering Filter Pipeline
Directly reconstructed from [`Negative.app`](/Applications/Negative.app) (Mach-O ARM64 IMP `0x10000c810`):
* **Hardware Layer Filtering (`CALayer.filters`)**:
  * **Normal Mode (`0`)**: Clears all Core Animation filters (`filters = nil`), sets `backgroundColor = NSColor.windowBackgroundColor`.
  * **Negative Mode (`1`)**: Sets `backgroundColor = NSColor.white` (inverts to `#000000`), instantiates and applies `[CIColorInvert, CISharpenLuminance]` to `pdfView.layer?.filters`.
  * **Negative Sepia Mode (`2`)**: Sets `backgroundColor = NSColor.white`, instantiates and applies `[CIColorInvert, CISharpenLuminance, CISepiaTone]`.
* **Zero Geometry Mutation**:
  * Because the filters run in the GPU composition pass, PDF page geometries, glyph metrics, and text structures remain untouched.
  * Native text selection, cursor rects, drag-to-select, copy-paste, and 120Hz inertial scrolling remain fully functional without interference.
* **macOS System Appearance Tracking**:
  * Overrides `viewDidChangeEffectiveAppearance()` to match system Aqua vs. Dark Aqua appearances dynamically if enabled.

### 2. Preview.app UI/UX & Thumbnail Sidebar
* **Full `PDFThumbnailView` Sidebar**:
  * Embedded in a collapsible `NSSplitViewController`.
  * Multi-page selection and live navigation.
* **Page Deletion (`⌘⌫` or `Delete` / `Backspace`)**:
  * Select any thumbnail(s) and press Delete or click the trash button to delete pages.
  * Full `NSUndoManager` integration: press `⌘Z` to undo page deletion or `⇧⌘Z` to redo.
* **Page Rotation & Blank Page Insertion**:
  * Context menu and keyboard shortcuts to Rotate Left (`⌘L`), Rotate Right (`⌘R`), or Insert Blank Page (`⇧⌘N`).

### 3. Preview-style Markup Bar (`NSTitlebarAccessoryViewController`)
* Implemented as an AppKit window accessory controller docked directly below the titlebar (matching Preview's `PVEditBannerViewController`).
* **Supported Annotations**:
  * **Text Box**: FreeText annotations (`PDFAnnotation(forType: .freeText)`).
  * **Freehand Pen**: Ink annotations (`PDFAnnotation(forType: .ink)`).
  * **Shapes**: Rectangles (`.square`), Circles/Ovals (`.circle`), Lines (`.line`).
  * **Text Markup**: Highlight (`.highlight`), Underline (`.underline`), Strikethrough (`.strikeOut`).
* **Formatting Controls**:
  * Stroke Color Well & Fill Color Well.
  * Line Width selector (1pt, 2pt, 3pt, 5pt, 8pt).
  * Font Size selector (10pt, 12pt, 14pt, 18pt, 24pt).
  * Delete Selected Annotation (`⌫`).

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘1` | Normal Mode (Original PDF colors) |
| `⌘2` | Negative Mode (Inverted + Sharpened) |
| `⌘3` | Negative Sepia Mode (Inverted + Sepia) |
| `⌥⌘1` | Toggle Left Thumbnail Sidebar |
| `⇧⌘A` | Toggle Markup Accessory Bar |
| `⌫` / `Delete` | Delete Selected Page (in sidebar) or Selected Annotation |
| `⌘O` | Open PDF Document |
| `⌘S` | Save Annotated PDF Document |
| `⌘Z` / `⇧⌘Z` | Undo / Redo |
| `⌘+` / `⌘-` / `⌘0` | Zoom In / Zoom Out / Actual Size |

---

## How to Build and Run

From `/Users/rishi/DEV/TheHolyPdf`:

```bash
# Compile and create TheHolyPdf.app bundle
./build_app.sh

# Run the app
open TheHolyPdf.app
```
