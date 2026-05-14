import Foundation

extension CLIBridge {
    /// User-level CLI configuration, loaded from `~/.config/lillist/config.toml`.
    /// Hand-parsed; only three top-level keys are supported. Anything else is
    /// silently ignored (forward-compatibility).
    public struct Config: Sendable, Equatable {
        public var outputFormat: OutputFormat
        public var sort: SortField
        public var timeZone: TimeZone?

        public init(outputFormat: OutputFormat = .pretty, sort: SortField = .manualPosition, timeZone: TimeZone? = nil) {
            self.outputFormat = outputFormat
            self.sort = sort
            self.timeZone = timeZone
        }

        /// Reads the config at `url`. A missing file yields defaults.
        public static func read(from url: URL) throws -> Config {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return Config()
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            var cfg = Config()
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                let value = stripQuotes(rawValue)
                switch key {
                case "output_format":
                    guard let fmt = OutputFormat(rawValue: value) else {
                        throw LillistError.validationFailed([
                            .init(field: "output_format", message: "unknown value '\(value)'; expected pretty|json|ndjson|tsv")
                        ])
                    }
                    cfg.outputFormat = fmt
                case "sort":
                    guard let s = SortField(rawValue: value) else {
                        throw LillistError.validationFailed([
                            .init(field: "sort", message: "unknown sort field '\(value)'")
                        ])
                    }
                    cfg.sort = s
                case "time_zone":
                    cfg.timeZone = TimeZone(identifier: value)
                default:
                    continue
                }
            }
            return cfg
        }

        public static func defaultLocation() -> URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("lillist", isDirectory: true)
                .appendingPathComponent("config.toml")
        }

        static func stripQuotes(_ s: String) -> String {
            var t = s
            if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
                t = String(t.dropFirst().dropLast())
            } else if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 {
                t = String(t.dropFirst().dropLast())
            }
            return t
        }
    }
}
