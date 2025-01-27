import SwiftUI

struct CommandDisplayView: View {
    @ObservedObject var viewModel: CommandDisplayViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Command Output")
                .font(.headline)
            
            ScrollView {
                Text(viewModel.output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            
            if viewModel.isRunning {
                ProgressView(value: viewModel.progress) {
                    Text("Running...")
                }
            }
            
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 600, height: 400)
        .onAppear {
            viewModel.start()
        }
    }
}

struct CommandDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        CommandDisplayView(viewModel: CommandDisplayViewModel())
    }
}