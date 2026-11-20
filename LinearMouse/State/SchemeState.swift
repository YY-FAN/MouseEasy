// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation

class SchemeState: ObservableObject {
    static let shared = SchemeState()

    private let configurationState: ConfigurationState = .shared
    private let deviceState: DeviceState = .shared

    private var subscriptions = Set<AnyCancellable>()

    @Published var currentApp: AppTarget?
    @Published var currentDisplay: String?

    init() {
        configurationState.$configuration
            .sink { [weak self] configuration in
                if let app = self?.currentApp, configuration.excludedApps?.contains(app) == true {
                    self?.currentApp = nil
                }
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        deviceState.$currentDeviceRef
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        deviceState.$currentDeviceMatcher
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
}

extension SchemeState {
    private var device: Device? {
        deviceState.currentDeviceRef?.value
    }

    private var deviceMatcher: DeviceMatcher? {
        deviceState.currentDeviceMatcher
    }

    private func deviceConditionMatches(
        _ conditionDeviceMatcher: DeviceMatcher,
        targetMatcher: DeviceMatcher?,
        targetDevice: Device?
    ) -> Bool {
        if let targetCategory = targetMatcher?.categoryOnlyValue {
            return conditionDeviceMatcher == DeviceMatcher(category: targetCategory)
        }

        if conditionDeviceMatcher.categoryOnlyValue != nil {
            return false
        }

        if let targetDevice {
            return conditionDeviceMatcher.match(with: targetDevice)
        }

        guard let targetMatcher else {
            return false
        }

        return conditionDeviceMatcher.match(with: targetMatcher)
    }

    private func matches(_ condition: Scheme.If, deviceMatcher: DeviceMatcher?, device: Device?,
                         app: AppTarget?, display: String?) -> Bool {
        let (appID, path, name) = extractAppComponents(from: app)
        guard let conditionDevice = condition.device else { return false }
        return deviceConditionMatches(conditionDevice, targetMatcher: deviceMatcher, targetDevice: device)
            && condition.app == appID && condition.processPath == path && condition.processName == name
            && condition.display == display
    }

    private func hasMatchingSchemes(for matcher: DeviceMatcher?, device: Device?, app: AppTarget?, display: String?) -> Bool {
        schemes.contains { scheme in
            scheme.if?.contains { matches($0, deviceMatcher: matcher, device: device, app: app, display: display) } == true
        }
    }

    private func deleteMatchingSchemes(for matcher: DeviceMatcher?, device: Device?, app: AppTarget?, display: String?) {
        schemes = schemes.compactMap { scheme in
            guard let conditions = scheme.if else { return scheme }
            let remaining = conditions.filter { !matches($0, deviceMatcher: matcher, device: device, app: app, display: display) }
            guard remaining.count != conditions.count else { return scheme }
            guard !remaining.isEmpty else { return nil }
            var changed = scheme
            changed.if = remaining
            return changed
        }
    }

    var isSchemeValid: Bool {
        guard deviceMatcher != nil else {
            return false
        }

        return true
    }

    var hasPortableMouseDefaults: Bool {
        configurationState.configuration.hasPortableMouseDefaults
    }

    var canSaveCurrentMouseAsDefaults: Bool {
        guard let portableDefaultsSourceMatcher else { return false }
        return configurationState.configuration.canUseAsPortableMouseDefaultsSource(portableDefaultsSourceMatcher)
    }

    @discardableResult
    func saveCurrentMouseAsDefaults() throws -> Configuration.PortableMouseDefaultsSummary {
        guard let portableDefaultsSourceMatcher else { throw Configuration.PortableMouseDefaultsError.selectSpecificMouse }
        return try configurationState.savePortableMouseDefaults(from: portableDefaultsSourceMatcher)
    }

    private var portableDefaultsSourceMatcher: DeviceMatcher? {
        guard let deviceMatcher else { return nil }
        if deviceMatcher.categoryOnlyValue == .mouse {
            guard let device, device.category == .mouse else { return nil }
            return DeviceMatcher(activeOf: device)
        }
        return deviceMatcher.category == [.mouse] ? deviceMatcher : nil
    }

    var schemes: [Scheme] {
        get { configurationState.configuration.schemes }
        set { configurationState.configuration.schemes = newValue }
    }

    var currentAppName: String? {
        currentApp?.displayName
    }

    var showsMirrorScrollSettings: Bool {
        currentApp == nil || currentApp == .bundle(IPhoneMirroringScrollCompatibility.bundleIdentifier)
    }

    var scheme: Scheme {
        get {
            guard let deviceMatcher else {
                return Scheme()
            }

            let (app, processPath, processName) = extractAppComponents(from: currentApp)

            if case let .at(index) = schemes.schemeIndex(
                ofDeviceMatcher: deviceMatcher,
                ofApp: app,
                ofProcessPath: processPath,
                ofProcessName: processName,
                ofDisplay: currentDisplay
            ) {
                return schemes[index]
            }

            var ifCondition = Scheme.If(device: deviceMatcher.condition)
            ifCondition.app = app
            ifCondition.processPath = processPath
            ifCondition.processName = processName
            ifCondition.display = currentDisplay

            return Scheme(if: [ifCondition])
        }

        set {
            guard let deviceMatcher else {
                return
            }

            let (app, processPath, processName) = extractAppComponents(from: currentApp)

            switch schemes.schemeIndex(
                ofDeviceMatcher: deviceMatcher,
                ofApp: app,
                ofProcessPath: processPath,
                ofProcessName: processName,
                ofDisplay: currentDisplay
            ) {
            case let .at(index):
                schemes[index] = newValue
            case let .insertAt(index):
                let isDeviceWide = app == nil && processPath == nil && processName == nil && currentDisplay == nil
                schemes.insert(
                    newValue,
                    at: insertionIndex(index, for: deviceMatcher, isDeviceWide: isDeviceWide)
                )
            }
        }
    }

    /// The first device-wide scheme of a device behind a receiver goes between
    /// the receiver's device-wide and app or display schemes.
    private func insertionIndex(_ index: Int, for matcher: DeviceMatcher, isDeviceWide: Bool) -> Int {
        guard isDeviceWide,
              let device,
              matcher.categoryOnlyValue == nil,
              schemes.allDeviceMatcherSpecificSchemes(of: matcher).isEmpty else {
            return index
        }

        let physicalDeviceMatcher = DeviceMatcher(of: device)
        guard physicalDeviceMatcher != matcher else {
            return index
        }

        return schemes.insertionIndex(ofDeviceWideSchemeBehind: physicalDeviceMatcher)
    }

    /// Hardware settings belong to the selected device, which may be a device
    /// behind a receiver, rather than to the receiver.
    private var deviceSchemeMatcher: DeviceMatcher? {
        guard let device else {
            return nil
        }

        if let deviceMatcher,
           deviceMatcher.categoryOnlyValue == nil,
           deviceMatcher.condition.match(with: device) {
            return deviceMatcher
        }

        return DeviceMatcher(activeOf: device)
    }

    var deviceScheme: Scheme {
        get {
            guard let deviceSchemeMatcher else {
                return Scheme()
            }

            if case let .at(index) = schemes.schemeIndex(
                ofDeviceMatcher: deviceSchemeMatcher,
                ofApp: nil,
                ofProcessPath: nil,
                ofProcessName: nil,
                ofDisplay: nil
            ) {
                return schemes[index]
            }

            return Scheme(if: [Scheme.If(device: deviceSchemeMatcher.condition)])
        }

        set {
            guard let deviceSchemeMatcher else {
                return
            }

            switch schemes.schemeIndex(
                ofDeviceMatcher: deviceSchemeMatcher,
                ofApp: nil,
                ofProcessPath: nil,
                ofProcessName: nil,
                ofDisplay: nil
            ) {
            case let .at(index):
                schemes[index] = newValue
            case let .insertAt(index):
                schemes.insert(newValue, at: insertionIndex(index, for: deviceSchemeMatcher, isDeviceWide: true))
            }
        }
    }

    private func extractAppComponents(
        from target: AppTarget?
    ) -> (app: String?, processPath: String?, processName: String?) {
        switch target {
        case .none:
            return (nil, nil, nil)
        case let .bundle(bundleIdentifier):
            return (bundleIdentifier, nil, nil)
        case let .executable(path):
            return (nil, path, nil)
        case let .executableName(name):
            return (nil, nil, name)
        }
    }

    var mergedScheme: Scheme {
        guard let deviceMatcher else {
            return Scheme()
        }

        let (app, processPath, processName) = extractAppComponents(from: currentApp)

        var context = Scheme.MatchContext(
            deviceMatcher: deviceMatcher,
            app: app,
            display: currentDisplay,
            processName: processName,
            processPath: processPath
        )
        // A device behind a receiver also inherits the receiver's schemes.
        if let device, deviceMatcher.categoryOnlyValue == nil, deviceMatcher.condition.match(with: device) {
            let physicalDeviceMatcher = DeviceMatcher(of: device)
            if physicalDeviceMatcher != deviceMatcher {
                context.devices.append(physicalDeviceMatcher)
            }
        }

        return configurationState.configuration.matchScheme(in: context)
    }

    var hasMatchingSchemes: Bool {
        hasMatchingSchemes(forApp: currentApp, forDisplay: currentDisplay)
    }

    func hasMatchingSchemes(for matcher: DeviceMatcher?, forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: matcher, device: nil, app: app, display: display)
    }

    func hasMatchingSchemes(for device: Device?, forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: device.map { DeviceMatcher(of: $0) }, device: device, app: app, display: display)
    }

