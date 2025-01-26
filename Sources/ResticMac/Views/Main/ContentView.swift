import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .repository
    @State private var showWelcomeSheet = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    @State private var resticService = ResticService()
    
    enum Tab {
        case repository
        case backup
        case schedule
        case scan
    }
    
    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
        } detail: {
            TabView(selection: $selectedTab) {
                RepositoryView()
                    .tag(Tab.repository)
                
                ComingSoonView(title: "Backup", message: "Backup functionality coming soon")
                    .tag(Tab.backup)
                
                ComingSoonView(title: "Schedule", message: "Scheduling functionality coming soon")
                    .tag(Tab.schedule)
                
                ScanView(resticService: resticService)
                    .tag(Tab.scan)
            }
        }
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeView(isPresented: $showWelcomeSheet, selectedTab: $selectedTab)
        }
        .onChange(of: showWelcomeSheet) { oldValue, newValue in
            if !newValue {
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            }
        }
    }
}

struct Sidebar: View {
    @Binding var selection: ContentView.Tab
    
    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: ContentView.Tab.repository) {
                Label("Repository", systemImage: "folder.fill")
            }
            
            NavigationLink(value: ContentView.Tab.backup) {
                Label("Backup", systemImage: "arrow.clockwise")
            }
            
            NavigationLink(value: ContentView.Tab.schedule) {
                Label("Schedule", systemImage: "calendar")
            }
            
            NavigationLink(value: ContentView.Tab.scan) {
                Label("Scanner", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("ResticMac")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ComingSoonView: View {
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title)
            
            Text(message)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct WelcomeView: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: ContentView.Tab
    @State private var showDirectoryPicker = false
    @State private var selectedPath: URL?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to ResticMac")
                    .font(.title)
                    .bold()
                
                Text("Let's get started by either adding an existing repository or searching for one on your computer.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 16) {
                    Button {
                        selectedTab = .repository
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Repository")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button {
                        selectedTab = .scan
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass.circle.fill")
                            Text("Search for Repositories")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top)
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Skip") {
                        isPresented = false
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}