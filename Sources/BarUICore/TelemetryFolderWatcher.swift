import CoreServices
import Foundation
import os

/// Reports when anything changes inside a set of Telemetry Folders, so new
/// Telemetry can be imported within seconds instead of at the next poll.
///
/// FSEvents is used because it watches from outside: it opens no file in the
/// folder, takes no locks and writes nothing there, which the Telemetry Spec
/// requires of readers. It only says that something changed, never what, so
/// the importer still works out what's new from its own read positions.
public enum TelemetryFolderWatcher {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "TelemetryFolderWatcher")

    /// Yields once per burst of changes. A burst that arrives while the
    /// consumer is still busy is folded into one pending element, so a slow
    /// import never builds up a backlog. The watch stops when the stream's
    /// consumer goes away. Folders that don't exist yet are watched for when
    /// they appear.
    public static func changes(in folders: [URL], latency: Duration = .milliseconds(500)) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard !folders.isEmpty else {
                continuation.finish()
                return
            }
            guard let watch = Watch(folders: folders, latency: latency, continuation: continuation) else {
                logger.error("Can't watch the Telemetry Folders; new Telemetry waits for the next poll")
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                watch.stop()
            }
        }
    }
}

/// Owns one FSEvents stream. Every call into FSEvents for it happens on its
/// private serial queue, which is what makes sharing it across the stream's
/// termination handler safe.
private final class Watch: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gordonbeeming.BarUI.TelemetryFolderWatcher")
    private let stream: FSEventStreamRef

    init?(folders: [URL], latency: Duration, continuation: AsyncStream<Void>.Continuation) {
        let box = Unmanaged.passRetained(ContinuationBox(continuation))
        var context = FSEventStreamContext(
            version: 0,
            info: box.toOpaque(),
            retain: nil,
            release: { info in
                guard let info else {
                    return
                }
                Unmanaged<ContinuationBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            Unmanaged<ContinuationBox>.fromOpaque(info).takeUnretainedValue().continuation.yield()
        }
        let seconds = Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            folders.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            seconds,
            flags
        ) else {
            // The stream never took ownership, so the retain above is ours to drop.
            box.release()
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
    }

    func stop() {
        queue.async {
            FSEventStreamStop(self.stream)
            FSEventStreamInvalidate(self.stream)
            FSEventStreamRelease(self.stream)
        }
    }
}

private final class ContinuationBox {
    let continuation: AsyncStream<Void>.Continuation

    init(_ continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }
}