    func hasMatchingSchemes(forApp app: AppTarget?, forDisplay display: String?) -> Bool {
        hasMatchingSchemes(for: deviceMatcher, device: nil, app: app, display: display)
    }

    func ensureAppSchemes(for apps: [AppTarget], forDisplay display: String?) {
        guard let deviceMatcher else { return }
        var updated = schemes
        for target in apps {
            // Existing overrides, including shared rules, keep their values.
            guard !updated.contains(where: { scheme in
                scheme.if?.contains { matches($0, deviceMatcher: deviceMatcher, device: nil, app: target, display: display) } == true
            }) else { continue }
            let (app, path, name) = extractAppComponents(from: target)
            guard case let .insertAt(index) = updated.schemeIndex(
                ofDeviceMatcher: deviceMatcher, ofApp: app, ofProcessPath: path,
                ofProcessName: name, ofDisplay: display
            ) else { continue }
            var condition = Scheme.If(device: deviceMatcher.condition)
            condition.app = app
            condition.processPath = path
            condition.processName = name
            condition.display = display
            updated.insert(Scheme(if: [condition]), at: index)
        }
        if updated.count != schemes.count { schemes = updated }
    }

    func deleteMatchingSchemes() {
        deleteMatchingSchemes(forApp: currentApp, forDisplay: currentDisplay)
    }

    func deleteMatchingSchemes(for matcher: DeviceMatcher?, forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: matcher, device: nil, app: app, display: display)
    }

    func deleteMatchingSchemes(for device: Device?, forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: device.map { DeviceMatcher(of: $0) }, device: device, app: app, display: display)
    }

    func deleteMatchingSchemes(forApp app: AppTarget?, forDisplay display: String?) {
        deleteMatchingSchemes(for: deviceMatcher, device: nil, app: app, display: display)
    }
}
