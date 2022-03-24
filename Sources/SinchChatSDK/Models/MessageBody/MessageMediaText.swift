import Foundation

struct MessageMediaText: MessageBody {
    var text: String
    var url: String
    var sendDate: Int64?
}
