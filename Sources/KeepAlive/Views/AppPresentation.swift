import SwiftUI

/// How an app's state is described in the menu and in Settings.
struct AppStatus {
    enum Tone { case normal, warning, failure }

    let text: String
    let tone: Tone
    /// One line per device when the app is installed on several, for tooltips.
    let details: String

    /// The app as a whole: what is happening now, or the state of the device that needs
    /// attention first.
    init(app: ManagedApp, targets: [SavedDevice], activity: Activity, now: Date = .now) {
        switch activity {
        case .waiting:
            self.init(String(localized: "Waiting…"))
            return
        case .preparing:
            self.init(targets.count == 1
                      ? String(localized: "Looking for \(targets[0].name)…")
                      : String(localized: "Looking for devices…"))
            return
        case .building:
            self.init(String(localized: "Building…"))
            return
        case .installing(let device):
            self.init(targets.count > 1 ? String(localized: "Installing on \(device)…") : String(localized: "Installing…"))
            return
        case .idle:
            break
        }

        guard !targets.isEmpty else {
            if !app.isEnabled {
                self.init(String(localized: "Paused"))
            } else if app.excludedDevices.isEmpty {
                self.init(String(localized: "No device selected"), tone: .failure)
            } else {
                self.init(String(localized: "No device turned on"), tone: .failure)
            }
            return
        }
        let devices = targets.map { device in
            (device: device, state: State(installation: app.installation(on: device.id), isEnabled: app.isEnabled, now: now))
        }
        if devices.count == 1 {
            self.init(state: devices[0].state, now: now)
            return
        }

        let details = devices.map { device, state in
            let text = Self(state: state, now: now).text
            // Errors already name their device when there are several.
            if case .failed = state { return text }
            return String(localized: "\(device.name): \(text)")
        }.joined(separator: "\n")
        let first = devices.min { $0.state.precedes($1.state, now: now) }!
        let summary = Self(state: first.state, now: now)
        // Name the device unless every device is in the same state.
        let isShared = devices.allSatisfy { Self(state: $0.state, now: now).text == summary.text }
        let name = first.device.name
        switch first.state {
        case .expired where !isShared:
            self.init(String(localized: "Expired on \(name)"), tone: summary.tone, details: details)
        case .notInstalled where !isShared:
            self.init(String(localized: "Not installed on \(name) yet"), tone: summary.tone, details: details)
        case .expires(let date) where !isShared && summary.tone == .warning:
            self.init(String(localized: "\(name): expires \(Self.relative(date, now: now))"), tone: summary.tone, details: details)
        default:
            self.init(summary.text, tone: summary.tone, details: details)
        }
    }

    /// The app on one device.
    init(installation: Installation, isEnabled: Bool, now: Date = .now) {
        self.init(state: State(installation: installation, isEnabled: isEnabled, now: now), now: now)
    }

    private init(state: State, now: Date) {
        switch state {
        case .expired:
            self.init(String(localized: "Expired"), tone: .failure)
        case .failed(let error):
            self.init(error, tone: .failure)
        case .paused:
            self.init(String(localized: "Paused"))
        case .expires(let date):
            let soon = date.timeIntervalSince(now) < Renewer.urgentInterval
            self.init(String(localized: "Expires \(Self.relative(date, now: now))"), tone: soon ? .warning : .normal)
        case .notInstalled:
            self.init(String(localized: "Not installed yet"))
        }
    }

    private init(_ text: String, tone: Tone = .normal, details: String? = nil) {
        self.text = text
        self.tone = tone
        self.details = details ?? text
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.locale = .interface
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The state of the app on one device.
    private enum State {
        case expired
        case failed(String)
        case expires(Date)
        case notInstalled
        case paused

        init(installation: Installation, isEnabled: Bool, now: Date) {
            if let expiration = installation.expirationDate, expiration <= now {
                self = .expired
            } else if let error = installation.lastError, isEnabled {
                self = .failed(error)
            } else if !isEnabled {
                self = .paused
            } else if let expiration = installation.expirationDate {
                self = .expires(expiration)
            } else {
                self = .notInstalled
            }
        }

        /// Whether this state needs attention before the other one.
        func precedes(_ other: State, now: Date) -> Bool {
            if case .expires(let date) = self, case .expires(let otherDate) = other { return date < otherDate }
            return rank(now: now) < other.rank(now: now)
        }

        private func rank(now: Date) -> Int {
            switch self {
            case .expired: 0
            case .failed: 1
            case .expires(let date) where date.timeIntervalSince(now) < Renewer.urgentInterval: 2
            case .notInstalled: 3
            case .expires: 4
            case .paused: 5
            }
        }
    }

    var style: AnyShapeStyle {
        switch tone {
        case .normal: AnyShapeStyle(.secondary)
        case .warning: AnyShapeStyle(.orange)
        case .failure: AnyShapeStyle(.red)
        }
    }
}

extension AppStore {
    func status(for app: ManagedApp) -> AppStatus {
        AppStatus(app: app, targets: targets(for: app), activity: activity(for: app))
    }
}

extension Locale {
    /// The language of the interface, so dates and lists match the surrounding text
    /// rather than only the region's format settings.
    static var interface: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

/// The project's own app icon, or a neutral placeholder in the same shape.
struct AppIconView: View {
    let app: ManagedApp
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let image = IconLocator.cachedIcon(for: app) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                shape
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app.dashed")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .saturation(app.isEnabled ? 1 : 0)
        .opacity(app.isEnabled ? 1 : 0.6)
    }
}

extension Device {
    var symbolName: String { isPad ? "ipad" : "iphone" }

    var connectionDescription: String {
        guard isReachable else { return String(localized: "Not reachable") }
        switch transport {
        case .network: return String(localized: "Connected via Wi‑Fi")
        case .wired: return String(localized: "Connected via cable")
        case .unknown: return String(localized: "Not reachable")
        }
    }
}

extension SavedDevice {
    var symbolName: String { isPad ? "ipad" : "iphone" }
}
