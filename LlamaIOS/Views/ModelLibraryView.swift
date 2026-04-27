import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @ObservedObject var modelStore: ModelStore
    @ObservedObject var downloader: HuggingFaceDownloader

    @State private var isShowingImporter = false
    @State private var isShowingDownloader = false
    @State private var errorMessage: String?

    private let ggufType = UTType(filenameExtension: "gguf") ?? .data

    var body: some View {
        NavigationStack {
            List {
                if let progress = downloader.progress, let filename = downloader.activeFilename {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(filename)
                                .font(.headline)
                            ProgressView(value: progress)
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    if modelStore.models.isEmpty {
                        ContentUnavailableView("No Models", systemImage: "externaldrive.badge.plus")
                    } else {
                        ForEach(modelStore.models) { model in
                            ModelRow(model: model)
                        }
                        .onDelete { offsets in
                            offsets
                                .map { modelStore.models[$0] }
                                .forEach(modelStore.deleteModel)
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingImporter = true
                    } label: {
                        Label("Import", systemImage: "doc.badge.plus")
                    }

                    Button {
                        isShowingDownloader = true
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [ggufType],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    try modelStore.importModel(from: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $isShowingDownloader) {
                HuggingFaceDownloadView(
                    downloader: downloader,
                    destinationDirectory: modelStore.modelsDirectory
                ) { fileURL in
                    do {
                        try modelStore.registerDownloadedModel(at: fileURL)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Model Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct ModelRow: View {
    let model: ModelRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.displayName)
                .font(.headline)
                .lineLimit(2)

            HStack {
                Label(model.source.label, systemImage: model.source == .downloaded ? "cloud" : "folder")
                Spacer()
                Text(byteCount(model.sizeBytes))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

