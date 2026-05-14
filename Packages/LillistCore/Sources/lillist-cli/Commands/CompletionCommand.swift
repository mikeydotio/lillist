import ArgumentParser
import Foundation

public struct CompletionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Generate shell completion scripts.",
        subcommands: [Bash.self, Zsh.self, Fish.self]
    )

    public init() {}

    public struct Bash: ParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "bash")
        public init() {}
        public func run() throws {
            print("Run: lillist --generate-completion-script bash")
        }
    }
    public struct Zsh: ParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "zsh")
        public init() {}
        public func run() throws { print("Run: lillist --generate-completion-script zsh") }
    }
    public struct Fish: ParsableCommand {
        public static let configuration = CommandConfiguration(commandName: "fish")
        public init() {}
        public func run() throws { print("Run: lillist --generate-completion-script fish") }
    }
}
