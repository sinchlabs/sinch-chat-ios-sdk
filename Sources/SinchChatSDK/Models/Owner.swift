import Foundation

enum Owner: Codable {
    case outgoing
    case incoming(Agent?)
    case system
}
