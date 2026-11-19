// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors

import CoreGraphics
import Foundation

@main
struct PortableMouseDefaultsTests {
    private static func validateFirstLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let first = try Configuration.loadOrCreate(at: url, previouslyConfigured: false)
        let saved = try Configuration.load(from: url)
        precondition(first == saved && first.schemes.count == 1)
        let mouse = first.matchScheme(withDeviceMatcher: .init(category: .mouse), withApp: "example.app", withDisplay: "Other")
        precondition(mouse.scrolling.smoothed.vertical == Scheme.Scrolling.Smoothed.Preset.flow.defaultConfiguration)
        precondition(mouse.scrolling.smoothed.horizontal == nil && mouse.scrolling.preserveContinuousScrolling == true)
        precondition(mouse.scrolling.reverse.vertical == nil && mouse.scrolling.modifiers.vertical == nil)
        precondition(mouse.pointer == Scheme.Pointer() && mouse.buttons.mappings == nil)
        let trackpad = first.matchScheme(withDeviceMatcher: .init(category: .trackpad))
        precondition(trackpad.scrolling.smoothed.vertical == nil && trackpad.scrolling.preserveContinuousScrolling == nil)
        let mirror = first.mirrorScrolling ?? .init()
        precondition(mirror.isEnabled && mirror.resolvedWheelMode == .smooth)

        let preset = Scheme.Buttons.windowSwitchingPreset
        precondition(preset.count == 2 && mouse.buttons.windowSwitchingButtonsAreAvailable)
        precondition(preset[0].trigger?.input == .button(.mouse(3)) && preset[0].outcomes?.shortPress == .arg1(.keyPress([.command, .backquote])))
        precondition(preset[1].trigger?.input == .button(.mouse(4)) && preset[1].outcomes?.shortPress == .arg1(.keyPress([.command, .tab])))
        var buttons = mouse.buttons
        buttons.mappings = [.init(button: .mouse(3), action: .arg0(.missionControl))]
        precondition(!buttons.windowSwitchingButtonsAreAvailable)
        buttons.mappings = preset
        precondition(!buttons.windowSwitchingButtonsAreAvailable)

