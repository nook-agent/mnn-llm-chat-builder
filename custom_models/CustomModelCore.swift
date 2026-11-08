import Foundation

struct CustomModelError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct HFRepository: Identifiable, Decodable {
    let id: String
    let downloads: Int?
    let pipeline_tag: String?
}

struct HFLocation: Equatable {
    let repo: String
    let revision: String
    let folder: String
    init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String]
        if value.contains("://") {
            guard let url = URL(string: value), url.scheme == "https", url.host == "huggingface.co",
                  url.user == nil, url.password == nil else {
                throw CustomModelError("Нужна ссылка https://huggingface.co/автор/модель")
            }
            parts = url.path.split(separator: "/").map(String.init)
        } else { parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init) }
        guard parts.count >= 2, parts.prefix(2).allSatisfy({ $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil && $0 != ".." }) else {
            throw CustomModelError("Укажи автора и модель: автор/модель")
        }
        repo = parts.prefix(2).joined(separator: "/")
        if parts.count == 2 { revision = "main"; folder = ""; return }
        guard parts.count >= 4, ["tree", "blob", "resolve"].contains(parts[2]) else {
            throw CustomModelError("Поддерживаются ссылки на репозиторий, папку или файл модели.")
        }
        revision = parts[3]
        var tail = Array(parts.dropFirst(4))
        if parts[2] != "tree", !tail.isEmpty { tail.removeLast() }
        folder = tail.joined(separator: "/")
        guard !revision.isEmpty, revision != "..", !revision.contains("/"),
              tail.allSatisfy({ $0 != ".." && $0 != "." && !$0.contains("\\") }) else {
            throw CustomModelError("Некорректный путь модели")
        }
    }
}

struct CustomModelRecord: Codable {
    let key: String
    let name: String
    let repo: String?
}

enum CustomModelFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMNNModels", isDirectory: true)
    }
    static func directory(_ key: String) -> URL { root.appendingPathComponent(key, isDirectory: true) }
    static func records() throws -> [CustomModelRecord] {
        let manifest = root.appendingPathComponent("models.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([CustomModelRecord].self, from: Data(contentsOf: manifest))
            .filter { UUID(uuidString: $0.key) != nil && FileManager.default.fileExists(atPath: directory($0.key).appendingPathComponent("config.json").path) }
    }
    static func save(_ records: [CustomModelRecord]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: root.appendingPathComponent("models.json"), options: .atomic)
    }
    static func publish(_ staging: URL, name: String, repo: String?) throws {
        try validate(staging)
        var records = try self.records()
        let key = UUID().uuidString
        let target = directory(key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: target)
        records.append(CustomModelRecord(key: key, name: name, repo: repo))
        do { try save(records) } catch { try? FileManager.default.moveItem(at: target, to: staging); throw error }
    }
    static func remove(_ key: String) throws {
        guard UUID(uuidString: key) != nil else { throw CustomModelError("Неверный ID модели") }
        var records = try self.records()
        let original = records
        records.removeAll { $0.key == key }
        try save(records)
        do { try FileManager.default.removeItem(at: directory(key)) }
        catch { try? save(original); throw error }
    }
    static func safeURL(_ path: String, in root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." }) else {
            throw CustomModelError("Недопустимый путь в модели: \(path)")
        }
        return root.appendingPathComponent(path)
    }
    static func validate(_ root: URL) throws {
        let fm = FileManager.default
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw CustomModelError("Не удалось открыть папку")
        }
        for case let file as URL in iterator {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw CustomModelError("Символические ссылки в модели не поддерживаются")
            }
        }
        let configURL = root.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CustomModelError("В папке нужен config.json от MNN-модели. GGUF и safetensors не подходят.")
        }
        var required = [config["llm_model"] as? String ?? "llm.mnn",
                        config["llm_weight"] as? String ?? "llm.mnn.weight",
                        config["tokenizer_file"] as? String ?? "tokenizer.txt", "llm_config.json"]
        // Older exports use tokenizer.mtok without an explicit tokenizer_file setting.
        if config["tokenizer_file"] == nil, fm.fileExists(atPath: root.appendingPathComponent("tokenizer.mtok").path) {
            required[2] = "tokenizer.mtok"
        }
        // Validate every explicit file reference, including optional vision/audio modules.
        for (key, value) in config where key.hasSuffix("_model") || key.hasSuffix("_weight") || key.hasSuffix("_file") {
            if let path = value as? String, !path.isEmpty { required.append(path) }
        }
        for path in Set(required) {
            let file = try safeURL(path, in: root)
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else {
                throw CustomModelError("Не хватает файла: \(path). Выбери всю папку модели.")
            }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let head = try handle.read(upToCount: 128) ?? Data()
            if String(data: head, encoding: .utf8)?.hasPrefix("version https://git-lfs.github.com/spec/") == true {
                throw CustomModelError("\(path) — указатель Git LFS, а не скачанный файл модели.")
            }
        }
    }
    static func staging() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mnn-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func copySelection(_ urls: [URL], to staging: URL) throws -> String {
        let fm = FileManager.default
        let access = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (url, granted) in zip(urls, access) where granted { url.stopAccessingSecurityScopedResource() } }
        if urls.count == 1, try urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            for child in try fm.contentsOfDirectory(at: urls[0], includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                try fm.copyItem(at: child, to: staging.appendingPathComponent(child.lastPathComponent))
            }
            return urls[0].lastPathComponent
        }
        for url in urls {
            try Task.checkCancellation()
            try fm.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent))
        }
        return "Импорт \(Date().formatted(date: .numeric, time: .shortened))"
    }
}

