import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @ObservedObject var modelStore: ModelStore
    @ObservedObject var downloader: HuggingFaceDownloader

    let catalogClient: HuggingFaceCatalogClient
    let onStartChat: (ModelRecord) -> Void

    @State private var mode: ModelLibraryMode = .installed
    @State private var isShowingImporter = false
    @State private var isShowingDownloader = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sort: ModelCatalogSort = .downloads
    @State private var catalogResults: [CatalogModel] = []
    @State private var isSearching = false

    private let ggufType = UTType(filenameExtension: "gguf") ?? .data

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(ModelLibraryMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let progress = downloader.progress, let filename = downloader.activeFilename {
                    DownloadProgressSection(filename: filename, progress: progress)
                }

                switch mode {
                case .installed:
                    installedModels
                case .discover:
                    discoverModels
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
                        Label("Manual Download", systemImage: "link.badge.plus")
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
                ) { fileURL, metadata in
                    do {
                        let model = try modelStore.registerDownloadedModel(at: fileURL, metadata: metadata)
                        onStartChat(model)
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
            .task {
                guard mode == .discover, catalogResults.isEmpty else { return }
                await searchCatalog()
            }
            .onChange(of: mode) { _, mode in
                guard mode == .discover, catalogResults.isEmpty else { return }
                Task { await searchCatalog() }
            }
        }
    }

    private var installedModels: some View {
        Section("Installed") {
            if modelStore.models.isEmpty {
                ContentUnavailableView("No Models", systemImage: "externaldrive.badge.plus")
            } else {
                ForEach(modelStore.models) { model in
                    ModelRow(model: model) {
                        onStartChat(model)
                    }
                }
                .onDelete { offsets in
                    offsets
                        .map { modelStore.models[$0] }
                        .forEach(modelStore.deleteModel)
                }
            }
        }
    }

    private var discoverModels: some View {
        Group {
            Section("Discover") {
                TextField("Search public GGUF models", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await searchCatalog() }
                    }

                Picker("Sort", selection: $sort) {
                    ForEach(ModelCatalogSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }

                Button {
                    Task { await searchCatalog() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(isSearching)
            }

            Section("Results") {
                if isSearching {
                    ProgressView()
                } else if catalogResults.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                } else {
                    ForEach(catalogResults) { model in
                        NavigationLink {
                            CatalogModelDetailView(
                                model: model,
                                catalogClient: catalogClient,
                                downloader: downloader,
                                modelStore: modelStore,
                                onStartChat: onStartChat
                            )
                        } label: {
                            CatalogModelRow(model: model)
                        }
                    }
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func searchCatalog() async {
        isSearching = true
        defer { isSearching = false }

        do {
            catalogResults = try await catalogClient.searchModels(query: searchText, sort: sort)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ModelLibraryMode: String, CaseIterable, Identifiable {
    case installed
    case discover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .installed:
            "Installed"
        case .discover:
            "Discover"
        }
    }
}

private struct DownloadProgressSection: View {
    let filename: String
    let progress: Double

    var body: some View {
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
}

private struct ModelRow: View {
    let model: ModelRecord
    let onStartChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.displayName)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Button {
                    onStartChat()
                } label: {
                    Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label(model.source.label, systemImage: model.source == .downloaded ? "cloud" : "folder")
                if let quantization = model.quantization {
                    Text(quantization)
                }
                Spacer()
                Text(byteCount(model.sizeBytes))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let repoId = model.repoId {
                Text(repoId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CatalogModelRow: View {
    let model: CatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.displayName)
                .font(.headline)
                .lineLimit(2)

            Text(model.id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                if let parameterSize = model.parameterSize {
                    Label(parameterSize, systemImage: "cpu")
                }
                Label("\(model.files.count) GGUF", systemImage: "doc")
                Spacer()
                if let downloads = model.downloads {
                    Text(downloads.formatted())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
