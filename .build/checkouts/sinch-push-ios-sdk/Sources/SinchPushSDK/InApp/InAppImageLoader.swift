import UIKit

/// A `UIImage` box for hopping between executors.
///
/// `UIImage` is immutable once created but is not annotated `Sendable`, so this
/// wrapper carries the guarantee explicitly instead of forcing the decode onto
/// the main actor.
private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}

/// The in-app alert image loader: `URLSession` plus `NSCache`, no Kingfisher.
///
/// One load per image view at a time: starting a new load cancels the previous
/// one, so a recycled view never shows a stale image.
@MainActor
public final class InAppImageLoader {

    public static let shared = InAppImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 24
    }

    /// Loads `url` into `imageView`, cancelling whatever that view was loading.
    ///
    /// `completion` runs on the main actor with the decoded image, or `nil` when
    /// the load failed or was cancelled. A cached image is delivered
    /// synchronously.
    public func load(
        _ url: URL?,
        into imageView: UIImageView,
        placeholder: UIImage? = nil,
        completion: (@MainActor (UIImage?) -> Void)? = nil
    ) {
        cancel(for: imageView)
        imageView.image = placeholder

        guard let url else {
            completion?(nil)
            return
        }

        if let cached = cache.object(forKey: url as NSURL) {
            imageView.image = cached
            completion?(cached)
            return
        }

        let identifier = ObjectIdentifier(imageView)
        let session = self.session

        tasks[identifier] = Task { @MainActor [weak self, weak imageView] in
            let fetched = await InAppImageLoader.fetch(url, session: session)
            guard !Task.isCancelled else { return }
            self?.tasks[identifier] = nil

            guard let image = fetched?.image else {
                completion?(nil)
                return
            }

            self?.cache.setObject(image, forKey: url as NSURL)

            guard let imageView else { return }
            imageView.image = image
            completion?(image)
        }
    }

    /// Drops the pending load for `imageView` and clears the cached task entry.
    public func cancel(for imageView: UIImageView) {
        tasks.removeValue(forKey: ObjectIdentifier(imageView))?.cancel()
    }

    /// Clears every decoded image. Mostly useful for tests and memory warnings.
    public func clearCache() {
        cache.removeAllObjects()
    }

    nonisolated private static func fetch(_ url: URL, session: URLSession) async -> SendableImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        return SendableImage(image: image)
    }
}
