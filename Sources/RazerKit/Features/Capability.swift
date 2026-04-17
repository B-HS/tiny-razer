import Foundation

/// Declarative list of what a Razer device can do. Used by `DeviceDescriptor`
/// to drive the UI and the available command surface.
public enum Capability: String, Sendable, Hashable, CaseIterable {
    case dpi
    case dpiHyper              // DPI command but using set_dpi_xy_byte path (older)
    case dpiStages             // stored stage array with active-stage cycle
    case pollingRate           // classic (1000/500/125)
    case pollingRateHyper      // set_polling_rate2 (up to 8000 Hz)
    case battery
    case charging
    case idleTimer             // wireless auto-sleep delay
    case lowBatteryThreshold   // configurable low-battery warning %
    case brightness
    case rgbStatic
    case rgbBreathe
    case rgbSpectrum
    case rgbWave
    case rgbReactive
    case rgbStarlight
    case customFrame           // per-key matrix frame (Hard tier)
    case extendedEffects       // uses the class 0x0F extended command path

    /// True for modern devices that route LED effects through the extended
    /// (class 0x0F) command family instead of the classic 0x03 path.
    public var isExtended: Bool { self == .extendedEffects }
}
