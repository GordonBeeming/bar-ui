import Foundation

extension Archive {
    /// The cumulative token points from `since` on (every one when nil),
    /// oldest first. Turning them into usage per period is `TokenUsage`'s
    /// job, and each point's usage is how far it moved from the point before
    /// it, so every counter seen in the range also brings its newest point
    /// from before the range as a baseline.
    public func tokenSamples(since: Date? = nil) throws -> [TokenSample] {
        guard let since else {
            return try readTokenSamples(try prepare("""
                SELECT app, model, token_type, start_time_unix_nano, time_unix_nano, count
                FROM token_samples
                ORDER BY time_unix_nano, app, model, token_type
                """))
        }
        let floor = since.unixNano
        let inRange = try prepare("""
            SELECT app, model, token_type, start_time_unix_nano, time_unix_nano, count
            FROM token_samples
            WHERE time_unix_nano >= ?1
            ORDER BY time_unix_nano, app, model, token_type
            """)
        try inRange.bind(.integer(floor))
        let samples = try readTokenSamples(inRange)

        let baseline = try prepare("""
            SELECT app, model, token_type, start_time_unix_nano, time_unix_nano, count
            FROM token_samples
            WHERE app = ?1 AND model = ?2 AND token_type = ?3 AND time_unix_nano < ?4
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        var baselines: [TokenSample] = []
        var seen: Set<[String]> = []
        for sample in samples where seen.insert([sample.app.rawValue, sample.model, sample.tokenType.rawValue]).inserted {
            try baseline.bind(.text(sample.app.rawValue), .text(sample.model), .text(sample.tokenType.rawValue), .integer(floor))
            baselines += try readTokenSamples(baseline)
        }
        return (baselines + samples).sorted {
            ($0.timeUnixNano, $0.app.rawValue, $0.model, $0.tokenType.rawValue) < ($1.timeUnixNano, $1.app.rawValue, $1.model, $1.tokenType.rawValue)
        }
    }

    private func readTokenSamples(_ statement: Statement) throws -> [TokenSample] {
        var samples: [TokenSample] = []
        while try statement.step() {
            // Rows from a Bar App or Token Type this build doesn't know stay
            // in the Archive untouched but can't be shown.
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let model = statement.text(at: 1),
                  let typeName = statement.text(at: 2), let tokenType = TokenType(rawValue: typeName) else {
                continue
            }
            samples.append(TokenSample(
                app: app,
                model: model,
                tokenType: tokenType,
                startTimeUnixNano: statement.int64(at: 3),
                timeUnixNano: statement.int64(at: 4),
                count: statement.int64(at: 5)
            ))
        }
        return samples
    }
}
