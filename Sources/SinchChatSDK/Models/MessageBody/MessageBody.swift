import UIKit

protocol MessageBody: Codable {
    var sendDate: Int64? { get }
}
