import Foundation
import os

/// Where a feed's document comes from. A protocol so nothing under test ever
/// reaches the network.
public protocol DocumentSource: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionDocumentSource: DocumentSource {
    public struct BadResponse: Error, LocalizedError {
        public let statusCode: Int
        public var errorDescription: String? { "The server answered \(statusCode)." }
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BadResponse(statusCode: http.statusCode)
        }
        return data
    }
}

public struct FeedSnapshot<Value: Sendable>: Sendable {
    public enum Origin: Sendable, Equatable {
        /// Downloaded just now.
        case fetched
        /// The copy kept from an earlier download.
        case cached
        /// The copy shipped inside the app.
        case bundled
    }

    public let value: Value
    public let origin: Origin
    /// When the document was last downloaded. Nil for the bundled copy.
    public let updatedAt: Date?
    /// Why the newest copy couldn't be had, when it couldn't. The value is
    /// still usable; this is for the UI to say it may be out of date.
    public let refreshFailure: String?
}

/// A document that is downloaded at most once a `maxAge`, kept on disk, and
/// backed by a copy shipped in the app, so the figures built on it work
/// offline. A download only replaces the cache once it has parsed, so a
/// captive portal's HTML page can't poison it.
public struct RefreshingFeed<Value: Sendable>: Sendable {
    private static var logger: Logger {
        Logger(subsystem: "com.gordonbeeming.BarUI", category: "RefreshingFeed")
    }

    private let url: URL
    private let cacheFile: URL?
    private let bundled: Data
    private let maxAge: TimeInterval
    private let source: any DocumentSource
    private let parse: @Sendable (Data) throws -> Value

    public init(
        url: URL,
        cacheFile: URL?,
        bundled: Data,
        maxAge: TimeInterval = 24 * 3_600,
        source: any DocumentSource,
        parse: @escaping @Sendable (Data) throws -> Value
    ) {
        self.url = url
        self.cacheFile = cacheFile
        self.bundled = bundled
        self.maxAge = maxAge
        self.source = source
        self.parse = parse
    }

    /// Throws only when nothing usable exists, not even the bundled copy.
    public func load(now: Date) async throws -> FeedSnapshot<Value> {
        let cache = readCache()
        let cached = cache.copy
        if let cached, now.timeIntervalSince(cached.updatedAt) < maxAge {
            return FeedSnapshot(value: cached.value, origin: .cached, updatedAt: cached.updatedAt, refreshFailure: nil)
        }

        var failure: String
        do {
            let data = try await source.data(from: url)
            let value = try parse(data)
            return FeedSnapshot(value: value, origin: .fetched, updatedAt: now, refreshFailure: writeCache(data))
        } catch {
            failure = error.localizedDescription
        }

        if let cached {
            return FeedSnapshot(value: cached.value, origin: .cached, updatedAt: cached.updatedAt, refreshFailure: failure)
        }
        if let problem = cache.problem {
            failure += "\nThe offline copy couldn't be read either: \(problem)"
        }
        return FeedSnapshot(value: try parse(bundled), origin: .bundled, updatedAt: nil, refreshFailure: failure)
    }

    private struct CacheRead {
        var copy: (value: Value, updatedAt: Date)?
        /// Why a cache file that exists couldn't be used. Nil when there is
        /// simply no cache yet, which is normal before the first download.
        var problem: String?
    }

    private struct MissingModificationDate: Error, LocalizedError {
        var errorDescription: String? { "It has no modification date." }
    }

    private func readCache() -> CacheRead {
        guard let cacheFile else {
            return CacheRead()
        }
        do {
            let data = try Data(contentsOf: cacheFile)
            let value = try parse(data)
            guard let updatedAt = try FileManager.default.attributesOfItem(atPath: cacheFile.path)[.modificationDate] as? Date else {
                throw MissingModificationDate()
            }
            return CacheRead(copy: (value, updatedAt))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return CacheRead()
        } catch {
            Self.logger.error("Can't use the cached copy at \(cacheFile.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return CacheRead(problem: error.localizedDescription)
        }
    }

    /// Returns why the cache couldn't be kept, or nil.
    private func writeCache(_ data: Data) -> String? {
        guard let cacheFile else {
            return nil
        }
        do {
            try data.write(to: cacheFile, options: .atomic)
            return nil
        } catch {
            return "Couldn't keep a copy for offline use: \(error.localizedDescription)"
        }
    }
}
