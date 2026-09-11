import XCTest

final class PostScriptEncryptionTests: XCTestCase {
    private var directoryURL: URL!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testPasswordValidation() throws {
        XCTAssertThrowsError(try PostScriptEncryptor.validatePassword("")) {
            XCTAssertEqual($0 as? PostScriptEncryptionError, .passwordEmpty)
        }
        XCTAssertThrowsError(try PostScriptEncryptor.validatePassword("secret_password")) {
            XCTAssertEqual($0 as? PostScriptEncryptionError, .reservedPassword)
        }
        XCTAssertThrowsError(try PostScriptEncryptor.validatePassword("not(allowed")) {
            XCTAssertEqual($0 as? PostScriptEncryptionError, .unsupportedPasswordCharacter)
        }
        XCTAssertThrowsError(try PostScriptEncryptor.validatePassword("ümlaut")) {
            XCTAssertEqual($0 as? PostScriptEncryptionError, .unsupportedPasswordCharacter)
        }
        XCTAssertNoThrow(try PostScriptEncryptor.validatePassword("Correct horse 42!"))
    }

    func testOutputFilenameUsesEncryptedPostScriptSuffix() {
        XCTAssertEqual(
            PostScriptEncryptor.outputFilename(for: "drawing.ps"),
            "drawing.encrypted.ps"
        )
        XCTAssertEqual(
            PostScriptEncryptor.outputFilename(for: "drawing.EPS"),
            "drawing.encrypted.ps"
        )
    }

    func testRejectsPlainTextInput() throws {
        let inputURL = directoryURL.appendingPathComponent("notes.txt")
        try Data("plain text".utf8).write(to: inputURL)
        XCTAssertThrowsError(try PostScriptEncryptor.validateInput(at: inputURL)) {
            XCTAssertEqual($0 as? PostScriptEncryptionError, .inputIsNotPostScript)
        }
    }

    func testEncryptsPostScriptWithoutIncludingTypesetterOrPlaintext() throws {
        let inputURL = directoryURL.appendingPathComponent("drawing.ps")
        let outputURL = directoryURL.appendingPathComponent("drawing.encrypted.ps")
        let plaintext = """
        %!PS-Adobe-3.0
        /Courier findfont 16 scalefont setfont
        72 720 moveto
        (Confidential payload 7249) show
        showpage
        """
        try Data(plaintext.utf8).write(to: inputURL)

        try PostScriptEncryptor.encrypt(
            inputURL: inputURL,
            outputURL: outputURL,
            password: "Correct horse 42!"
        )

        let encrypted = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(encrypted.hasPrefix("%!PS-Adobe-3.0\n"))
        XCTAssertTrue(encrypted.contains("%%PSEncryptMode: PostScript"))
        XCTAssertTrue(encrypted.contains("/password (secret_password) def"))
        XCTAssertEqual(encrypted.components(separatedBy: "secret_password").count - 1, 1)
        XCTAssertTrue(
            encrypted.contains(
                "/wrongPasswordMessage <57726f6e672050617373776f7264> def"
            )
        )
        XCTAssertTrue(encrypted.contains("/ReusableStreamDecode filter cvx exec"))
        XCTAssertFalse(encrypted.contains("Confidential payload 7249"))
        XCTAssertFalse(encrypted.contains("Text renderer"))
        XCTAssertFalse(encrypted.contains("CourierLatin1"))
    }
}
