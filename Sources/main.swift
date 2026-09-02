import AppKit
import CoreGraphics
import Darwin
import Foundation

private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
private typealias GetBrightness = @convention(c) (
    CGDirectDisplayID,
    UnsafeMutablePointer<Float>
) -> Int32
private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias BrightnessChanged = @convention(c) (
    CGDirectDisplayID,
    Double
) -> Void

private struct DisplayServices {
    let canChange: CanChangeBrightness
    let get: GetBrightness
    let set: SetBrightness
    let changed: BrightnessChanged?

    init() throws {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/" +
            "DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw KeeperError.frameworkLoad(errorText())
        }

        canChange = try Self.load(
            "DisplayServicesCanChangeBrightness",
            from: handle,
            as: CanChangeBrightness.self
        )
        get = try Self.load(
            "DisplayServicesGetBrightness",
            from: handle,
            as: GetBrightness.self
        )
        set = try Self.load(
            "DisplayServicesSetBrightness",
            from: handle,
            as: SetBrightness.self
        )
        changed = Self.loadOptional(
            "DisplayServicesBrightnessChanged",
            from: handle,
            as: BrightnessChanged.self
        )
    }

    private static func load<T>(
        _ name: String,
        from handle: UnsafeMutableRawPointer,
        as _: T.Type
    ) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw KeeperError.missingSymbol(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private static func loadOptional<T>(
        _ name: String,
        from handle: UnsafeMutableRawPointer,
        as _: T.Type
    ) -> T? {
        guard let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private enum KeeperError: LocalizedError {
    case frameworkLoad(String)
    case missingSymbol(String)

    var errorDescription: String? {
        switch self {
        case let .frameworkLoad(message):
            "Could not load DisplayServices: \(message)"
        case let .missingSymbol(name):
            "DisplayServices is missing \(name)"
        }
    }
}

private struct DisplayTarget {
    let id: CGDirectDisplayID
    let name: String
    let brightness: Float
}

private let brightnessNudge: Float = 1.0 / 128.0

private func isTargetDisplayName(_ name: String) -> Bool {
    name.localizedCaseInsensitiveContains("LG UltraFine")
}

private func temporaryBrightness(for target: Float) -> Float {
    if target >= brightnessNudge {
        return target - brightnessNudge
    }
    return min(1.0, target + brightnessNudge)
}

private func runSelfTest() {
    precondition(isTargetDisplayName("LG UltraFine"))
    precondition(isTargetDisplayName("LG UltraFine (3)"))
    precondition(isTargetDisplayName("lg ultrafine 5k"))
    precondition(!isTargetDisplayName("Apple Studio Display"))
    precondition(!isTargetDisplayName("LG UltraWide"))
    precondition(!isTargetDisplayName("Unknown display"))
    precondition(temporaryBrightness(for: 1.0) == 1.0 - brightnessNudge)
    precondition(temporaryBrightness(for: brightnessNudge) == 0.0)
    precondition(temporaryBrightness(for: 0.0) == brightnessNudge)
    print("self-test passed")
}

private final class BrightnessKeeper: @unchecked Sendable {
    private let services: DisplayServices
    private var scheduledRepair: DispatchWorkItem?
    private var lastRepair = Date.distantPast
    private let eventDelay: TimeInterval = 1.0
    private let duplicateWindow: TimeInterval = 4.0
    private let pulseDuration: TimeInterval = 0.12

    init(services: DisplayServices) {
        self.services = services
    }

    func listDisplays() {
        for display in onlineDisplays() {
            var brightness: Float = -1
            let result = services.get(display.id, &brightness)
            let supported = services.canChange(display.id)
            print(
                String(
                    format: "%@ id=0x%08x supported=%@ result=%d brightness=%.4f",
                    display.name,
                    display.id,
                    supported ? "yes" : "no",
                    result,
                    brightness
                )
            )
        }
    }

    @discardableResult
    func repairNow(reason: String) -> Int {
        let targets = ultrafineTargets()
        guard !targets.isEmpty else {
            log("No online LG UltraFine displays were ready (\(reason))")
            return 0
        }

        log("Repairing \(targets.count) LG UltraFine display(s) (\(reason))")
        var nudged: [DisplayTarget] = []
        for target in targets {
            let temporary = temporaryBrightness(for: target.brightness)
            let result = services.set(target.id, temporary)
            if result == 0 {
                nudged.append(target)
            } else {
                log(
                    String(
                        format: "%@ 0x%08x nudge failed: %d",
                        target.name,
                        target.id,
                        result
                    )
                )
            }
        }

        guard !nudged.isEmpty else {
            return 0
        }

        Thread.sleep(forTimeInterval: pulseDuration)
        for target in nudged {
            let result = services.set(target.id, target.brightness)
            if result == 0 {
                services.changed?(target.id, Double(target.brightness))
                log(
                    String(
                        format: "%@ 0x%08x restored to %.4f",
                        target.name,
                        target.id,
                        target.brightness
                    )
                )
            } else {
                log(
                    String(
                        format: "%@ 0x%08x restore failed: %d",
                        target.name,
                        target.id,
                        result
                    )
                )
            }
        }
        lastRepair = Date()
        return nudged.count
    }

    func scheduleRepair(reason: String) {
        if Date().timeIntervalSince(lastRepair) < duplicateWindow {
            log("Ignoring duplicate event (\(reason))")
            return
        }

        scheduledRepair?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.repairNow(reason: reason)
        }
        scheduledRepair = work
        DispatchQueue.main.asyncAfter(deadline: .now() + eventDelay, execute: work)
        log("Scheduled repair after \(eventDelay)s (\(reason))")
    }

    private func ultrafineTargets() -> [DisplayTarget] {
        onlineDisplays().compactMap { display in
            guard isTargetDisplayName(display.name),
                  services.canChange(display.id)
            else {
                return nil
            }

            var brightness: Float = -1
            guard services.get(display.id, &brightness) == 0,
                  (0.0 ... 1.0).contains(brightness)
            else {
                log(
                    String(
                        format: "%@ 0x%08x brightness read failed",
                        display.name,
                        display.id
                    )
                )
                return nil
            }
            return DisplayTarget(
                id: display.id,
                name: display.name,
                brightness: brightness
            )
        }
    }

    private func onlineDisplays() -> [(id: CGDirectDisplayID, name: String)] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return []
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }

        var namesByID: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                continue
            }
            namesByID[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }

        return ids.map { id in
            (id, namesByID[id] ?? "Unknown display")
        }
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("\(timestamp) \(message)\n".utf8))
    }
}

private func errorText() -> String {
    guard let error = dlerror() else {
        return "unknown dynamic-loader error"
    }
    return String(cString: error)
}

private func run() throws {
    let arguments = Set(CommandLine.arguments.dropFirst())
    if arguments.contains("--self-test") {
        runSelfTest()
        return
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let keeper = BrightnessKeeper(services: try DisplayServices())
    if arguments.contains("--list") {
        keeper.listDisplays()
        return
    }
    if arguments.contains("--once") {
        let count = keeper.repairNow(reason: "manual")
        if count == 0 {
            exit(EXIT_FAILURE)
        }
        return
    }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
        forName: NSWorkspace.screensDidWakeNotification,
        object: nil,
        queue: .main
    ) { _ in
        keeper.scheduleRepair(reason: "screens woke")
    }
    workspaceCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
    ) { _ in
        keeper.scheduleRepair(reason: "Mac woke")
    }

    DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("com.apple.screenIsUnlocked"),
        object: nil,
        queue: .main
    ) { _ in
        keeper.scheduleRepair(reason: "screen unlocked")
    }

    FileHandle.standardError.write(
        Data("LG UltraFine Brightness Keeper is watching for wake/unlock\n".utf8)
    )
    RunLoop.main.run()
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
