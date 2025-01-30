import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .repository
    @State private var showWelcomeSheet = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    @StateObject private var commandDisplay = CommandDisplayViewModel()
    @StateObject private var resticService: ResticService
    
    init() {
        let executor = ProcessExecutor()
        _resticService = StateObject(wrappedValue: ResticService(executor: executor))
    }
    
    enum Tab: String, CaseIterable, Identifiable {
        case repository
        case backup
        case schedule
        case scan
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .repository: return "Repository"
            case .backup: return "Backup"
            case .schedule: return "Schedule"
            case .scan: return "Scanner"
            }
        }
        
        var icon: String {
            switch self {
            case .repository: return "folder.fill"
            case .backup: return "arrow.clockwise"
            case .schedule: return "calendar"
            case .scan: return "magnifyingglass"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
        } detail: {
            TabView(selection: $selectedTab) {
                RepositoryView(resticService: resticService, commandDisplay: commandDisplay)
                    .tag(Tab.repository)
                
                BackupView(resticService: resticService)
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
        .task {
            Task {
                await resticService.setCommandDisplay(commandDisplay)
            }
        }
    }
}

struct Sidebar: View {
    @Binding var selection: ContentView.Tab
    
    var body: some View {
        List(selection: $selection) {
            ForEach(ContentView.Tab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
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
