#if DEBUG && os(iOS)
import Foundation

/// Launch arguments for reaching a state in the iPad simulator without tapping, for screenshots.
///   -play <title>   selects the play with that title (on the stage, chooses it)
///   -cue <label>    selects the cue with that name, in the Sketchpad and on the stage ("2.1" by label also works on the stage)
///   -unlock         unlocks the stage
extension AppModel {
    func applySimulatorAids() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(of flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        if let title = value(of: "-play"), let play = sketchpad.plays.first(where: { $0.title == title }) {
            sketchpad.selectPlay(play.id)
            if section == .stage { stage.choose(play.id) }
        }
        if let name = value(of: "-cue") {
            let cues = sketchpad.play?.scenes.flatMap(\.cues) ?? []
            if let cue = cues.first(where: { $0.name == name }) { sketchpad.selectCue(cue.id) }
            if let offset = stage.sheet.entries.firstIndex(where: { $0.cue.name == name || $0.label == name }) { stage.select(offset) }
        }
        if arguments.contains("-unlock"), !stage.isChoosing { stage.isLocked = false }
    }
}
#endif
