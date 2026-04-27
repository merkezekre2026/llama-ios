import SwiftUI

struct HuggingFaceDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var downloader: HuggingFaceDownloader

    let destinationDirectory: URL
    let onDownloaded: (URL) -> Void

    @State private var repoId = ""
    @State private var filename = ""
    @State private var errorMessage: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Hugging Face") {
                    TextField("owner/model-name", text: $repoId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("model.Q4_K_M.gguf", text: $filename)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let progress = downloader.progress {
                    Section {
                        ProgressView(value: progress)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Download Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        downloadTask?.cancel()
                        downloader.cancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        startDownload()
                    }
                    .disabled(isDownloading)
                }
            }
        }
    }

    private var isDownloading: Bool {
        downloader.progress != nil
    }

    private func startDownload() {
        errorMessage = nil
        downloadTask = Task {
            do {
                let fileURL = try await downloader.download(
                    repoId: repoId,
                    filename: filename,
                    destinationDirectory: destinationDirectory
                )
                onDownloaded(fileURL)
                dismiss()
            } catch is CancellationError {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

