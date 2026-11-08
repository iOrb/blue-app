import XCTest

final class PerformanceTests: XCTestCase {
    @MainActor private func preparedApp(stress: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        let arguments = ["--uitest"] + (stress ? ["--stress-data"] : [])
        app.launchArguments = arguments + ["--uitest-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["folder-template.movies"].waitForExistence(timeout: 60))
        app.terminate()
        app.launchArguments = arguments
        return app
    }
    @MainActor private func launchMetrics(stress: Bool) {
        let app = preparedApp(stress: stress)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            XCTAssertTrue(app.buttons["folder-template.movies"].waitForExistence(timeout: 30))
            app.terminate()
        }
    }
    @MainActor private func scrollMetrics(stress: Bool) {
        let app = preparedApp(stress: stress)
        app.launch()
        app.buttons["folder-template.movies"].tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTMemoryMetric(application: app), XCTHitchMetric(application: app),
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
            ],
            options: options
        ) {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = stress ? "stress-collection" : "normal-collection"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }
    @MainActor func testNormalLaunchMetrics() { launchMetrics(stress: false) }
    @MainActor func testStressLaunchMetrics() { launchMetrics(stress: true) }
    @MainActor func testNormalScrollMetrics() { scrollMetrics(stress: false) }
    @MainActor func testStressScrollMetrics() { scrollMetrics(stress: true) }
}
