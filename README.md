# Llama iOS

SwiftUI iOS 17+ app for running local GGUF models with `llama.cpp` through the
[`llama.swift`](https://github.com/mattt/llama.swift) Swift package.

## Features

- Import `.gguf` models from Files.
- Download public Hugging Face GGUF files with `owner/model-name` and filename.
- Store models in the app sandbox under `Application Support/Models`.
- Manage multiple chat sessions with persisted JSON history.
- Stream local generation token-by-token through llama.cpp.
- Tune temperature, context length, max tokens, thread count, seed, and GPU layers.

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

Private and gated models are intentionally out of scope for v1 because they need
token storage and authenticated requests.

## Tests

After generating the Xcode project, run the `LlamaIOSTests` unit test target in
Xcode. The tests cover Hugging Face URL validation, model import metadata, chat
persistence, and generation setting defaults.

## Notes

Large model files are ignored by git. Keep GGUF files outside the repository or
inside the app sandbox after import/download.
