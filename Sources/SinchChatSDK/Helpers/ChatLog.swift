import Foundation

/// Chat's debug logging for the few UI error paths that report one.
///
/// The shared `Logger` lives in `SinchPushSDK` and is internal there; chat keeps its own minimal output instead of a
/// second logging type.
func chatLog(_ message: @autoclosure () -> Any) {
    #if DEBUG
    print(message())
    #endif
}
