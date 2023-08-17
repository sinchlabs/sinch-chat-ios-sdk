import Foundation

public enum Owner: Codable {
    case outgoing
    case incoming(Agent?)
    case system
}
