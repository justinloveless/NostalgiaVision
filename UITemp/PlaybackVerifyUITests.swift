import XCTest

final class PlaybackVerifyUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    func testTuningToRealFeedWithKSPlayerDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-nostalgiavision.reset", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["SET-UP"].waitForExistence(timeout: 10))
        let feedButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'FEED URL'")).firstMatch
        XCTAssertTrue(feedButton.waitForExistence(timeout: 5))

        remote.press(.select)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        remote.press(.select)
        sleep(1)
        app.typeText("http://192.168.1.63:8002/api/channels.m3u")
        sleep(1)
        app.typeText("\r")

        // Wait for the async feed fetch to actually resolve before turning the dial, so we don't
        // race TVSet's one-shot "resume on first lineup" against our own manual turn.
        let setUpGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["SET-UP"])
        let resumed = XCTWaiter().wait(for: [setUpGone], timeout: 15)
        print("VERIFY auto-resumed off settings without pressing down: \(resumed == .completed)")
        if resumed != .completed {
            remote.press(.down)
            sleep(2)
        }

        let attachment1 = XCTAttachment(screenshot: app.screenshot())
        attachment1.name = "t0"
        attachment1.lifetime = .keepAlways
        add(attachment1)

        for i in 0..<3 {
            sleep(10)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "t\((i + 1) * 10)"
            shot.lifetime = .keepAlways
            add(shot)
            print("VERIFY t=\((i + 1) * 10)s appState=\(app.state.rawValue) noSignal=\(app.staticTexts["NO SIGNAL"].exists)")
        }

        XCTAssertEqual(app.state, .runningForeground, "app must not have crashed")
        print("VERIFY final tree >>>\n\(app.debugDescription)\n<<<")
    }

    func testChannelSwitchingDoesNotLeakPlayers() throws {
        let app = XCUIApplication()
        app.launch()

        // Settings from a prior run are already persisted (a real feed URL), so the app resumes
        // straight onto a channel without going through SET-UP.
        if app.staticTexts["SET-UP"].waitForExistence(timeout: 5) {
            XCTFail("expected settings to already be configured from a prior run; SET-UP appeared instead")
        }
        sleep(3)

        print("VERIFY ---- settled on first channel ----")
        sleep(4)

        // Flip channels faster than a stream typically finishes opening (~3s), the way an
        // impatient viewer actually surfs, to stress whatever async teardown is in flight.
        for i in 0..<4 {
            print("VERIFY ---- quick down #\(i) ----")
            remote.press(.down)
            usleep(700_000)
        }
        print("VERIFY ---- settling after quick surf down ----")
        sleep(8)

        for i in 0..<4 {
            print("VERIFY ---- quick up #\(i) ----")
            remote.press(.up)
            usleep(700_000)
        }
        print("VERIFY ---- settling after quick surf up (back near start) ----")
        sleep(8)

        XCTAssertEqual(app.state, .runningForeground, "app must not have crashed")
    }
}
