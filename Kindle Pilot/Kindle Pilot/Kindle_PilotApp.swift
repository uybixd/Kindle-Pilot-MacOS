import Foundation
import SwiftUI

struct Kindle_PilotApp: App {
    @StateObject private var languageStore = AppLanguageStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
        }
    }
}

@main
enum KindlePilotMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        if environment["KINDLE_PILOT_ASKPASS"] == "1" {
            let password = environment["KINDLE_PILOT_PASSWORD"] ?? ""
            FileHandle.standardOutput.write(Data((password + "\n").utf8))
            Darwin.exit(0)
        }

        #if DEBUG
        if environment["KINDLE_PILOT_RUN_REGRESSION_CHECKS"] == "1" {
            do {
                try ClippingsParserRegressionChecks.runAll()
                FileHandle.standardOutput.write(Data("Regression checks passed\n".utf8))
                Darwin.exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                Darwin.exit(1)
            }
        }
        #endif

        Kindle_PilotApp.main()
    }
}
