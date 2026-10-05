import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppsSettingsView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            DeviceSettingsView()
                .tabItem { Label("Device", systemImage: "iphone") }
            LogView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 560)
    }
}
