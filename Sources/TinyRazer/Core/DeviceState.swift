import Foundation
import RazerKit

/// View-level snapshot of a live Razer device: descriptor + whatever runtime
/// state we've been able to read from the hardware.
struct DeviceState: Identifiable, Equatable {
    let device: RazerDevice

    var batteryPercent: Int?
    var isCharging: Bool?
    var dpiX: UInt16?
    var dpiY: UInt16?
    var pollingRate: PollingRate?
    var brightness: UInt8?
    var firmwareVersion: String?
    var serialNumber: String?
    var dpiStages: MiscCommands.DPIStageList?
    var idleTimeSeconds: UInt16?
    var lowBatteryThresholdPercent: Int?
    var lastError: String?

    var id: UInt64 { device.id }
    var displayName: String { device.descriptor.displayName }
    var shortName: String { device.descriptor.shortName }

    init(device: RazerDevice) {
        self.device = device
    }
}
