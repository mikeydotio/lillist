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

        /// The calendar date commands should use, honoring the configured
        /// `time_zone`. Falls back to `Calendar.current` (which carries the
        /// host's zone) when no `time_zone` key is set. Centralizes what
        /// every CLI date command previously hardcoded as `Calendar.current`,
        /// so the parsed `time_zone` actually affects relative-date math.
        public func resolvedCalendar() -> Calendar {
            guard let timeZone else { return Calendar.current }
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            return calendar
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
                    guard let zone = TimeZone(identifier: value) else {
                        throw LillistError.validationFailed([
                            .init(field: "time_zone", message: "unknown time zone identifier '\(value)'")
                        ])
                    }
                    cfg.timeZone = zone
                default:
                    continue
                }
            }
            return cfg
        }

        public static func defaultLocation() -> URL {
            // `FileManager.homeDirectoryForCurrentUser` is unavailable on iOS;
            // `NSHomeDirectory()` is portable. On iOS this resolves to the
            // app sandbox container — meaningless for CLI use but harmless
            // because the iOS app never invokes `Config.read(from:)` against
            // this path. The CLI target is the only real caller.
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
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
