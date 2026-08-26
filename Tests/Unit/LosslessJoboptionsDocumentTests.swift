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
