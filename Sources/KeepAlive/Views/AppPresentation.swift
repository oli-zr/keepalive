import SwiftUI

/// How an app's state is described in the menu and in Settings.
struct AppStatus {
    enum Tone { case normal, warning, failure }

    let text: String
    let tone: Tone

    init(app: ManagedApp, activity: Activity, now: Date = .now) {
        switch activity {
        case .waiting:
            self.init(String(localized: "Waiting…"))
            return
        case .preparing:
            self.init(String(localized: "Looking for iPhone…"))
            return
        case .building:
            self.init(String(localized: "Building…"))
            return
        case .installing:
            self.init(String(localized: "Installing…"))
            return
        case .idle:
            break
        }

        let expiration = app.expirationDate
        if let expiration, expiration <= now {
            self.init(String(localized: "Expired"), tone: .failure)
        } else if let error = app.lastError, app.isEnabled {
            self.init(error, tone: .failure)
        } else if !app.isEnabled {
            self.init(String(localized: "Paused"))
        } else if let expiration {
            let relative = expiration.formatted(.relative(presentation: .named))
            let soon = expiration.timeIntervalSince(now) < Renewer.urgentInterval
            self.init(String(localized: "Expires \(relative)"), tone: soon ? .warning : .normal)
        } else {
            self.init(String(localized: "Not installed yet"))
        }
    }

    private init(_ text: String, tone: Tone = .normal) {
        self.text = text
        self.tone = tone
    }

    var style: AnyShapeStyle {
        switch tone {
        case .normal: AnyShapeStyle(.secondary)
        case .warning: AnyShapeStyle(.orange)
        case .failure: AnyShapeStyle(.red)
        }
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
    var connectionDescription: String {
        guard isReachable else { return String(localized: "Not reachable") }
        switch transport {
        case .network: return String(localized: "Connected via Wi‑Fi")
        case .wired: return String(localized: "Connected via cable")
        case .unknown: return String(localized: "Not reachable")
        }
    }
}
