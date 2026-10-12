import Foundation
import os

public struct ImportSummary: Sendable, Equatable {
    public var filesRead = 0
    public var samplesRead = 0
    public var droppedRecords = 0
    /// Files that couldn't be read this pass, with the reason. The next pass
    /// tries them again from where the Archive last got to.
    public var failures: [String: String] = [:]

    public init() {}
}

/// Copies new Limit samples from a Bar App's metrics files into the Archive.
/// It only reads the Telemetry Folder: no locks, nothing written there.
public struct TelemetryImporter: Sendable {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "TelemetryImporter")

    private let archive: Archive

    public init(archive: Archive) {
        self.archive = archive
    }

    public func importMetrics(of app: BarApp, from folder: URL) async throws -> ImportSummary {
        var summary = ImportSummary()
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return summary
        }

        // Oldest first, so a Limit's description ends on its newest name even
        // on a first import of many days.
        for name in names.filter(app.isMetricsFileName).sorted() {
            let file = folder.appendingPathComponent(name, isDirectory: false)
            do {
                if let read = try await importFile(file, named: name, of: app) {
                    summary.filesRead += 1
                    summary.samplesRead += read.samples
                    summary.droppedRecords += read.dropped
                }
            } catch let error as ArchiveError {
                // The Archive failing is not about this file; every other file
                // would fail the same way, so stop and let the caller show it.
                throw error
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // Retention deletes whole files at any moment; one that went
                // between listing and reading has nothing left to import.
                continue
            } catch {
                Self.logger.error("Can't read \(name, privacy: .public) for \(app.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                summary.failures[name] = error.localizedDescription
            }
        }
        return summary
    }

    private func importFile(_ file: URL, named name: String, of app: BarApp) async throws -> (samples: Int, dropped: Int)? {
        let previous = try await archive.progress(of: app, fileName: name)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        var offset = previous?.byteOffset ?? 0
        var droppedSoFar = previous?.droppedRecords ?? 0
        if size < offset {
            // Writers only append, so a shorter file is a different file under
            // the same name. Its old position and count no longer apply.
            offset = 0
            droppedSoFar = 0
        }
        guard size > offset || previous == nil else {
            return nil
        }

        let handle = try FileHandle(forReadingFrom: file)
        defer {
            do {
                try handle.close()
            } catch {
                Self.logger.error("Can't close \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.readToEnd() ?? Data()

        let result = MetricsParser.parse(data, from: app)
        guard result.consumedByteCount > 0 || previous == nil || offset != previous?.byteOffset else {
            return nil
        }
        try await archive.record(result.samples, tokenSamples: result.tokenSamples, progress: ImportProgress(
            app: app,
            fileName: name,
            byteOffset: offset + Int64(result.consumedByteCount),
            droppedRecords: droppedSoFar + result.droppedRecords
        ))
        return (result.samples.count, result.droppedRecords)
    }
}

extension BarApp {
    /// Logs share the folder but carry no Limit samples, so only the metrics
    /// pattern is imported here.
    func isMetricsFileName(_ name: String) -> Bool {
        isTelemetryFileName(name) && name.hasPrefix("\(serviceName)-metrics-")
    }
}
