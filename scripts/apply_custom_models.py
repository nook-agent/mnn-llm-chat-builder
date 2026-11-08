#!/usr/bin/env python3
"""Apply audited, fail-closed changes to the pinned upstream tree."""
from pathlib import Path
import sys
root = Path(sys.argv[1]) / 'apps/iOS/MNNLLMChat/MNNLLMiOS'
builder = Path(__file__).resolve().parent.parent

def patch(file, old, new):
    path = root / file
    text = path.read_text()
    assert text.count(old) == 1, (file, old, text.count(old))
    path.write_text(text.replace(old, new))

patch('MainTab/ModelList/Models/ModelInfo.swift',
      '    var id: String {',
      '    var id: String {\n        if let key = sources?["custom"] { return "custom/" + key }')
patch('MainTab/ModelList/Models/ModelInfo.swift',
      '    var localPath: String {',
      '    var localPath: String {\n        if let key = sources?["custom"] { return CustomModelFiles.directory(key).path }')
vm = 'MainTab/ModelList/Models/ModelListViewModel.swift'
patch(vm, '            syncDownloadStatus(for: &fetchedModels)',
      '            syncDownloadStatus(for: &fetchedModels)\n            fetchedModels.append(contentsOf: try CustomModelFiles.modelInfos())')
patch(vm, '            errorMessage = "Error: \\(error.localizedDescription)"',
      '            errorMessage = "Error: \\(error.localizedDescription)"\n            if let imported = try? CustomModelFiles.modelInfos() {\n                models.removeAll { $0.sources?["custom"] != nil }\n                models.insert(contentsOf: imported, at: 0)\n            }')
patch(vm, '        guard model.isDownloaded else { return }\n\n        do {',
      '''        guard model.isDownloaded else { return }
        if let key = model.sources?["custom"] {
            do {
                try CustomModelFiles.remove(key)
                await MainActor.run {
                    self.models.removeAll { $0.id == model.id }
                    self.unpinModel(model)
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription; self.showError = true }
            }
            return
        }

        do {''')
patch('MainTab/ModelList/Views/ModelListView.swift',
      '            .searchable(text: $searchText, prompt: "Search models...")',
      '            .safeAreaInset(edge: .top) { CustomModelAccessButton(viewModel: viewModel) }\n            .searchable(text: $searchText, prompt: "Search models...")')
patch('MainTab/LocalModelList/Views/LocalModelListView.swift',
      '        .listStyle(.plain)',
      '        .safeAreaInset(edge: .top) { CustomModelAccessButton(viewModel: viewModel) }\n        .listStyle(.plain)')
# Existing Xcode project has explicit file references. Append these declarations to
# an existing compiled unit; keep the maintained sources separate in this builder.
path = root / 'MainTab/ModelList/Views/ModelListView.swift'
with path.open('a') as out:
    for name in ('CustomModelCore.swift', 'CustomModelsUI.swift'):
        out.write('\n' + (builder / 'custom_models' / name).read_text())
print('Custom models patch applied')
