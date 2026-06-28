import Foundation

enum TouchDeviceDetector {
    static func extractEventDevice(from text: String) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for index in lines.indices where lines[index].contains("N: Name=\"pt_mt\"") {
            var cursor = lines.index(after: index)
            while cursor < lines.endIndex, !lines[cursor].hasPrefix("I:") {
                if let event = firstEvent(in: lines[cursor]) {
                    return event
                }
                cursor = lines.index(after: cursor)
            }
        }

        var blocks: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.hasPrefix("I:"), !current.isEmpty {
                blocks.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }

        for block in blocks {
            let hasTouchName = block.contains { $0.contains("N: Name=\"pt_mt\"") }
            let hasAbsoluteAxis = block.contains { $0.hasPrefix("B: ABS=") }
            guard hasTouchName, hasAbsoluteAxis else { continue }

            for line in block where line.hasPrefix("H: Handlers=") {
                if let event = firstEvent(in: line) {
                    return event
                }
            }
        }

        return nil
    }

    private static func firstEvent(in line: String) -> String? {
        guard let range = line.range(of: #"event\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range])
    }
}
