import Foundation
import IOKit.ps

enum PowerState {
    /// True on desktop Macs and on laptops that are plugged in.
    static var isOnExternalPower: Bool {
        guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return true }
        return (source as String) == kIOPMACPowerKey
    }
}
