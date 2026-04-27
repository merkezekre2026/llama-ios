import Foundation

@MainActor
final class AppState: ObservableObject {
    let modelStore: ModelStore
    let chatStore: ChatStore
    let downloader: HuggingFaceDownloader
    let engine: LlamaEngine

    @Published var settings: GenerationSettings
    @Published var startupError: String?

    init(
        modelStore: ModelStore = ModelStore(),
        chatStore: ChatStore = ChatStore(),
        downloader: HuggingFaceDownloader = HuggingFaceDownloader(),
        engine: LlamaEngine = LlamaEngine(),
        settings: GenerationSettings = .default
    ) {
        self.modelStore = modelStore
        self.chatStore = chatStore
        self.downloader = downloader
        self.engine = engine
        self.settings = settings
    }

    func bootstrap() {
        do {
            try modelStore.load()
            try chatStore.load()
        } catch {
            startupError = error.localizedDescription
        }
    }
}

