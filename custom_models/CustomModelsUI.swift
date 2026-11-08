import SwiftUI
import UniformTypeIdentifiers

extension CustomModelFiles {
    static func modelInfos() throws -> [ModelInfo] {
        try records().map { record in
            ModelInfo(modelName: record.name + " [" + String(record.key.prefix(6)) + "]",
                      tags: ["MNN", "Imported"], categories: ["Custom Models"],
                      vendor: "Imported", sources: ["custom": record.key], isDownloaded: true)
        }
    }
}

@MainActor
final class CustomModelsController: ObservableObject {
    @Published var query = ""
    @Published var link = ""
    @Published var results: [HFRepository] = []
    @Published var status = ""
    @Published var error = ""
    @Published var busy = false
    @Published var searching = false
    @Published var fraction = 0.0
    private var operation: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; searching = false; return }
        searching = true; error = ""
        searchTask = Task {
            do {
                let matches = try await CustomHuggingFace.search(text)
                try Task.checkCancellation()
                results = matches
                if matches.isEmpty { status = "Ничего не найдено" }
                searching = false
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription; searching = false }
            }
        }
    }
    func cancel() { operation?.cancel() }
    func stopSearch() { searchTask?.cancel() }
    func download(_ input: String, completed: @escaping () -> Void) {
        guard !busy else { return }
        do {
            let location = try HFLocation(input)
            start(completed: completed) { stage in
                try await CustomHuggingFace.download(location, to: stage) { text, value in
                    await MainActor.run { self.status = text; self.fraction = value }
                }
                return (location.repo + (location.folder.isEmpty ? "" : "/" + location.folder), location.repo)
            }
        } catch { self.error = error.localizedDescription }
    }
    func importFiles(_ result: Result<[URL], Error>, completed: @escaping () -> Void) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            start(completed: completed) { stage in
                let name = try await Task.detached(priority: .userInitiated) {
                    try CustomModelFiles.copySelection(urls, to: stage)
                }.value
                return (name, nil)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func start(completed: @escaping () -> Void,
                       work: @escaping (URL) async throws -> (String, String?)) {
        guard !busy else { return }
        busy = true; error = ""; status = "Подготовка модели…"; fraction = 0
        operation = Task {
            do {
                let stage = try CustomModelFiles.staging()
                defer { try? FileManager.default.removeItem(at: stage) }
                let (name, repo) = try await work(stage)
                try Task.checkCancellation()
                status = "Проверка файлов…"
                // File validation reads only metadata and a small prefix of each required file.
                try CustomModelFiles.publish(stage, name: name, repo: repo)
                fraction = 1; status = "Готово. Модель добавлена в My Model."
                completed()
            } catch {
                if Task.isCancelled { status = "Отменено" }
                else { self.error = error.localizedDescription; status = "" }
            }
            busy = false; operation = nil
        }
    }
}

struct CustomModelAccessButton: View {
    @ObservedObject var viewModel: ModelListViewModel
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Label("Hugging Face · Ссылка · Файлы", systemImage: "plus.circle.fill")
                .font(.subheadline).frame(maxWidth: .infinity).padding(12)
        }
        .background(.regularMaterial)
        .sheet(isPresented: $presented) {
            CustomModelsView {
                // Make imports visible immediately, even if the remote catalog is unavailable.
                do {
                    viewModel.models.removeAll { $0.sources?["custom"] != nil }
                    viewModel.models.insert(contentsOf: try CustomModelFiles.modelInfos(), at: 0)
                } catch { viewModel.errorMessage = error.localizedDescription; viewModel.showError = true }
            }
        }
    }
}

struct CustomModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CustomModelsController()
    @State private var folderPicker = false
    @State private var filesPicker = false
    let completed: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Поиск по всему Hugging Face") {
                    HStack {
                        TextField("Например, MNN-Pocket", text: $controller.query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.search).onSubmit { controller.search() }
                        Button { controller.search() } label: { Image(systemName: "magnifyingglass") }
                            .disabled(controller.busy || controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Поиск идёт по Hugging Face. Для запуска выбирай модели в формате MNN.")
                        .font(.caption).foregroundStyle(.secondary)
                    if controller.searching { ProgressView("Поиск…") }
                    ForEach(controller.results) { repo in
                        Button { controller.download(repo.id, completed: completed) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repo.id).font(.subheadline).textSelection(.enabled)
                                Text("↓ \(repo.downloads ?? 0) · \(repo.pipeline_tag ?? "модель")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(controller.busy)
                    }
                }
                Section("Скачать по ссылке") {
                    TextField("https://huggingface.co/автор/модель", text: $controller.link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Скачать MNN-модель") { controller.download(controller.link, completed: completed) }
                        .disabled(controller.busy || controller.link.isEmpty)
                    Text("Можно вставить автор/модель, ссылку на репозиторий, папку или файл config.json. Только публичные модели без авторизации.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Импорт из «Файлов»") {
                    Button("Выбрать папку модели") { folderPicker = true }.disabled(controller.busy)
                    Button("Выбрать файлы модели") { filesPicker = true }.disabled(controller.busy)
                    Text("Выбери распакованную папку с config.json, llm_config.json, .mnn, весами и токенизатором. Или выдели все файлы модели сразу. ZIP сначала распакуй в «Файлах».")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if controller.busy || !controller.status.isEmpty {
                    Section {
                        if controller.busy { ProgressView(); ProgressView(value: controller.fraction) }
                        Text(controller.status).font(.footnote)
                        if controller.busy { Button("Отменить", role: .destructive) { controller.cancel() } }
                    }
                }
                if !controller.error.isEmpty {
                    Section("Не удалось добавить модель") {
                        Text(controller.error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Добавить модель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }.disabled(controller.busy)
            } }
            .interactiveDismissDisabled(controller.busy)
            .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) {
                controller.importFiles($0, completed: completed)
            }
            .fileImporter(isPresented: $filesPicker, allowedContentTypes: [.item], allowsMultipleSelection: true) {
                controller.importFiles($0, completed: completed)
            }
            .onDisappear { controller.stopSearch() }
        }
    }
}
