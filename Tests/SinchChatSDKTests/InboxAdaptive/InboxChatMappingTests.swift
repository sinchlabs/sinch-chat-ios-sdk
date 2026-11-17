import XCTest
@testable import SinchChatSDK

final class InboxChatMappingTests: XCTestCase {
    func testSelectedChannelOverridesDefaultTopicAndPreservesOptions() {
        var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
        channel.channelID = "selected-channel"
        let options = GetChatViewControllerOptions(topicID: "default-channel", metadata: [],
                                                   shouldInitializeConversation: true, sendDocumentAsTextMessage: true)
        let chat = InboxChat(channel: channel, options: options)
        XCTAssertEqual(chat.chatOptions?.topicID, "selected-channel")
        XCTAssertEqual(chat.chatOptions?.shouldInitializeConversation, true)
        XCTAssertEqual(chat.chatOptions?.sendDocumentAsTextMessage, true)
        XCTAssertEqual(options.topicID, "default-channel")
    }

    func testNilOptionsStillOpenSelectedChannel() {
        var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
        channel.channelID = "second-channel"
        XCTAssertEqual(InboxChat(channel: channel, options: nil).chatOptions?.topicID, "second-channel")
    }

    func testChannelStatusMapsToPublicStatus() {
        var channel = Sinch_Chat_Sdk_V1alpha2_Channel()
        channel.status = .open
        XCTAssertEqual(InboxChat(channel: channel, options: nil).status, "open")
        channel.status = .closed
        XCTAssertEqual(InboxChat(channel: channel, options: nil).status, "closed")
        channel.status = .UNRECOGNIZED(42)
        XCTAssertEqual(InboxChat(channel: channel, options: nil).status, "")
    }
}
