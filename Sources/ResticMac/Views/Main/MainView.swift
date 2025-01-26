import SwiftUI

struct MainView: View {
    @State private var isShowingCommandDisplay = false
    
    var body: some View {
        ContentView()
            .sheet(isPresented: $isShowingCommandDisplay) {
                // We'll implement CommandDisplayView later
                Text("Command Display")
                    .frame(width: 600, height: 400)
            }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}