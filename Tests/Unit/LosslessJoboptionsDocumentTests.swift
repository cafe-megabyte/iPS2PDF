import Foundation
import XCTest

final class LosslessJoboptionsDocumentTests: XCTestCase {
    func testEveryBundledJoboptionsRoundTripsWithoutChanges() throws {
        let directory = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Joboptions", withExtension: nil)
        )
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "joboptions" }

        XCTAssertEqual(urls.count, 14)
        for url in urls {
            let original = try Data(contentsOf: url)
            XCTAssertEqual(try LosslessJoboptionsDocument(data: original).data, original, url.lastPathComponent)
        }
    }

    func testLastDuplicateOccurrenceIsDisplayedAndEdited() throws {
        let original = Data("%!PS\n<< /Quality 1 /Untouched (keep) /Quality 2 >> setdistillerparams\n".utf8)
        let document = try LosslessJoboptionsDocument(data: original)

        XCTAssertEqual(document.value(forKey: "Quality")?.numberValue, 2)
        let edited = try document.replacingValue(
            forKey: "Quality",
            with: .number(3, original: "3")
        )
        let text = try XCTUnwrap(String(data: edited.data, encoding: .utf8))

        XCTAssertTrue(text.contains("/Quality 1"))
        XCTAssertTrue(text.contains("/Quality 3"))
        XCTAssertTrue(text.contains("/Untouched (keep)"))
        XCTAssertFalse(text.contains("/Quality 2"))
    }

    func testLastAllowTransparencyOccurrenceControlsTheEffectiveValue() throws {
        let original = Data("<< /AllowTransparency false /AllowTransparency true >> setdistillerparams\n".utf8)
        let document = try LosslessJoboptionsDocument(data: original)

        XCTAssertEqual(document.value(forKey: "AllowTransparency")?.boolValue, true)
    }

    func testLastAutoPositionEPSFilesOccurrenceControlsTheEffectiveValue() throws {
        let original = Data(
            "<< /AutoPositionEPSFiles false /AutoPositionEPSFiles true >> setdistillerparams\n".utf8
        )
        let document = try LosslessJoboptionsDocument(data: original)

        XCTAssertEqual(document.value(forKey: "AutoPositionEPSFiles")?.boolValue, true)
    }

    func testMissingValueInsertionPreservesCRLF() throws {
        let original = Data("%!PS\r\n<<\r\n  /Existing true\r\n>> setdistillerparams\r\n".utf8)
        let edited = try LosslessJoboptionsDocument(data: original)
            .replacingValue(forKey: "Added", with: .string("value"))
        let bytes = [UInt8](edited.data)

        for index in bytes.indices where bytes[index] == 0x0A {
            XCTAssertGreaterThan(index, 0)
            XCTAssertEqual(bytes[index - 1], 0x0D)
        }
        XCTAssertTrue(try XCTUnwrap(String(data: edited.data, encoding: .utf8)).contains("/Added (value)"))
    }

    func testNestedReplacementChangesOnlyTheTargetValue() throws {
        let originalText = """
        %!PS
        <<
          /Description << /ENU (English) /DEU (Deutsch) /JPN <FEFF65E5672C8A9E> >>
          /ColorImageDict << /QFactor 0.40 /Unknown [1 2 3] >>
        >> setdistillerparams
        """
        let original = Data(originalText.utf8)
        let document = try LosslessJoboptionsDocument(data: original)

        XCTAssertEqual(document.value(forPath: "/Description /DEU")?.textualValue, "Deutsch")
        XCTAssertEqual(document.value(forPath: "/ColorImageDict /QFactor")?.numberValue, 0.4)

        let edited = try document.replacingValue(
            forPath: "/ColorImageDict /QFactor",
            with: .number(0.75, original: "0.75")
        )
        let expected = originalText.replacingOccurrences(of: "/QFactor 0.40", with: "/QFactor 0.75")
        XCTAssertEqual(edited.data, Data(expected.utf8))
    }

    func testNestedInsertionPreservesExistingDictionaryBytes() throws {
        let original = Data("<< /Description << /ENU (Keep) % comment\r\n  /JPN <FEFF65E5672C>\r\n>> >> setdistillerparams\r\n".utf8)
        let edited = try LosslessJoboptionsDocument(data: original).replacingValue(
            forPath: "/Description /DEU",
            with: .string("Grüße"),
            stringInsertionStyle: .adobeUnicodeHex
        )
        let text = try XCTUnwrap(String(data: edited.data, encoding: .utf8))

        XCTAssertTrue(text.contains("/ENU (Keep) % comment\r\n"))
        XCTAssertTrue(text.contains("/JPN <FEFF65E5672C>\r\n"))
        XCTAssertTrue(text.contains("/DEU <FEFF0047007200FC00DF0065>"))
        XCTAssertEqual(edited.value(forPath: "/Description /DEU")?.textualValue, "Grüße")
    }

    func testHexadecimalUnicodeStringKeepsItsRepresentationWhenReplaced() throws {
        let original = Data("<< /Description <FEFF004F006C0064> >> setdistillerparams\n".utf8)
        let document = try LosslessJoboptionsDocument(data: original)
        XCTAssertEqual(document.value(forKey: "Description")?.textualValue, "Old")

        let edited = try document.replacingValue(forKey: "Description", with: .string("Neu"))
        XCTAssertTrue(try XCTUnwrap(String(data: edited.data, encoding: .utf8)).contains("<FEFF004E00650075>"))
        XCTAssertEqual(edited.value(forKey: "Description")?.textualValue, "Neu")
    }

    func testLatin1SourceRemainsLatin1AfterPointEdit() throws {
        let source = "<< /Description (Grüße) /Flag false >> setdistillerparams\r"
        let original = try XCTUnwrap(source.data(using: .isoLatin1))
        let edited = try LosslessJoboptionsDocument(data: original)
            .replacingValue(forKey: "Flag", with: .boolean(true))

        XCTAssertNil(String(data: edited.data, encoding: .utf8))
        XCTAssertEqual(String(data: edited.data, encoding: .isoLatin1), source.replacingOccurrences(of: "false", with: "true"))
    }

    func testUTF8BOMIsPreservedAfterPointEdit() throws {
        var original = Data([0xEF, 0xBB, 0xBF])
        original.append(Data("<< /Flag false >> setdistillerparams\n".utf8))
        let edited = try LosslessJoboptionsDocument(data: original)
            .replacingValue(forKey: "Flag", with: .boolean(true))

        XCTAssertTrue(edited.data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(try LosslessJoboptionsDocument(data: edited.data).value(forKey: "Flag")?.boolValue, true)
    }

    func testUTF16ByteOrderMarksArePreservedAfterPointEdit() throws {
        let source = "<< /Flag false >> setdistillerparams\r\n"
        for (bom, encoding) in [
            ([UInt8(0xFF), 0xFE], String.Encoding.utf16LittleEndian),
            ([UInt8(0xFE), 0xFF], String.Encoding.utf16BigEndian)
        ] {
            var original = Data(bom)
            original.append(try XCTUnwrap(source.data(using: encoding)))
            let edited = try LosslessJoboptionsDocument(data: original)
                .replacingValue(forKey: "Flag", with: .boolean(true))

            XCTAssertTrue(edited.data.starts(with: bom))
            XCTAssertEqual(try LosslessJoboptionsDocument(data: edited.data).value(forKey: "Flag")?.boolValue, true)
        }
    }

    func testCommentsEscapedStringsArraysAndUnknownFragmentsSurvive() throws {
        let original = Data("""
        %!PS
        <<
          % keep this comment
          /Title (nested \\(text\\) and \\\\ slash)
          /Values [1 true /Name { 2 3 add }]
          unknown-fragment
        >> setdistillerparams
        """.utf8)
        let document = try LosslessJoboptionsDocument(data: original)
        XCTAssertTrue(document.hasUnclassifiedFragments)

        let edited = try document.replacingValue(forKey: "NewFlag", with: .boolean(true))
        let text = try XCTUnwrap(String(data: edited.data, encoding: .utf8))
        XCTAssertTrue(text.contains("% keep this comment"))
        XCTAssertTrue(text.contains("unknown-fragment"))
        XCTAssertTrue(text.contains("/Values [1 true /Name { 2 3 add }]"))
    }

    func testMalformedAndNonJoboptionsInputIsRejected() {
        XCTAssertThrowsError(try LosslessJoboptionsDocument(data: Data("<< /A (unterminated".utf8)))
        XCTAssertThrowsError(try LosslessJoboptionsDocument(data: Data("plain text".utf8)))
        XCTAssertThrowsError(try LosslessJoboptionsDocument(data: Data()))
    }
}
