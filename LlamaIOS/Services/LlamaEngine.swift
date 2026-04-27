import Foundation
import LlamaSwift

enum LlamaEngineError: LocalizedError {
    case failedToLoadModel
    case failedToCreateContext
    case failedToDecode
    case noLoadedModel
    case contextTooSmall

    var errorDescription: String? {
        switch self {
        case .failedToLoadModel:
            "The model could not be loaded."
        case .failedToCreateContext:
            "A llama.cpp context could not be created."
        case .failedToDecode:
            "llama.cpp failed while decoding tokens."
        case .noLoadedModel:
            "Load a model before starting generation."
        case .contextTooSmall:
            "The prompt plus requested output does not fit in the configured context window."
        }
    }
}

actor LlamaEngine {
    private var loadedModelID: UUID?
    private var loadedSettings: GenerationSettings?
    private var context: LlamaContextBox?
    private var isCancelled = false

    func load(model: ModelRecord, settings: GenerationSettings) throws {
        if loadedModelID == model.id, loadedSettings == settings, context != nil {
            return
        }

        unload()
        context = try LlamaContextBox(modelPath: model.localPath, settings: settings)
        loadedModelID = model.id
        loadedSettings = settings
    }

    func unload() {
        context = nil
        loadedModelID = nil
        loadedSettings = nil
        isCancelled = false
    }

    func cancel() {
        isCancelled = true
    }

    func generate(prompt: String, settings: GenerationSettings) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(prompt: prompt, settings: settings, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await self.cancel()
                }
            }
        }
    }

    private func run(
        prompt: String,
        settings: GenerationSettings,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) throws {
        guard let context else {
            throw LlamaEngineError.noLoadedModel
        }

        isCancelled = false
        try context.prepare(prompt: prompt, maxTokens: settings.maxTokens)

        while !isCancelled, !Task.isCancelled, !context.isDone {
            let token = try context.nextToken()
            if !token.isEmpty {
                continuation.yield(token)
            }
        }

        continuation.finish()
    }
}

private final class LlamaContextBox {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private var sampler: OpaquePointer
    private var batch: llama_batch
    private var temporaryInvalidBytes: [CChar] = []
    private var currentPosition: Int32 = 0
    private var targetLength: Int32 = 0

    private(set) var isDone = false

    init(modelPath: String, settings: GenerationSettings) throws {
        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(settings.gpuLayers)

        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif

        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            llama_backend_free()
            throw LlamaEngineError.failedToLoadModel
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(settings.contextLength)
        contextParams.n_threads = Int32(settings.threads)
        contextParams.n_threads_batch = Int32(settings.threads)

        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            llama_backend_free()
            throw LlamaEngineError.failedToCreateContext
        }

        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.batch = llama_batch_init(512, 0, 1)

        let samplerParams = llama_sampler_chain_default_params()
        self.sampler = llama_sampler_chain_init(samplerParams)
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(Float(settings.temperature)))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(settings.seed)))
    }

    deinit {
        llama_sampler_free(sampler)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    func prepare(prompt: String, maxTokens: Int) throws {
        isDone = false
        temporaryInvalidBytes.removeAll()
        llama_sampler_reset(sampler)
        llama_memory_clear(llama_get_memory(context), true)

        let tokens = tokenize(prompt: prompt, addBOS: true)
        let nContext = Int(llama_n_ctx(context))
        let requestedTokens = tokens.count + maxTokens

        guard requestedTokens <= nContext else {
            throw LlamaEngineError.contextTooSmall
        }

        clearBatch()
        for (index, token) in tokens.enumerated() {
            addToBatch(token, position: Int32(index), logits: index == tokens.count - 1)
        }

        guard llama_decode(context, batch) == 0 else {
            throw LlamaEngineError.failedToDecode
        }

        currentPosition = Int32(tokens.count)
        targetLength = Int32(requestedTokens)
    }

    func nextToken() throws -> String {
        let nextToken = llama_sampler_sample(sampler, context, batch.n_tokens - 1)

        if llama_vocab_is_eog(vocab, nextToken) || currentPosition >= targetLength {
            isDone = true
            let tail = String(validatingUTF8: temporaryInvalidBytes + [0]) ?? ""
            temporaryInvalidBytes.removeAll()
            return tail
        }

        let bytes = tokenToPiece(nextToken)
        temporaryInvalidBytes.append(contentsOf: bytes)

        let tokenString: String
        if let string = String(validatingUTF8: temporaryInvalidBytes + [0]) {
            temporaryInvalidBytes.removeAll()
            tokenString = string
        } else {
            tokenString = ""
        }

        clearBatch()
        addToBatch(nextToken, position: currentPosition, logits: true)
        currentPosition += 1

        guard llama_decode(context, batch) == 0 else {
            throw LlamaEngineError.failedToDecode
        }

        return tokenString
    }

    private func tokenize(prompt: String, addBOS: Bool) -> [llama_token] {
        let utf8Count = prompt.utf8.count
        let tokenCapacity = utf8Count + (addBOS ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: tokenCapacity)
        defer { tokens.deallocate() }

        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(utf8Count),
            tokens,
            Int32(tokenCapacity),
            addBOS,
            true
        )

        guard tokenCount > 0 else { return [] }
        return (0..<Int(tokenCount)).map { tokens[$0] }
    }

    private func tokenToPiece(_ token: llama_token) -> [CChar] {
        var scratch = [CChar](repeating: 0, count: 16)
        let length = llama_token_to_piece(vocab, token, &scratch, Int32(scratch.count), 0, false)

        if length >= 0 {
            return Array(scratch.prefix(Int(length)))
        }

        var buffer = [CChar](repeating: 0, count: Int(-length))
        let resizedLength = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        return Array(buffer.prefix(max(0, Int(resizedLength))))
    }

    private func clearBatch() {
        batch.n_tokens = 0
    }

    private func addToBatch(_ token: llama_token, position: llama_pos, logits: Bool) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = position
        batch.n_seq_id[index] = 1
        batch.seq_id[index]![0] = 0
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}
