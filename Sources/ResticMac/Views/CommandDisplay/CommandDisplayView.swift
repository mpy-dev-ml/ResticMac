import SwiftUI

struct CommandDisplayView: View {
    @StateObject private var viewModel = CommandDisplayViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            commandHeader
            outputArea
            progressArea
        }
        .frame(width: 600, height: 400)
    }
    
    private var commandHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command")
                .font(.headline)
            
            Text(viewModel.command)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
        }
        .padding()
    }
    
    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            
            ScrollView {
                Text(viewModel.output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.1))
            .cornerRadius(4)
        }
        .padding()
    }
    
    private var progressArea: some View {
        VStack(spacing: 8) {
            if viewModel.isRunning {
                ProgressView(value: viewModel.progress) {
                    Text("Running...")
                }
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
            
            HStack {
                Spacer()
                
                Button(viewModel.isRunning ? "Close" : "Done") {
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
    }
}

struct CommandDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        CommandDisplayView()
    }
}