import SwiftUI

enum PDFExporter {
    /// Renders a SwiftUI view to a real vector PDF (not a rasterized image) by driving
    /// `ImageRenderer`'s callback with a PDF-backed `CGContext` instead of a bitmap one.
    @MainActor
    static func render(_ view: some View, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.render { renderSize, renderCallback in
            var box = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdfContext = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            renderCallback(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
    }
}
