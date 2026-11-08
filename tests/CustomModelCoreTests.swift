
func expectFailure(_ label: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("Expected failure: \(label)") }
    catch { print("PASS rejected \(label)") }
}
let pocket = try HFLocation("https://huggingface.co/taobao-mnn/MNN-Pocket-0.3B-MNN")
assert(pocket.repo == "taobao-mnn/MNN-Pocket-0.3B-MNN" && pocket.folder.isEmpty && pocket.revision == "main")
let shortLocation = try HFLocation("author/model")
let treeLocation = try HFLocation("https://huggingface.co/author/model/tree/main")
assert(shortLocation == treeLocation)
let fileLocation = try HFLocation("https://huggingface.co/author/model/blob/main/int4/config.json")
assert(fileLocation.folder == "int4")
expectFailure("foreign host") { _ = try HFLocation("https://huggingface.co.evil.test/a/b") }
expectFailure("invalid repo") { _ = try HFLocation("../model") }
expectFailure("path traversal") { _ = try HFLocation("https://huggingface.co/a/b/tree/main/../evil") }
let stage = try CustomModelFiles.staging()
defer { try? FileManager.default.removeItem(at: stage) }
expectFailure("incomplete model") { try CustomModelFiles.validate(stage) }
for name in ["llm.mnn", "llm.mnn.weight", "tokenizer.mtok", "llm_config.json"] {
    try Data("model-test".utf8).write(to: stage.appendingPathComponent(name))
}
try Data("{\"tokenizer_file\":\"tokenizer.mtok\"}".utf8).write(to: stage.appendingPathComponent("config.json"))
try CustomModelFiles.validate(stage)
print("PASS complete Pocket-style model")
try Data("version https://git-lfs.github.com/spec/v1\noid sha256:test\n".utf8).write(to: stage.appendingPathComponent("llm.mnn"))
expectFailure("LFS pointer") { try CustomModelFiles.validate(stage) }
try Data("model-test".utf8).write(to: stage.appendingPathComponent("llm.mnn"))
try Data("{\"llm_model\":\"../llm.mnn\"}".utf8).write(to: stage.appendingPathComponent("config.json"))
expectFailure("config traversal") { try CustomModelFiles.validate(stage) }
try Data("{}".utf8).write(to: stage.appendingPathComponent("config.json"))
try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("unsafe").path, withDestinationPath: "/etc/passwd")
expectFailure("symlink") { try CustomModelFiles.validate(stage) }
print("All custom model core tests passed")
