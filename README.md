# MNNLLMChat iOS builder

Builds unsigned arm64/iOS 17+ IPA from pinned alibaba/MNN revision
`5b74a931887ba5b4d9f65b222cc18dd1a16599a8` with macOS 15 / Xcode 16.4.

Custom additions, available above My Model and Model Market lists:
- Global Hugging Face API search (up to 40 results per query).
- Public repository downloads by `owner/model`, repository URL, tree URL,
  or config-file URL. Downloads use an immutable snapshot SHA and stream to disk.
- Import a folder or multiple selected model files through iOS Files.
  Unzip archives in Files first. Select the actual folder containing config.json.
- Validate required MNN graph, weights, tokenizer and configuration; reject missing
  files, Git LFS pointers, traversal paths and symlinks.
- Persistent private storage with unique model IDs; partial or canceled imports
  are discarded. Existing catalog models are preserved.

Only MNN LLM exports are supported. GGUF/safetensors require conversion elsewhere.
Private/gated Hugging Face repositories and automatic ZIP extraction are not supported.
Model architecture, device RAM and native runtime compatibility still matter;
physical-device inference is not validated by the build.

`custom_models/` contains the maintained Swift implementation.
`scripts/apply_custom_models.py` applies checked integration edits and appends the
new declarations to an existing compiled Swift unit (the upstream Xcode project
uses explicit file references). Tests run before native builds. The workflow uploads
an artifact and creates a release. Sign the IPA with your preferred sideload tool.

## AltStore Classic / SideStore source

Add this URL in Sources → +:

https://raw.githubusercontent.com/nook-agent/mnn-llm-chat-builder/main/source.json

The source points to the latest published custom build. Metadata (bundle ID,
version, size, minimum iOS and privacy descriptions) is read from the real IPA by
`scripts/generate_source.py`. Successful future builds update it automatically.
This is an AltStore Classic / SideStore source, not an AltStore PAL marketplace.

Icon: original Alibaba MNN app artwork from the pinned upstream revision.
