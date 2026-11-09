import Foundation

/// The conforming fixtures, rewritten the way a Bar App writes a second
/// Account's files: the resource carries `account.id` and `account.name`.
enum AccountFixture {
    /// `id` nil leaves `account.id` out, which is how the default Account's
    /// files read.
    static func data(from fixtureName: String, accountID id: String?, name: String? = nil) throws -> Data {
        let source = try Fixtures.data(named: fixtureName)
        var output = Data()
        for line in source.split(separator: UInt8(ascii: "\n")) {
            guard var request = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw FixtureError.notAnObject
            }
            for key in ["resourceMetrics", "resourceLogs"] {
                guard var resources = request[key] as? [[String: Any]] else {
                    continue
                }
                for index in resources.indices {
                    guard var resource = resources[index]["resource"] as? [String: Any],
                          var attributes = resource["attributes"] as? [[String: Any]] else {
                        throw FixtureError.noResource
                    }
                    if let id {
                        attributes.append(["key": "account.id", "value": ["stringValue": id]])
                    }
                    if let name {
                        attributes.append(["key": "account.name", "value": ["stringValue": name]])
                    }
                    resource["attributes"] = attributes
                    resources[index]["resource"] = resource
                }
                request[key] = resources
            }
            output.append(try JSONSerialization.data(withJSONObject: request))
            output.append(UInt8(ascii: "\n"))
        }
        return output
    }

    @discardableResult
    static func write(from fixtureName: String, accountID id: String?, name: String? = nil, as fileName: String, in folder: URL) throws -> URL {
        let target = folder.appendingPathComponent(fileName)
        try data(from: fixtureName, accountID: id, name: name).write(to: target)
        return target
    }

    enum FixtureError: Error {
        case notAnObject
        case noResource
    }
}
