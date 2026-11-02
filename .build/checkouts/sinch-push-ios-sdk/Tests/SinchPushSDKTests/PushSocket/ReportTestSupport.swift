//  ReportTestSupport.swift — the harness the four Report*Tests suites share.

@testable import SinchPushSDK

/// A harness that reports but never presents: a notification in the way would
/// add a second DISPLAYED to every count.
func makeReportHarness(
    draw: Double = 0.5,
    store: FakeSocketStateStore = FakeSocketStateStore()
) -> SocketHarness {
    let presenter = FakeNotificationPresenter()
    presenter.acceptsPost = false
    return makeHarness(
        configuration: testConfiguration(displayNotifications: .always),
        random: draw,
        store: store,
        presenter: presenter)
}
