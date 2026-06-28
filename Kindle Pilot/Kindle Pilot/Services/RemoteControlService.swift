import Foundation

enum KindleScreenOrientation: String, CaseIterable, Hashable {
    case portrait
    case landscape

    var title: String {
        switch self {
        case .portrait:
            return L("竖屏")
        case .landscape:
            return L("横屏")
        }
    }
}

struct FlipCommandDefinition: Identifiable, Hashable {
    let direction: PageTurnDirection
    let orientation: KindleScreenOrientation

    var id: String {
        "\(direction.remoteEventName)_\(orientation.rawValue)"
    }

    var title: String {
        "\(orientation.title)\(direction.logTitle)"
    }

    var remotePath: String {
        "/mnt/us/FlipCmd/\(id).event"
    }

    static let all: [FlipCommandDefinition] = [
        FlipCommandDefinition(direction: .next, orientation: .portrait),
        FlipCommandDefinition(direction: .previous, orientation: .portrait),
        FlipCommandDefinition(direction: .next, orientation: .landscape),
        FlipCommandDefinition(direction: .previous, orientation: .landscape)
    ]
}

final class RemoteControlService {
    private let connectionService: ConnectionService

    init(connectionService: ConnectionService) {
        self.connectionService = connectionService
    }

    func turnPage(settings: ConnectionSettings, direction: PageTurnDirection) async throws -> String {
        var resolvedSettings = settings
        if resolvedSettings.normalizedEventDevice == nil {
            resolvedSettings.eventDevice = try await connectionService.detectTouchDevice(settings: settings)
        }

        guard let event = resolvedSettings.normalizedEventDevice else {
            throw NSError(
                domain: "KindlePilot.RemoteControlService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L("缺少触控设备 eventX")]
            )
        }

        let client = connectionService.makeClient(settings: resolvedSettings)
        let eventDevice = "/dev/input/\(event)"
        let command = """
        resolution=$(fbset 2>/dev/null | awk -F'\"' '/mode/ {print $2; exit}'); \
        width=${resolution%x*}; \
        height=${resolution#*x}; \
        orientation=portrait; \
        if [ -n "$width" ] && [ -n "$height" ] && [ "$width" -gt "$height" ] 2>/dev/null; then orientation=landscape; fi; \
        event_file=/mnt/us/FlipCmd/\(direction.remoteEventName)_${orientation}.event; \
        if test ! -s "$event_file"; then echo "MISSING_FLIP_CMD $event_file"; exit 44; fi; \
        cat "$event_file" > \(shellQuote(eventDevice)); \
        /usr/bin/powerd_test -i >/dev/null 2>&1 || true; \
        echo "\(LF("%@完成", direction.logTitle)): $orientation, \(eventDevice)"
        """

        let result: SSHCommandResult
        do {
            result = try await client.exec(command: command)
        } catch KindleSSHClientError.commandFailed(_, let exitCode, let output, _) where exitCode == 44 {
            throw NSError(
                domain: "KindlePilot.RemoteControlService",
                code: 44,
                userInfo: [
                    NSLocalizedDescriptionKey: missingFlipCommandMessage(from: output)
                ]
            )
        }

        let output = result.trimmedOutput
        return output.isEmpty ? "\(LF("%@完成", direction.logTitle)): \(eventDevice)" : output
    }

    func missingFlipCommands(settings: ConnectionSettings) async throws -> [FlipCommandDefinition] {
        let client = connectionService.makeClient(settings: settings)
        let probeCommand = FlipCommandDefinition.all
            .map { "test -s \(shellQuote($0.remotePath)) || echo \(shellQuote($0.remotePath))" }
            .joined(separator: "; ")
        let result = try await client.exec(command: probeCommand)
        let missingPaths = Set(
            result.standardOutput
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        return FlipCommandDefinition.all.filter { missingPaths.contains($0.remotePath) }
    }

    func recordFlipCommand(
        settings: ConnectionSettings,
        definition: FlipCommandDefinition,
        duration: Int = 5
    ) async throws -> String {
        var resolvedSettings = settings
        if resolvedSettings.normalizedEventDevice == nil {
            resolvedSettings.eventDevice = try await connectionService.detectTouchDevice(settings: settings)
        }

        guard let event = resolvedSettings.normalizedEventDevice else {
            throw NSError(
                domain: "KindlePilot.RemoteControlService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L("缺少触控设备 eventX")]
            )
        }

        let client = connectionService.makeClient(settings: resolvedSettings)
        let eventDevice = "/dev/input/\(event)"
        let command = """
        mkdir -p /mnt/us/FlipCmd; \
        rm -f \(shellQuote(definition.remotePath)); \
        timeout \(duration) cat \(shellQuote(eventDevice)) > \(shellQuote(definition.remotePath)) 2>/dev/null; \
        code=$?; \
        if test -s \(shellQuote(definition.remotePath)); then echo recorded \(shellQuote(definition.remotePath)); exit 0; fi; \
        echo empty recording for \(shellQuote(definition.remotePath)) code=$code; \
        exit 45
        """

        let result = try await client.exec(command: command)
        let output = result.trimmedOutput
        if output.hasPrefix("recorded ") {
            return LF("%@录制完成", definition.title)
        }
        return output.isEmpty ? LF("%@录制完成", definition.title) : output
    }

    private func missingFlipCommandMessage(from output: String) -> String {
        let marker = "MISSING_FLIP_CMD "
        let missingPath = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.hasPrefix(marker) }?
            .dropFirst(marker.count)

        if let missingPath {
            return LF("缺少翻页命令: %@。请点击「检查命令」并录制对应手势。", String(missingPath))
        }

        return L("缺少翻页命令。请点击「检查命令」并录制对应手势。")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
