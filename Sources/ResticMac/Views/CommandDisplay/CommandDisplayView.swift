import SwiftUI

struct CommandDisplayView: View {
    @ObservedObject var viewModel: CommandDisplayViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Command Output")
                    .font(.headline)
                Spacer()
                if !viewModel.isRunning {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .padding()
            
            if viewModel.isRunning {
                ProgressView(value: viewModel.progress, total: 100)
                    .padding(.horizontal)
            }
            
            OutputList(output: viewModel.output)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct OutputList: View {
    let output: [CommandDisplayViewModel.OutputLine]
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(output) { line in
                    Text(line.text)
                        .foregroundColor(line.type == .error ? .red : .primary)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

struct CommandDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        CommandDisplayView(viewModel: CommandDisplayViewModel())
    }
}