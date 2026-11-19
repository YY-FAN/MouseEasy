import Foundation

enum Scheme { enum Buttons { enum Mapping { enum Action {} } } }
typealias Target = Scheme.Buttons.Mapping.Action.OpenTarget

let support = URL(fileURLWithPath: "/tmp/local support", isDirectory: true)
let config = AppIdentity.configurationURL(applicationSupport: support)
precondition(config.path == "/tmp/local support/MouseWorkbenchDev/settings.json")
precondition(!config.path.contains("linearmouse"))

let target = Target(path: "/tmp/a file $(touch nope).sh", arguments: ["one argument", "$(touch nope)", ""], mode: .execute)
let request = target.executionRequest()
precondition(request.executable.path == "/bin/sh")
precondition(request.arguments == ["/tmp/a file $(touch nope).sh", "one argument", "$(touch nope)", ""])
let direct = Target(path: "/tmp/my executable", arguments: ["a b"], mode: .execute)
precondition(direct.executionRequest().executable.path == "/tmp/my executable")
precondition(direct.executionRequest().arguments == ["a b"])
let roundTrip = try JSONDecoder().decode(Target.self, from: JSONEncoder().encode(target))
precondition(roundTrip == target)
print("PASS: independent config path, literal script arguments, executable resolution, configuration round-trip; no process launched")

let script = FileManager.default.temporaryDirectory.appendingPathComponent("mouse-bash-\(UUID().uuidString).sh")
try Data("#!/bin/bash\nprintf test\n".utf8).write(to: script)
defer { try? FileManager.default.removeItem(at: script) }
let declared = Target(path: script.path, arguments: ["literal arg"], mode: .execute).executionRequest()
precondition(declared.executable.path == "/bin/bash")
precondition(declared.arguments == [script.path, "literal arg"])
print("PASS: non-executable script respects declared interpreter; nothing executed")
