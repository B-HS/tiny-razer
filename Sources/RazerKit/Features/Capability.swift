import Foundation

/// Declarative list of what a Razer device can do. Used by `DeviceDescriptor`
/// to drive the UI and the available command surface.
public enum Capability: String, Sendable, Hashable, CaseIterable {
    case dpi
    case dpiHyper              // DPI command but using set_dpi_xy_byte path (older)
    case pollingRate           // classic (1000/500/125)
    case pollingRateHyper      // set_polling_rate2 (up to 8000 Hz)
    case battery
    case charging
    case brightness
    case rgbStatic
    case rgbBreathe
    case rgbSpectrum
    case rgbWave
    case rgbReactive
    case rgbStarlight
    case customFrame
}