enum CustomHuggingFace {
    struct Snapshot: Decodable {
        struct File: Decodable { let rfilename: String }
        let sha: String
        let siblings: [File]
    }
    static func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"; components.host = "huggingface.co"
        components.path = path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CustomModelError("Неверная ссылка") }
        return url
    }
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CustomModelError("Нет ответа Hugging Face") }
        switch http.statusCode {
        case 200...299: return
        case 401, 403: throw CustomModelError("Модель закрыта или требует разрешения. Сейчас доступны публичные модели без входа.")
        case 404: throw CustomModelError("Модель или ревизия не найдена")
        case 429: throw CustomModelError("Hugging Face ограничил запросы. Попробуй позже.")
        default: throw CustomModelError("Hugging Face: HTTP \(http.statusCode)")
        }
    }
    static func search(_ query: String) async throws -> [HFRepository] {
        let endpoint = try url("/api/models", query: [.init(name: "search", value: query), .init(name: "limit", value: "40"), .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1")])
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try check(response)
        return try JSONDecoder().decode([HFRepository].self, from: data)
    }
    static func download(_ location: HFLocation, to staging: URL,
                         progress: @escaping @Sendable (String, Double) async -> Void) async throws {
        let endpoint = try url("/api/models/\(location.repo)/revision/\(location.revision)")
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        try check(response)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        let prefix = location.folder.isEmpty ? "" : location.folder + "/"
        let allowed = Set(["json", "mnn", "weight", "mtok", "txt", "model", "bin", "tiktoken", "jinja", "jinja2"])
        let files = snapshot.siblings.map(\.rfilename).filter {
            $0.hasPrefix(prefix) && allowed.contains(($0 as NSString).pathExtension.lowercased()) &&
            !(($0 as NSString).lastPathComponent.lowercased().hasPrefix("readme")) &&
            !(($0 as NSString).lastPathComponent.lowercased().hasPrefix("license"))
        }
        guard files.contains(prefix + "config.json"), files.contains(where: { $0.hasSuffix(".mnn") }) else {
            throw CustomModelError("Здесь нет MNN-модели. Нужны config.json и файлы .mnn; GGUF/safetensors не поддерживаются. Для вложенной модели вставь ссылку на её папку.")
        }
        for (index, path) in files.enumerated() {
            try Task.checkCancellation()
            let relative = String(path.dropFirst(prefix.count))
            let target = try CustomModelFiles.safeURL(relative, in: staging)
            await progress("\(index + 1)/\(files.count): \(relative)", Double(index) / Double(files.count))
            var request = URLRequest(url: try url("/\(location.repo)/resolve/\(snapshot.sha)/\(path)"))
            request.timeoutInterval = 3600
            let (temporary, fileResponse) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try check(fileResponse)
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }
}
