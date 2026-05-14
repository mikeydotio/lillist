import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// TTY detection for choosing between ANSI-colored and plain output.
public enum TTY {
    public static var stdoutIsTTY: Bool {
        isatty(fileno(stdout)) == 1
    }

    public static var shouldUseColor: Bool {
        // Respect NO_COLOR (https://no-color.org) and stdout TTY status.
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return stdoutIsTTY
    }
}
