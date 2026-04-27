import SwiftUI

struct CatalogModelDetailView: View {
    let model: CatalogModel
    let catalogClient: HuggingFaceCatalogClient
    @ObservedObject var downloader: HuggingFaceDownloader
    @ObservedObject var modelStore: ModelStore
    let onStartChat: (ModelRecord) -> Void

    @State private var details: CatalogModel
    @State private var isLoadingDetails = false
    @State private var downloadingFilename: String?
    @State private var downloadedModel: ModelRecord?
    @State private var errorMessage: String?

    init(
        model: CatalogModel,
        catalogClient: HuggingFaceCatalogClient,
        downloader: HuggingFaceDownloader,
        modelStore: ModelStore,
        onStartChat: @escaping (ModelRecord) -> Void
    ) {
        self.model = model
        self.catalogClient = catalogClient
        self.downloader = downloader
        self.modelStore = modelStore
        self.onStartChat = onStartChat
        _details = State(initialValue: model)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Repository", value: details.id)
                if let parameterSize = details.parameterSize {
                    LabeledContent("Size", value: parameterSize)
                }
                if let downloads = details.downloads {
                    LabeledContent("Downloads", value: downloads.formatted())
                }
                if let likes = details.likes {
                    LabeledContent("Likes", value: likes.formatted())
                }
                if let lastModified = details.lastModified {
                    LabeledContent("Updated") {
                        Text(lastModified, style: .date)
                    }
                }
            }

            Section("Files") {
                if isLoadingDetails {
                    ProgressView()
                } else if details.files.isEmpty {
                    ContentUnavailableView("No GGUF Files", systemImage: "doc.badge.ellipsis")
                } else {
                    ForEach(details.files) { file in
                        CatalogFileRow(
                            file: file,
                            isDownloading: downloadingFilename == file.filename
                        ) {
                            Task { await download(file) }
                        }
                        .disabled(downloadingFilename != nil)
                    }
                }
            }
        }
        .navigationTitle(details.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetailsIfNeeded()
        }
        .alert("Download Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Model Downloaded", isPresented: downloadedBinding) {
            Button("Start Chat") {
                if let downloadedModel {
                    onStartChat(downloadedModel)
                }
                self.downloadedModel = nil
            }
            Button("OK", role: .cancel) {
                downloadedModel = nil
            }
        } message: {
            Text(downloadedModel?.displayName ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var downloadedBinding: Binding<Bool> {
        Binding(
            get: { downloadedModel != nil },
            set: { if !$0 { downloadedModel = nil } }
        )
    }

    private func loadDetailsIfNeeded() async {
        guard details.files.isEmpty else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            details = try await catalogClient.modelDetails(repoId: model.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(_ file: CatalogModelFile) async {
        downloadingFilename = file.filename
        defer { downloadingFilename = nil }

        do {
            let fileURL = try await downloader.download(
                repoId: details.id,
                filePath: file.filename,
                destinationDirectory: modelStore.modelsDirectory
            )
            let metadata = ModelDownloadMetadata(
                repoId: details.id,
                filename: file.filename,
                parameterSize: details.parameterSize,
                quantization: file.quantization,
                downloadURL: file.downloadURL
            )
            downloadedModel = try modelStore.registerDownloadedModel(at: fileURL, metadata: metadata)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CatalogFileRow: View {
    let file: CatalogModelFile
    let isDownloading: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(file.filename)
                    .font(.body)
                    .lineLimit(3)

                HStack {
                    if let quantization = file.quantization {
                        Text(quantization)
                    }
                    if let sizeBytes = file.sizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloading {
                ProgressView()
            } else {
                Button {
                    onDownload()
                } label: {
                    Label("Download", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