        for text in [#"{ "schemes": [] }"#, #"{ "schemes":[{"scrolling":{"reverse":true}}], "mirrorScrolling":{"speed":2} }"#] {
            let bytes = Data(text.utf8)
            try bytes.write(to: url)
            for previouslyConfigured in [true, false] {
                let upgraded = try Configuration.loadOrCreate(at: url, previouslyConfigured: previouslyConfigured)
                let expected = try Configuration.load(from: bytes)
                let after = try Data(contentsOf: url)
                precondition(upgraded == expected && bytes == after)
            }
        }
        let malformed = Data("invalid".utf8)
        try malformed.write(to: url)
        do {
            _ = try Configuration.loadOrCreate(at: url, previouslyConfigured: false)
            preconditionFailure("An unreadable configuration must not be reset")
        } catch Configuration.ConfigurationError.parseError {
            let after = try Data(contentsOf: url)
            precondition(after == malformed)
        }
        try FileManager.default.removeItem(at: url)
        let returning = try Configuration.loadOrCreate(at: url, previouslyConfigured: true)
        precondition(returning.schemes.isEmpty)
        print("First install, native defaults, optional side keys, existing/empty/malformed profiles and returning-install checks passed")
    }

    static func main() throws {
        try validateFirstLaunch()
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        // Synthetic fixture: two different mice with intentionally different
        // overrides. It is not a copy of the user's private device identities.
        let json = #"""
        {"schemes":[
          {"if":{"device":{"category":"mouse"}},"scrolling":{"smoothed":{"enabled":true,"preset":"flow"}}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"serialNumber":"test-A","category":"mouse"}},
           "scrolling":{"reverse":{"vertical":true,"horizontal":false},"speed":2,"modifiers":{"control":{"type":"pinchZoom"}},"hotkeys":{"acceleration":{"type":"mouse","code":256},"accelerationScale":3}},
           "pointer":{"hardwareDPI":2400,"speed":0.5},"logitech":{"highResolutionWheel":true},
           "buttons":{"mappings":[
              {"trigger":{"input":{"button":4}},"outcomes":{"shortPress":{"keyPress":["command","tab"]}}},
              {"trigger":{"input":{"button":{"kind":"logitechControl","controlID":12}}},"outcomes":{"shortPress":"showDesktop"}}
           ],"keyboardMappings":[{"keyCode":0,"action":"missionControl"}],"swipe":{"threshold":60},"clickDebouncing":{"timeout":50},"autoScroll":{"enabled":true,"trigger":{"button":2}}}},
          {"if":{"device":{"vendorID":4660,"productID":4098,"category":"mouse"}},"scrolling":{"reverse":false}},
          {"if":{"device":{"category":"trackpad"}},"scrolling":{"reverse":false}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"serialNumber":"test-A","category":"mouse"},"app":"test.special"},"scrolling":{"reverse":false},"buttons":{"mappings":[{"button":4,"action":"missionControl"}]}},
          {"if":[{"device":{"vendorID":4660,"productID":4097,"category":"mouse"}},{"app":"test.other"}],"scrolling":{"speed":9}}
        ]}
        """#
        let source = DeviceMatcher(vendorID: 4660, productID: 4097, serialNumber: "test-A", category: [.mouse])
        let newMouse = DeviceMatcher(vendorID: 6000, productID: 7000, category: [.mouse])
        let otherMouse = DeviceMatcher(vendorID: 4660, productID: 4098, category: [.mouse])
        let trackpad = DeviceMatcher(category: .trackpad)
        var config = try Configuration.load(from: json)
        let originals = config.schemes
        let trackpadBefore = config.matchScheme(withDeviceMatcher: trackpad)
        check(config.canUseAsPortableMouseDefaultsSource(source), "A concrete source profile must be selected")
        let report = try config.setPortableMouseDefaults(from: source)
        check(report.changed, "The first promotion must change category defaults")
        check(report.sourceSchemeCount == 1, "App and OR rules must not be counted as device-wide sources")
        check(report.ordinaryButtonMappings == 1, "Only one generic side-button binding is portable")
        check(report.excludedDeviceSpecificMappings == 1, "Logitech identity input must be excluded")
        check(config.hasPortableMouseDefaults, "Default availability must be visible to the UI")
        check(Array(config.schemes.dropFirst()) == Array(originals.dropFirst()), "Every original device/app/OR rule must remain unchanged")

        let inherited = config.matchScheme(withDeviceMatcher: newMouse)
        check(inherited.scrolling.reverse.vertical == true, "A new mouse must inherit vertical reverse")
        check(inherited.scrolling.reverse.horizontal == false, "Axis values must remain independent")
        check(inherited.scrolling.smoothed.vertical?.isEnabled == true, "New mice keep the shared smooth preset")
        check(inherited.scrolling.speed.vertical == 2, "Portable scroll speed must follow the selected source")
        check(inherited.scrolling.modifiers.vertical?.control == .pinchZoom, "Modifier-wheel preferences must carry over")
        check(inherited.scrolling.hotkeys.acceleration == nil, "Vendor virtual mouse hotkeys must stay device-specific")
        check(inherited.scrolling.hotkeys.accelerationScale == nil, "Vendor hotkey speed scale must not be broadened")
        check(inherited.pointer.hardwareDPI == nil && inherited.pointer.speed == nil, "Hardware DPI and per-device pointer speed must not migrate")
        check(inherited.logitech.highResolutionWheel == nil, "Logitech hardware settings must not migrate")
        check(inherited.buttons.keyboardMappings == nil, "Keyboard-only actions must not be broadened")
        check(inherited.buttons.clickDebouncing.timeout == nil, "Hardware debouncing must not migrate")
        check(inherited.buttons.swipe.threshold == 60, "Generic mouse gesture thresholds must migrate")
        check(inherited.buttons.autoScroll.enabled == true, "Ordinary auto-scroll trigger must migrate")
        check(config.matchScheme(withDeviceMatcher: otherMouse).scrolling.reverse.vertical == false, "An existing mouse's explicit reverse=false must win")
        check(config.matchScheme(withDeviceMatcher: trackpad) == trackpadBefore, "Trackpad behavior must stay identical")
        check(config.matchScheme(withDeviceMatcher: source, withApp: "test.special").scrolling.reverse.vertical == false, "Application-specific overrides must still win")
        check(config.matchScheme(withDeviceMatcher: source).scrolling.speed.vertical == 9, "Original OR conditions must remain active only in their existing scopes")

        // A mouse without side keys never emits their inputs; the real pure
        // recognizer must leave its ordinary click stream untouched.
        var engine = ButtonMappingEngine(mappings: inherited.buttons.mappings ?? [])
        let down = engine.buttonDown(.mouse(0), modifierFlags: [], at: 0)
        let up = engine.buttonUp(.mouse(0), modifierFlags: [], at: 1)
        check(!down.consumesEvent && !up.consumesEvent && down.actions.isEmpty && up.actions.isEmpty,
              "Missing side buttons must not interfere with primary clicking")
        check(inherited.scrolling.reverse.vertical == true, "Button capability must not disable scroll reverse")
        let sideDown = engine.buttonDown(.mouse(4), modifierFlags: [], at: 2)
        let sideUp = engine.buttonUp(.mouse(4), modifierFlags: [], at: 3)
        check(sideDown.consumesEvent || sideDown.buffersEvent, "A real side button must activate its inherited mapping")
        check(sideUp.actions == [.arg1(.keyPress([.command, .tab]))], "The inherited action must remain the configured shortcut")

        let afterFirst = config
        let repeated = try config.setPortableMouseDefaults(from: source)
        check(!repeated.changed && config == afterFirst, "Promotion must be idempotent")
        let roundTrip = try Configuration.load(from: config.dump())
        check(roundTrip == config, "The promoted configuration must round-trip")

        var noCategory = Configuration(schemes: [originals[1], originals[2]])
        _ = try noCategory.setPortableMouseDefaults(from: source)
        check(noCategory.schemes.first?.if?.first?.device?.categoryOnlyValue == .mouse, "Missing category defaults must be inserted before specific mice")
        check(noCategory.matchScheme(withDeviceMatcher: otherMouse).scrolling.reverse.vertical == false, "Inserted defaults must not override an existing mouse")

        let beforeInvalid = config
        do { _ = try config.setPortableMouseDefaults(from: DeviceMatcher(category: .mouse)); preconditionFailure("Category source should be refused") }
        catch Configuration.PortableMouseDefaultsError.selectSpecificMouse {}
        check(config == beforeInvalid, "Refused source must not mutate the config")
        do { _ = try config.setPortableMouseDefaults(from: newMouse); preconditionFailure("Unknown source should be refused") }
        catch Configuration.PortableMouseDefaultsError.missingSourceProfile {}
        check(config == beforeInvalid, "An unknown mouse must not cause a guess among old profiles")
        var lateDefault = Configuration(schemes: [originals[1], originals[0]])
        let beforeLate = lateDefault
        do { _ = try lateDefault.setPortableMouseDefaults(from: source); preconditionFailure("Unsafe order should be refused") }
        catch Configuration.PortableMouseDefaultsError.incompatibleRuleOrder {}
        check(lateDefault == beforeLate, "Unknown rule order must not be silently rewritten")
        var hardwareOnly = try Configuration.load(from: #"{"schemes":[{"if":{"device":{"vendorID":4660,"productID":4097,"serialNumber":"test-A","category":"mouse"}},"pointer":{"hardwareDPI":3200},"scrolling":{"hotkeys":{"acceleration":{"type":"mouse","code":256},"accelerationScale":3}}}]}"#)
        let beforeHardwareOnly = hardwareOnly
        do { _ = try hardwareOnly.setPortableMouseDefaults(from: source); preconditionFailure("Hardware-only source should be refused") }
        catch Configuration.PortableMouseDefaultsError.noPortableSettings {}
        check(hardwareOnly == beforeHardwareOnly, "A hardware-only source must not create empty portable defaults")

        var pruningOnly = afterFirst
        let categoryBeforePrune = pruningOnly.schemes[0]
        let pruneReport = try pruningOnly.setPortableMouseDefaults(from: source, sourceFollowsDefaults: true)
        check(pruneReport.changed && pruningOnly.schemes[0] == categoryBeforePrune,
              "Source-only pruning must report changed even when category values already match")

        var broadSource = try Configuration.load(from: #"{"schemes":[{"if":{"device":{"vendorID":4660,"category":"mouse"}},"scrolling":{"reverse":true}}]}"#)
        let beforeBroad = broadSource
        do { _ = try broadSource.setPortableMouseDefaults(from: source, sourceFollowsDefaults: true); preconditionFailure("A rule covering other devices must not be cleared") }
        catch Configuration.PortableMouseDefaultsError.sourceScopeTooBroad {}
        check(broadSource == beforeBroad, "A broad source scope refusal must not affect other devices")

        var following = try Configuration.load(from: json)
        let followingOriginal = following
        let sourceBefore = following.matchScheme(withDeviceMatcher: source)
        let followReport = try following.setPortableMouseDefaults(from: source, sourceFollowsDefaults: true)
        let sourceAfter = following.matchScheme(withDeviceMatcher: source)
        check(followReport.sourceFollowsDefaults && followReport.changed, "The follow-defaults choice must be explicit and reported")
        check(sourceAfter.scrolling == sourceBefore.scrolling, "The source's effective scrolling must remain identical after promotion")
        check(sourceAfter.buttons == sourceBefore.buttons, "The source's effective button behavior must remain identical after promotion")
        check(sourceAfter.pointer == sourceBefore.pointer && sourceAfter.logitech == sourceBefore.logitech,
              "Source pointer/DPI and hardware settings must stay untouched")
        check(following.schemes[1].scrolling.$reverse == nil && following.schemes[1].scrolling.$speed == nil,
              "Migrated scroll fields must no longer pin the source to old values")
        check(following.schemes[1].scrolling.hotkeys.acceleration?.code == 256
              && following.schemes[1].scrolling.hotkeys.accelerationScale == 3,
              "Source vendor hotkeys and their own multiplier must be retained")
        check(following.schemes[1].buttons.mappings?.count == 1
              && following.schemes[1].buttons.mappings?.first?.trigger?.statefulButtons.contains(where: { $0.logitechControl != nil }) == true,
              "Only ordinary mappings are moved; vendor button mappings stay on source")
        check(following.schemes[1].buttons.keyboardMappings == followingOriginal.schemes[1].buttons.keyboardMappings
              && following.schemes[1].buttons.clickDebouncing == followingOriginal.schemes[1].buttons.clickDebouncing,
              "Keyboard actions and device debouncing must remain source-specific")
        check(Array(following.schemes.dropFirst(2)) == Array(followingOriginal.schemes.dropFirst(2)),
              "Other mice, trackpad, app and OR rules must not be touched by source-follow migration")
        following.schemes[0].scrolling.reverse.vertical = false
        following.schemes[0].buttons.mappings?[0].outcomes?.shortPress = .arg0(.missionControl)
        let followsLater = following.matchScheme(withDeviceMatcher: source)
        check(followsLater.scrolling.reverse.vertical == false, "Changing common reverse must affect the promoted source too")
        var followsEngine = ButtonMappingEngine(mappings: followsLater.buttons.mappings ?? [])
        _ = followsEngine.buttonDown(.mouse(4), modifierFlags: [], at: 0)
        check(followsEngine.buttonUp(.mouse(4), modifierFlags: [], at: 1).actions == [.arg0(.missionControl)],
              "Changing common button action must affect the promoted source too")
        check(following.matchScheme(withDeviceMatcher: otherMouse).scrolling.reverse.vertical == false,
              "A different mouse must keep its explicit override")
        let followingStable = following
        let repeatFollow = try following.setPortableMouseDefaults(from: source, sourceFollowsDefaults: true)
        check(!repeatFollow.changed && following == followingStable, "Follow migration must remain idempotent")
        let repeatWithoutFollow = try following.setPortableMouseDefaults(from: source)
        check(!repeatWithoutFollow.changed && following == followingStable,
              "Promotion without follow must stay idempotent after a completed follow migration")

        // Realistic legacy structure: two exact profiles surround a profile
        // for the same full model identity which omits only the serial.
        var aliases = try Configuration.load(from: #"""
        {"schemes":[
          {"if":{"device":{"category":"mouse"}},"scrolling":{"smoothed":{"enabled":true,"preset":"flow"}}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"productName":"Test Mouse","serialNumber":"test-A","category":"mouse"}},"scrolling":{"reverse":true},"buttons":{"mappings":[{"button":4,"action":"missionControl"}]}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"productName":"Test Mouse","category":"mouse"}},"scrolling":{"speed":2},"pointer":{"hardwareDPI":2400,"speed":0.7}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"productName":"Test Mouse","serialNumber":"test-A","category":"mouse"}},"scrolling":{"reverse":true},"buttons":{"mappings":[{"button":5,"action":"showDesktop"}]}},
          {"if":{"device":{"vendorID":4660,"productID":4097,"productName":"Test Mouse","serialNumber":"test-B","category":"mouse"}},"scrolling":{"reverse":false,"speed":7},"pointer":{"speed":0.2},"buttons":{"mappings":[{"button":4,"action":"launchpad"}]}}
        ]}
        """#)
        let namedSource = DeviceMatcher(vendorID: 4660, productID: 4097, productName: "Test Mouse", serialNumber: "test-A", category: [.mouse])
        let differentSerial = DeviceMatcher(vendorID: 4660, productID: 4097, productName: "Test Mouse", serialNumber: "test-B", category: [.mouse])
        let aliasOriginal = aliases
        let aliasSourceBefore = aliases.matchScheme(withDeviceMatcher: namedSource)
        let aliasReport = try aliases.setPortableMouseDefaults(from: namedSource, sourceFollowsDefaults: true)
        let aliasSourceAfter = aliases.matchScheme(withDeviceMatcher: namedSource)
        check(aliasReport.changed && aliasReport.sourceSchemeCount == 3,
              "Both exact profiles and the serial-less full model alias must be recognized")
        check(aliasSourceAfter.scrolling == aliasSourceBefore.scrolling
              && aliasSourceAfter.buttons == aliasSourceBefore.buttons,
              "Model alias promotion must preserve the source's effective scrolling and buttons")
        check(aliases.schemes[2].$scrolling == nil && aliases.schemes[2].pointer == aliasOriginal.schemes[2].pointer,
              "Model alias portable fields move while hardware and pointer settings stay scoped")
        check(aliases.schemes[4] == aliasOriginal.schemes[4],
              "An explicitly different serial profile must remain unchanged")
        aliases.schemes[0].scrolling.reverse.vertical = false
        aliases.schemes[0].scrolling.speed.vertical = 3
        aliases.schemes[0].buttons.mappings?[0].outcomes?.shortPress = .arg0(.showDesktop)
        let aliasFollows = aliases.matchScheme(withDeviceMatcher: namedSource)
        check(aliasFollows.scrolling.reverse.vertical == false && aliasFollows.scrolling.speed.vertical == 3,
              "A cleared same-model alias must not pin the source to old common scroll values")
        var aliasEngine = ButtonMappingEngine(mappings: aliasFollows.buttons.mappings ?? [])
        _ = aliasEngine.buttonDown(.mouse(4), modifierFlags: [], at: 0)
        check(aliasEngine.buttonUp(.mouse(4), modifierFlags: [], at: 1).actions == [.arg0(.showDesktop)],
              "Common button changes must reach a source with old same-model aliases")
        let serialOverride = aliases.matchScheme(withDeviceMatcher: differentSerial)
        check(serialOverride.scrolling.reverse.vertical == false && serialOverride.scrolling.speed.vertical == 7,
              "A different serial's explicit scrolling must still override shared defaults")
        var serialEngine = ButtonMappingEngine(mappings: serialOverride.buttons.mappings ?? [])
        _ = serialEngine.buttonDown(.mouse(4), modifierFlags: [], at: 0)
        check(serialEngine.buttonUp(.mouse(4), modifierFlags: [], at: 1).actions == [.arg0(.launchpad)],
              "A different serial's explicit button action must still override shared defaults")
        let aliasStable = aliases
        let aliasRepeated = try aliases.setPortableMouseDefaults(from: namedSource, sourceFollowsDefaults: true)
        check(!aliasRepeated.changed && aliases == aliasStable, "Model-alias follow migration must remain idempotent")

        print("PASS: \(checks) portable mouse defaults checks; production matching, typed projection, real button recognizer, explicit overrides and refusal cases")
        print("0 device reads, 0 input events posted; private user configuration was not modified")
    }
}
