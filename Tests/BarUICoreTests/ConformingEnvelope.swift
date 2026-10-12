import Foundation

/// The resource and scope a Bar App writes around every record under
/// Telemetry Spec v1 §3, so a test line breaks only the rule it means to.
enum ConformingEnvelope {
    static func scopeName(of service: String) -> String {
        service == "codexbar" ? "com.gordonbeeming.CodexBar.telemetry" : "com.gordonbeeming.ClaudeBar.telemetry"
    }

    /// Resource attributes, with `bar.spec.version` left out when `specVersion` is nil.
    static func resourceAttributes(service: String, specVersion: String? = "1") -> [[String: Any]] {
        var attributes: [[String: Any]] = [
            ["key": "service.name", "value": ["stringValue": service]],
            ["key": "service.version", "value": ["stringValue": "1.0"]],
            ["key": "host.name", "value": ["stringValue": "test-mac.local"]],
            ["key": "os.type", "value": ["stringValue": "darwin"]]
        ]
        if let specVersion {
            attributes.append(["key": "bar.spec.version", "value": ["stringValue": specVersion]])
        }
        return attributes
    }

    static func scope(service: String) -> [String: Any] {
        ["name": scopeName(of: service), "version": "1.0"]
    }

    /// The `resource` object as raw JSON.
    static func resourceJSON(service: String) -> String {
        #"{"attributes":[{"key":"service.name","value":{"stringValue":"\#(service)"}},{"key":"service.version","value":{"stringValue":"1.0"}},{"key":"host.name","value":{"stringValue":"test-mac.local"}},{"key":"os.type","value":{"stringValue":"darwin"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]}"#
    }

    /// The `scope` object as raw JSON.
    static func scopeJSON(service: String) -> String {
        #"{"name":"\#(scopeName(of: service))","version":"1.0"}"#
    }
}
