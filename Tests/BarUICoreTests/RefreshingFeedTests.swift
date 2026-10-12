import Foundation
import Testing
@testable import BarUICore

/// A source that never touches the network: it serves what the test gives it
/// and counts how often it was asked.
private final class FakeSource: DocumentSource, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>
    private var asked = 0

    init(_ result: Result<Data, Error>) { self.result = result }

    var requests: Int { lock.withLock { asked } }

    func data(from url: URL) async throws -> Data {
        try lock.withLock {
            asked += 1
            return try result.get()
        }
    }
}

private struct Offline: Error {}

@Suite("Refreshing feed")
struct RefreshingFeedTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let url = URL(string: "https://example.invalid/feed")!

    private final class Directory {
        let url: URL
        var cacheFile: URL { url.appendingPathComponent("feed.json") }

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("RefreshingFeedTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func writeCache(_ text: String, age: TimeInterval) throws {
            try Data(text.utf8).write(to: cacheFile)
            try FileManager.default.setAttributes([.modificationDate: RefreshingFeedTests.now.addingTimeInterval(-age)], ofItemAtPath: cacheFile.path)
        }
    }

    private static func text(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("ok:") else {
            throw Offline()
        }
        return text
    }

    private static func feed(_ directory: Directory?, source: FakeSource, bundled: String = "ok:bundled") -> RefreshingFeed<String> {
        RefreshingFeed(
            url: url, cacheFile: directory?.cacheFile, bundled: Data(bundled.utf8), maxAge: 86_400, source: source,
            parse: { try text($0) }
        )
    }

    @Test("Nothing cached: fetches, uses the result, and keeps it for next time")
    func firstFetch() async throws {
        let directory = try Directory()
        let source = FakeSource(.success(Data("ok:remote".utf8)))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:remote")
        #expect(snapshot.origin == .fetched)
        #expect(snapshot.updatedAt == Self.now)
        #expect(try String(contentsOf: directory.cacheFile, encoding: .utf8) == "ok:remote")
    }

    @Test("A cache younger than a day is used without asking the network")
    func freshCache() async throws {
        let directory = try Directory()
        try directory.writeCache("ok:cached", age: 3_600)
        let source = FakeSource(.success(Data("ok:remote".utf8)))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:cached")
        #expect(snapshot.origin == .cached)
        #expect(source.requests == 0)
    }

    @Test("A cache older than a day is refreshed")
    func staleCacheRefreshes() async throws {
        let directory = try Directory()
        try directory.writeCache("ok:cached", age: 2 * 86_400)
        let source = FakeSource(.success(Data("ok:remote".utf8)))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:remote")
        #expect(source.requests == 1)
    }

    @Test("Offline with an old cache, the old cache is used and the failure is reported")
    func offlineUsesCache() async throws {
        let directory = try Directory()
        try directory.writeCache("ok:cached", age: 2 * 86_400)
        let source = FakeSource(.failure(Offline()))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:cached")
        #expect(snapshot.origin == .cached)
        #expect(snapshot.refreshFailure != nil)
    }

    @Test("Offline with no cache, the bundled copy is used")
    func offlineUsesBundled() async throws {
        let directory = try Directory()
        let source = FakeSource(.failure(Offline()))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:bundled")
        #expect(snapshot.origin == .bundled)
        #expect(snapshot.refreshFailure != nil)
    }

    @Test("A fetched document that doesn't parse is not cached and doesn't replace a good cache")
    func badDocumentIsIgnored() async throws {
        let directory = try Directory()
        try directory.writeCache("ok:cached", age: 2 * 86_400)
        let source = FakeSource(.success(Data("<html>captive portal</html>".utf8)))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:cached")
        #expect(snapshot.refreshFailure != nil)
        #expect(try String(contentsOf: directory.cacheFile, encoding: .utf8) == "ok:cached")
    }

    @Test("A cache that no longer parses is skipped")
    func corruptCache() async throws {
        let directory = try Directory()
        try directory.writeCache("garbage", age: 60)
        let source = FakeSource(.failure(Offline()))

        let snapshot = try await Self.feed(directory, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:bundled")
    }

    @Test("Without anywhere to cache, it still fetches and falls back to the bundled copy")
    func noCacheLocation() async throws {
        let source = FakeSource(.success(Data("ok:remote".utf8)))

        let snapshot = try await Self.feed(nil, source: source).load(now: Self.now)

        #expect(snapshot.value == "ok:remote")
    }

    @Test("A cache that can't be written is reported but the fetched value is still used")
    func unwritableCache() async throws {
        let directory = try Directory()
        let blocked = RefreshingFeed(
            url: Self.url, cacheFile: directory.url.appendingPathComponent("missing/feed.json"), bundled: Data("ok:bundled".utf8),
            maxAge: 86_400, source: FakeSource(.success(Data("ok:remote".utf8))), parse: { try Self.text($0) }
        )

        let snapshot = try await blocked.load(now: Self.now)

        #expect(snapshot.value == "ok:remote")
        #expect(snapshot.refreshFailure != nil)
    }

    @Test("When even the bundled copy is unusable, loading fails instead of inventing a value")
    func nothingUsable() async throws {
        let source = FakeSource(.failure(Offline()))

        await #expect(throws: (any Error).self) {
            try await Self.feed(nil, source: source, bundled: "broken").load(now: Self.now)
        }
    }
}
