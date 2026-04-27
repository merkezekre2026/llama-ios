import Foundation

@MainActor
final class AppState: ObservableObject {
    let modelStore: ModelStore
    let chatStore: ChatStore
    let settingsStore: SettingsStore
    let downloader: HuggingFaceDownloader
    let catalogClient: HuggingFaceCatalogClient
    let engine: LlamaEngine

    @Published var settings: GenerationSettings {
        didSet {
            try? settingsStore.save(settings)
        }
    }
    @Published var startupError: String?

    init(
        modelStore: ModelStore = ModelStore(),
        chatStore: ChatStore = ChatStore(),
        settingsStore: SettingsStore = SettingsStore(),
        downloader: HuggingFaceDownloader = HuggingFaceDownloader(),
        catalogClient: HuggingFaceCatalogClient = HuggingFaceCatalogClient(),
        engine: LlamaEngine = LlamaEngine(),
        settings: GenerationSettings = .default
    ) {
        self.modelStore = modelStore
        self.chatStore = chatStore
        self.settingsStore = settingsStore
        self.downloader = downloader
        self.catalogClient = catalogClient
        self.engine = engine
        self.settings = settings
    }

    func bootstrap() {
        do {
            try modelStore.load()
            try chatStore.load()
            settings = try settingsStore.load()
        } catch {
            startupError = error.localizedDescription
        }
    }
}
