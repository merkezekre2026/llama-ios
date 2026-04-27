import SwiftUI

struct SettingsView: View {
    @Binding var settings: GenerationSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Sampling") {
                    LabeledContent("Temperature") {
                        Text(settings.temperature, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    Slider(value: $settings.temperature, in: 0...2, step: 0.05)

                    Stepper("Max tokens: \(settings.maxTokens)", value: $settings.maxTokens, in: 32...4096, step: 32)
                    Stepper("Seed: \(settings.seed)", value: $settings.seed, in: 0...Int(Int32.max), step: 1)
                }

                Section("Runtime") {
                    Stepper("Context: \(settings.contextLength)", value: $settings.contextLength, in: 512...8192, step: 256)
                    Stepper("Threads: \(settings.threads)", value: $settings.threads, in: 1...12, step: 1)
                    Stepper("GPU layers: \(settings.gpuLayers)", value: $settings.gpuLayers, in: 0...128, step: 1)
                }

                Section {
                    Button("Reset Defaults") {
                        settings = .default
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

