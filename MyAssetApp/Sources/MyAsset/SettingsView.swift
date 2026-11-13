import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var store = DataStore.shared
    @ObservedObject private var life = LifeStore.shared

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showResetConfirm = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("설정").font(.largeTitle.bold())

                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Theme.green)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(Theme.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                section("데이터") {
                    settingRow(icon: "square.and.arrow.up", title: "백업 내보내기",
                               subtitle: "가계부·구독·일정·체크리스트 등 모든 데이터를 JSON 파일 하나로 저장합니다.") {
                        Button("내보내기") { showExporter = true }
                    }
                    Divider()
                    settingRow(icon: "square.and.arrow.down", title: "백업 가져오기",
                               subtitle: "내보낸 백업 파일로 데이터를 복원합니다. 현재 데이터는 대체됩니다.") {
                        Button("가져오기") { showImporter = true }
                    }
                    Divider()
                    settingRow(icon: "folder", title: "데이터 저장 위치",
                               subtitle: DataStore.dataURL.path) {
                        Button("Finder에서 보기") {
                            NSWorkspace.shared.activateFileViewerSelecting([DataStore.dataURL, LifeStore.dataURL])
                        }
                    }
                }

                section("관리") {
                    settingRow(icon: "trash", title: "모든 데이터 삭제",
                               subtitle: "가계부와 생활 데이터를 모두 삭제합니다. 되돌릴 수 없습니다.") {
                        Button("전체 삭제", role: .destructive) { showResetConfirm = true }
                    }
                }

                section("정보") {
                    settingRow(icon: "info.circle", title: "MyLife",
                               subtitle: "버전 2.0.0 · macOS 일상 생활 관리") { EmptyView() }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .fileExporter(isPresented: $showExporter,
                      document: BackupDocument(data: makeBackup()),
                      contentType: .json,
                      defaultFilename: "MyLife-백업-\(DateFormat.day.string(from: Date()))") { result in
            if case .success = result { message = "백업을 내보냈습니다."; errorMessage = nil }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try restoreBackup(data)
                message = "백업을 복원했습니다."
                errorMessage = nil
            } catch {
                message = nil
                errorMessage = "백업 파일을 불러오지 못했습니다. 올바른 MyLife 백업 파일인지 확인해주세요."
            }
        }
        .confirmationDialog("정말 모든 데이터를 삭제할까요?", isPresented: $showResetConfirm) {
            Button("전체 삭제", role: .destructive) {
                store.resetAll()
                life.resetAll()
                message = "모든 데이터를 삭제했습니다."
                errorMessage = nil
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 작업은 되돌릴 수 없습니다. 삭제 전에 백업 내보내기를 권장합니다.")
        }
    }

    // MARK: 통합 백업

    /// 가계부(asset) + 생활(life) 데이터를 하나의 JSON으로 묶음
    private func makeBackup() -> Data {
        let asset = (try? JSONSerialization.jsonObject(with: store.exportData())) ?? [String: Any]()
        let lifeData = (try? JSONSerialization.jsonObject(with: life.exportData())) ?? [String: Any]()
        let envelope: [String: Any] = ["version": 2, "asset": asset, "life": lifeData]
        return (try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private func restoreBackup(_ data: Data) throws {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let asset = obj["asset"] {
            try store.importData(try JSONSerialization.data(withJSONObject: asset))
            if let lifeObj = obj["life"] {
                try life.importData(try JSONSerialization.data(withJSONObject: lifeObj))
            }
        } else {
            // 구버전(MyAsset 1.0) 백업 — 가계부 데이터만 복원
            try store.importData(data)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(spacing: 12) {
                content()
            }
            .padding(18)
            .card()
        }
    }

    private func settingRow<Trailing: View>(icon: String, title: String, subtitle: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            trailing()
        }
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
