# Llama iOS

SwiftUI iOS 17+ app for running local GGUF models with `llama.cpp` through the
[`llama.swift`](https://github.com/mattt/llama.swift) Swift package.

## Features

- Import `.gguf` models from Files.
- Download public Hugging Face GGUF files with `owner/model-name` and filename.
- Discover public Hugging Face GGUF models from an in-app catalog.
- Pick a GGUF file from a model detail page and download it directly.
- Store models in the app sandbox under `Application Support/Models`.
- Persist model metadata such as repo id, filename, quantization, parameter size,
  download URL, and last-used time.
- Manage multiple chat sessions with persisted JSON history.
- Stream local generation token-by-token through llama.cpp.
- Tune temperature, context length, max tokens, thread count, seed, and GPU layers.
- Persist generation settings across app launches.

## Requirements

- macOS with Xcode 15 or newer.
- iOS 17+ deployment target.
- XcodeGen.
- A real iPhone or iPad is recommended for local inference. Simulator builds force
  GPU layers to `0`, so performance and Metal behavior will differ from device.

## Generate the Xcode Project

```sh
brew install xcodegen
xcodegen generate
open LlamaIOS.xcodeproj
```

Select a development team in Xcode before running on device.

## Hugging Face Downloads

The first version supports public files only. Enter:

- Repo ID: `owner/model-name`
- Filename: `model.Q4_K_M.gguf`

The app downloads from:

```text
https://huggingface.co/{repoId}/resolve/main/{filename}
```

Private and gated models remain out of scope for v2. The catalog and download
flows only use public Hugging Face Hub APIs.

## Persistence

v2 stores chats, models, and generation settings in versioned JSON files. Existing
v1 `chats.json` and `models.json` array files are migrated in place the first time
the app loads them.

## Tests

After generating the Xcode project, run the `LlamaIOSTests` unit test target in
Xcode. The tests cover Hugging Face URL validation, model import metadata, chat
persistence, and generation setting defaults.

## Notes

Large model files are ignored by git. Keep GGUF files outside the repository or
inside the app sandbox after import/download.
