import CoreGraphics
import CoreText
import Foundation

@MainActor
final class PDFSignatureFont {
    let graphicsFont: CGFont
    let glyph: CGGlyph

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "SignatureFont", withExtension: "otf"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else { throw PDFProcessingError.failed }
        var character = Array("\u{201A}".utf16)
        var mapped = CGGlyph()
        let coreText = CTFontCreateWithGraphicsFont(font, 50, nil, nil)
        guard CTFontGetGlyphsForCharacters(coreText, &character, &mapped, 1), mapped != 0 else {
            throw PDFProcessingError.failed
        }
        graphicsFont = font
        glyph = mapped
    }

    func coreTextFont(size: CGFloat) -> CTFont {
        CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
    }

    func relativeGlyphBounds(size: CGFloat) -> CGRect {
        var glyph = glyph
        var bounds = CGRect.zero
        _ = CTFontGetBoundingRectsForGlyphs(coreTextFont(size: size), .default, &glyph, &bounds, 1)
        return bounds.standardized
    }
}
