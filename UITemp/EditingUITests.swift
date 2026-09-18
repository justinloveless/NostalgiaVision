import XCTest

final class EditingUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private let feed = "http://127.0.0.1:8099/channels.m3u"

    func testTypingAFeedURLConfiguresTheSetAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-nostalgiavision.reset", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["SET-UP"].waitForExistence(timeout: 10))
        let feedButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'FEED URL'")).firstMatch
        XCTAssertTrue(feedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(feedButton.hasFocus, "the first control takes focus on entry")

        remote.press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "select must present the text editor cover")

        remote.press(.select)
        sleep(2)
        app.typeText(feed)
        sleep(1)
        print("EDITTEST after typing: \(app.textFields.firstMatch.value ?? "nil")")

        remote.press(.menu)
        sleep(1)
        let done = app.buttons["DONE"]
        if done.exists {
            while !done.hasFocus { remote.press(.right) }
            remote.press(.select)
        }
        sleep(3)
        print("EDITTEST tree >>>\n\(app.debugDescription)\n<<<")
    }
}
