
// Exercise the actual iOS networking implementation against the user's model.
let results = try await CustomHuggingFace.search("MNN-Pocket")
guard results.contains(where: { $0.id == "taobao-mnn/MNN-Pocket-0.3B-MNN" }) else {
    fatalError("User model missing from global search")
}
let smokeStage = try CustomModelFiles.staging()
defer { try? FileManager.default.removeItem(at: smokeStage) }
try await CustomHuggingFace.download(try HFLocation("taobao-mnn/MNN-Pocket-0.3B-MNN"), to: smokeStage) { name, _ in
    print("Download \(name)")
}
try CustomModelFiles.validate(smokeStage)
let before = try CustomModelFiles.records()
try CustomModelFiles.publish(smokeStage, name: "Pocket smoke test", repo: "taobao-mnn/MNN-Pocket-0.3B-MNN")
let after = try CustomModelFiles.records()
guard after.count == before.count + 1, let added = after.last else { fatalError("Manifest persistence failed") }
guard FileManager.default.fileExists(atPath: CustomModelFiles.directory(added.key).appendingPathComponent("llm.mnn.weight").path) else {
    fatalError("Published weights missing")
}
try CustomModelFiles.remove(added.key)
let cleaned = try CustomModelFiles.records()
assert(cleaned.count == before.count)
print("PASS live Hugging Face search, Pocket download, validation, persistence and deletion")
