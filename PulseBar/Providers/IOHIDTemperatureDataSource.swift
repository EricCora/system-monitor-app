import Foundation
import Darwin

public struct IOHIDTemperatureDataSource: TemperatureDataSource {
    private let minimumValidCelsius: Double
    private let maximumValidCelsius: Double

    public init(
        minimumValidCelsius: Double = 0,
        maximumValidCelsius: Double = 125
    ) {
        self.minimumValidCelsius = minimumValidCelsius
        self.maximumValidCelsius = maximumValidCelsius
    }

    public func readTemperatures() async throws -> PowermetricsTemperatureReading {
        let api = try IOHIDSymbolLoader.api.get()

        guard let client = api.createClient(kCFAllocatorDefault) else {
            throw ProviderError.unavailable("Failed to create IOHID event system client")
        }
        defer {
            Unmanaged<AnyObject>.fromOpaque(client).release()
        }

        let matching: [String: Any] = [
            "PrimaryUsagePage": Int(kIOHIDVendorUsagePage),
            "PrimaryUsage": Int(kIOHIDTemperatureUsage)
        ]
        api.setMatching(client, matching as CFDictionary)

        guard let services = api.copyServices(client)?.takeRetainedValue() else {
            throw ProviderError.unavailable("IOHID temperature services unavailable")
        }

        var sensors: [HIDSensorTemperature] = []
        sensors.reserveCapacity(32)

        let serviceCount = CFArrayGetCount(services)
        for index in 0..<serviceCount {
            guard let unmanaged = CFArrayGetValueAtIndex(services, index) else {
                continue
            }
            let service = UnsafeMutableRawPointer(mutating: unmanaged)

            let name = readServiceName(service: service, api: api)
            guard includeSensor(named: name) else {
                continue
            }

            guard let event = api.copyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else {
                continue
            }
            defer {
                Unmanaged<AnyObject>.fromOpaque(event).release()
            }

            let rawValue = api.getFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            guard rawValue.isFinite,
                  rawValue >= minimumValidCelsius,
                  rawValue <= maximumValidCelsius else {
                continue
            }

            sensors.append(HIDSensorTemperature(name: name, celsius: rawValue))
        }

        guard !sensors.isEmpty else {
            throw ProviderError.parsingFailed("No valid Celsius temperatures found in IOHID sensor output")
        }

        let primary = preferredPrimarySensor(from: sensors)?.celsius ?? sensors[0].celsius
        let maximum = sensors.map(\.celsius).max() ?? primary

        return PowermetricsTemperatureReading(
            primaryCelsius: primary,
            maxCelsius: maximum,
            sensorCount: sensors.count,
            source: "iohid"
        )
    }

    private func readServiceName(service: UnsafeMutableRawPointer, api: IOHIDDynamicAPI) -> String {
        guard let property = api.copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
              let string = property as? String,
              !string.isEmpty else {
            return "unknown"
        }
        return string
    }

    private func includeSensor(named name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("gas gauge") {
            return false
        }
        if lower.contains("battery") {
            return false
        }
        return true
    }

    private func preferredPrimarySensor(from sensors: [HIDSensorTemperature]) -> HIDSensorTemperature? {
        sensors.min { lhs, rhs in
            let left = primaryPriority(for: lhs.name)
            let right = primaryPriority(for: rhs.name)
            if left != right {
                return left < right
            }
            return lhs.celsius > rhs.celsius
        }
    }

    private func primaryPriority(for name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("pmgr soc die") {
            return 0
        }
        if lower.contains("soc mtr") {
            return 1
        }
        if lower.contains("tdie") {
            return 2
        }
        if lower.contains("gpu mtr") {
            return 3
        }
        if lower.contains("ane") {
            return 4
        }
        if lower.contains("nand") {
            return 5
        }
        return 10
    }
}

private struct HIDSensorTemperature: Sendable {
    let name: String
    let celsius: Double
}

private enum IOHIDSymbolLoader {
    static let api: Result<IOHIDDynamicAPI, ProviderError> = {
        do {
            return .success(try IOHIDDynamicAPI.load())
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.unavailable("Failed to initialize IOHID symbols: \(error.localizedDescription)"))
        }
    }()
}

private struct IOHIDDynamicAPI {
    typealias CreateClientFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?) -> Void
    typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer?) -> Unmanaged<CFArray>?
    typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer?, CFString) -> Unmanaged<CFTypeRef>?
    typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer?, Int64, Int64, Int32) -> UnsafeMutableRawPointer?
    typealias GetFloatValueFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Double

    let createClient: CreateClientFn
    let setMatching: SetMatchingFn
    let copyServices: CopyServicesFn
    let copyProperty: CopyPropertyFn
    let copyEvent: CopyEventFn
    let getFloatValue: GetFloatValueFn

    static func load() throws -> IOHIDDynamicAPI {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            throw ProviderError.unavailable("Unable to load IOKit for IOHID temperature sensors")
        }

        guard
            let createClient: CreateClientFn = symbol(handle: handle, named: "IOHIDEventSystemClientCreate"),
            let setMatching: SetMatchingFn = symbol(handle: handle, named: "IOHIDEventSystemClientSetMatching"),
            let copyServices: CopyServicesFn = symbol(handle: handle, named: "IOHIDEventSystemClientCopyServices"),
            let copyProperty: CopyPropertyFn = symbol(handle: handle, named: "IOHIDServiceClientCopyProperty"),
            let copyEvent: CopyEventFn = symbol(handle: handle, named: "IOHIDServiceClientCopyEvent"),
            let getFloatValue: GetFloatValueFn = symbol(handle: handle, named: "IOHIDEventGetFloatValue")
        else {
            throw ProviderError.unavailable("Required IOHID temperature symbols are unavailable on this macOS build")
        }

        // Keep the image loaded for process lifetime; unloading would invalidate function pointers.
        _ = handle

        return IOHIDDynamicAPI(
            createClient: createClient,
            setMatching: setMatching,
            copyServices: copyServices,
            copyProperty: copyProperty,
            copyEvent: copyEvent,
            getFloatValue: getFloatValue
        )
    }

    private static func symbol<T>(handle: UnsafeMutableRawPointer, named name: String) -> T? {
        guard let rawSymbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(rawSymbol, to: T.self)
    }
}

private let kIOHIDVendorUsagePage: Int32 = 0xFF00
private let kIOHIDTemperatureUsage: Int32 = 5
private let kIOHIDEventTypeTemperature: Int64 = 0x0F
private let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(kIOHIDEventTypeTemperature << 16)
