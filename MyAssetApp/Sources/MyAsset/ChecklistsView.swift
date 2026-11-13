import SwiftUI

struct ChecklistsView: View {
    @ObservedObject private var life = LifeStore.shared

    @State private var selectedID: ChecklistSelection?

    struct ChecklistSelection: Identifiable {
        let id: UUID
    }

    private var inProgress: [Checklist] { life.checklists.filter { !$0.isComplete } }
    private var completed: [Checklist] { life.checklists.filter(\.isComplete) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("체크리스트").font(.largeTitle.bold())
                        Text("이사, 여행, 월말 정산 — 놓치기 쉬운 일을 단계별로 확인하세요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    newChecklistMenu
                }

                if life.checklists.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(inProgress) { list in
                            checklistCard(list)
                        }
                    }
                    if !completed.isEmpty {
                        Text("완료됨").font(.headline).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                            ForEach(completed) { list in
                                checklistCard(list).opacity(0.7)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(item: $selectedID) { selection in
            ChecklistDetailSheet(checklistID: selection.id)
        }
    }

    private var newChecklistMenu: some View {
        Menu {
            Button("빈 체크리스트") {
                let list = Checklist(name: "새 체크리스트")
                life.addChecklist(list)
                selectedID = ChecklistSelection(id: list.id)
            }
            Divider()
            Section("템플릿으로 만들기") {
                ForEach(ChecklistTemplate.all) { template in
                    Button {
                        let list = template.instantiate()
                        life.addChecklist(list)
                        selectedID = ChecklistSelection(id: list.id)
                    } label: {
                        Label(template.name, systemImage: template.icon)
                    }
                }
            }
        } label: {
            Label("새 체크리스트", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .frame(width: 160)
    }

    private func checklistCard(_ list: Checklist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: list.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name).font(.headline)
                    Text("\(list.doneCount)/\(list.items.count) 완료")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if list.isComplete {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green)
                }
            }

            ProgressView(value: list.progress)
                .tint(list.isComplete ? Theme.green : Theme.accent)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(list.items.filter { !$0.isDone }.prefix(3)) { item in
                    HStack(spacing: 7) {
                        Image(systemName: "circle").font(.caption2).foregroundStyle(.tertiary)
                        Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if list.items.allSatisfy(\.isDone) && !list.items.isEmpty {
                    Text("모든 항목을 완료했어요 🎉").font(.caption).foregroundStyle(Theme.green)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
        .onTapGesture { selectedID = ChecklistSelection(id: list.id) }
        .contextMenu {
            Button("열기") { selectedID = ChecklistSelection(id: list.id) }
            Divider()
            Button("삭제", role: .destructive) { life.deleteChecklist(id: list.id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 48)).foregroundStyle(Theme.accent.gradient)
            Text("체크리스트로 빠짐없이 챙기세요").font(.title3.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(ChecklistTemplate.all) { template in
                    Button {
                        let list = template.instantiate()
                        life.addChecklist(list)
                        selectedID = ChecklistSelection(id: list.id)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: template.icon).font(.system(size: 20)).foregroundStyle(Theme.accent)
                            Text(template.name).font(.subheadline.weight(.medium))
                            Text("\(template.items.count)개 항목").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 체크리스트 상세

struct ChecklistDetailSheet: View {
    let checklistID: UUID

    @ObservedObject private var life = LifeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var newItem = ""
    @State private var showDeleteConfirm = false

    private var checklist: Checklist? { life.checklist(id: checklistID) }

    var body: some View {
        VStack(spacing: 0) {
            if let list = checklist {
                HStack(spacing: 10) {
                    Image(systemName: list.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                    TextField("이름", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title3.bold())
                        .onSubmit { life.renameChecklist(id: checklistID, name: name) }
                    Spacer()
                    Text("\(list.doneCount)/\(list.items.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(20)

                ProgressView(value: list.progress)
                    .tint(list.isComplete ? Theme.green : Theme.accent)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(list.items) { item in
                            HStack(spacing: 10) {
                                Button {
                                    life.toggleItem(listID: checklistID, itemID: item.id)
                                } label: {
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(item.isDone ? Theme.green : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                Text(item.text)
                                    .font(.subheadline)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                Spacer()
                                Button {
                                    life.deleteItem(listID: checklistID, itemID: item.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.primary.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }

                HStack(spacing: 8) {
                    TextField("새 항목 추가", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addItem() }
                    Button {
                        addItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 20)

                HStack {
                    Button("체크리스트 삭제", role: .destructive) { showDeleteConfirm = true }
                    Spacer()
                    Button("닫기") {
                        life.renameChecklist(id: checklistID, name: name)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .padding(20)
            } else {
                Text("체크리스트를 찾을 수 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding(40)
                Button("닫기") { dismiss() }
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 440, height: 540)
        .onAppear { name = checklist?.name ?? "" }
        .confirmationDialog("이 체크리스트를 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                life.deleteChecklist(id: checklistID)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        life.addItem(listID: checklistID, text: text)
        newItem = ""
    }
}
