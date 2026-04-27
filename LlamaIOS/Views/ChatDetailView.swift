import SwiftUI

struct ChatDetailView: View {
    let session: ChatSession

    @ObservedObject var chatStore: ChatStore
    @ObservedObject var modelStore: ModelStore

    let engine: LlamaEngine
    @Binding var settings: GenerationSettings

    @State private var input = ""
    @State private var selectedModelID: UUID?
    @State private var generationTask: Task<Void, Never>?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            modelPicker
                .padding()
                .background(.bar)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty {
                            ContentUnavailableView(
                                modelStore.models.isEmpty ? "Install a Model" : "Start a Message",
                                systemImage: modelStore.models.isEmpty ? "externaldrive.badge.plus" : "text.bubble"
                            )
                                .padding(.top, 48)
                        } else {
                            ForEach(session.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            composer
                .padding()
                .background(.bar)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedModelID = session.modelId ?? modelStore.models.first?.id
        }
        .onChange(of: modelStore.models) { _, models in
            if let selectedModelID, models.contains(where: { $0.id == selectedModelID }) {
                return
            }
            self.selectedModelID = session.modelId ?? models.first?.id
        }
        .onDisappear {
            stopGeneration()
        }
        .alert("Generation Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var modelPicker: some View {
        HStack {
            Picker("Model", selection: $selectedModelID) {
                Text("No model").tag(Optional<UUID>.none)
                ForEach(modelStore.models) { model in
                    Text(model.displayName).tag(Optional(model.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedModelID) { _, modelId in
                chatStore.updateModel(sessionId: session.id, modelId: modelId)
            }

            Spacer()

            if isGenerating {
                ProgressView()
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(isGenerating)

            if isGenerating {
                Button {
                    stopGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    send()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedModel == nil)
            }
        }
    }

    private var selectedModel: ModelRecord? {
        modelStore.model(withID: selectedModelID)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let selectedModel else { return }

        input = ""
        isGenerating = true
        errorMessage = nil

        chatStore.updateModel(sessionId: session.id, modelId: selectedModel.id)
        modelStore.markUsed(modelId: selectedModel.id)
        chatStore.appendMessage(sessionId: session.id, role: .user, content: text)

        guard let promptSession = chatStore.sessions.first(where: { $0.id == session.id }),
              let assistantMessage = chatStore.appendMessage(sessionId: session.id, role: .assistant, content: "") else {
            isGenerating = false
            return
        }

        let prompt = chatStore.prompt(for: promptSession)

        generationTask = Task {
            do {
                try await engine.load(model: selectedModel, settings: settings)
                let stream = await engine.generate(prompt: prompt, settings: settings)

                for try await token in stream {
                    await MainActor.run {
                        chatStore.appendToMessage(sessionId: session.id, messageId: assistantMessage.id, chunk: token)
                    }
                }
            } catch is CancellationError {
                await engine.cancel()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    chatStore.appendToMessage(
                        sessionId: session.id,
                        messageId: assistantMessage.id,
                        chunk: "\n\n\(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                isGenerating = false
            }
        }
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        Task {
            await engine.cancel()
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            Text(message.content.isEmpty ? " " : message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    private var background: some ShapeStyle {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.16)
        case .assistant:
            Color.secondary.opacity(0.12)
        case .system:
            Color.orange.opacity(0.16)
        }
    }
}
