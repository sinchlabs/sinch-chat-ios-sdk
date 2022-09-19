import UIKit

protocol MessageBody: Codable {
    var sendDate: Int64? { get }

}

protocol MessageWithURL: Codable {
    var url: String { get }
}

protocol MessageWithText: Codable {
   func getText() -> String
}
