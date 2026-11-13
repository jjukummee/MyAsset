import SwiftUI

/// Claude가 data.json을 업데이트한 후 표시되는 거래 검토 화면.
/// 최근 가져온 거래를 카테고리·분류(지출/수입/이체/저축)로 인라인 수정할 수 있다.
struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DataStore.shared

    // 검토 대상: 최근 업데이트 정보를 기준으로 최신순 N건
    @State private var drafts: [TxDraft] = []
    @State private var searchText = ""

    private var filtered: [TxDraft] {
        guard !searchText.isEmpty else { return drafts }
        return drafts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            transactionList
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .onAppear(perform: loadDrafts)
    }

    // MARK: 헤더

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("거래내역 검토").font(.title3.bold())
                Text("분류가 잘못된 항목을 수정한 뒤 저장하세요")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: 검색

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("내용, 카테고리 검색...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: 거래 목록

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($drafts) { $draft in
                    if filtered.contains(where: { $0.id == draft.id }) {
                        TxDraftRow(draft: $draft)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 푸터

    private var footer: some View {
        HStack {
            Text("\(drafts.count)건")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("취소") { dismiss() }
            Button("저장") { save() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: 로직

    private func loadDrafts() {
        guard let info = store.externalUpdateInfo else {
            // 업데이트 정보 없으면 최근 50건
            drafts = store.transactions.prefix(50).map { TxDraft(from: $0) }
            return
        }
        // 업데이트된 시각 기준 ±1초 이후 거래 + 최소 addedCount건
        let count = max(info.addedCount, 1)
        drafts = Array(store.transactions.prefix(count)).map { TxDraft(from: $0) }
    }

    private func save() {
        for draft in drafts {
            guard var tx = store.transactions.first(where: { $0.id == draft.id }) else { continue }
            let newAmount = draft.adjustedAmount
            if tx.amount != newAmount || tx.category != draft.category || tx.memo != draft.memo {
                tx.amount = newAmount
                tx.category = draft.category
                tx.memo = draft.memo
                store.updateTransaction(tx)
            }
        }
        store.dismissExternalUpdate()
        dismiss()
    }
}

// MARK: - 거래 Draft 모델

struct TxDraft: Identifiable {
    let id: UUID
    var title: String
    var date: Date
    var originalAmount: Int   // 절댓값
    var sign: TxSign           // 지출 / 수입 / 이체 / 저축
    var category: String
    var memo: String

    /// 저장 시 amount 계산 (저축·이체는 음수이되 카테고리로 구분)
    var adjustedAmount: Int {
        switch sign {
        case .income: return abs(originalAmount)
        case .expense, .transfer, .savings: return -abs(originalAmount)
        }
    }

    init(from tx: UserTransaction) {
        id = tx.id
        title = tx.title
        date = tx.date
        originalAmount = abs(tx.amount)
        memo = tx.memo

        // 기존 카테고리 → sign 매핑
        switch tx.category {
        case "이체": sign = .transfer
        case "저축": sign = .savings
        default:    sign = tx.amount >= 0 ? .income : .expense
        }
        category = tx.category
    }
}

enum TxSign: String, CaseIterable {
    case expense = "지출"
    case income  = "수입"
    case transfer = "이체"
    case savings  = "저축"

    var color: Color {
        switch self {
        case .expense:  return Theme.red
        case .income:   return Theme.green
        case .transfer: return Color.secondary
        case .savings:  return Theme.teal
        }
    }

    var icon: String {
        switch self {
        case .expense:  return "arrow.up.right"
        case .income:   return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .savings:  return "banknote"
        }
    }
}

// MARK: - 행 뷰

private struct TxDraftRow: View {
    @Binding var draft: TxDraft

    // 분류 변경 시 카테고리 자동 세팅 여부
    @State private var expandedEdit = false

    private var allCategories: [String] {
        SpendCategory.all.map(\.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if expandedEdit { editPanel }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 12) {
            // 분류 토글
            Menu {
                ForEach(TxSign.allCases, id: \.self) { s in
                    Button {
                        draft.sign = s
                        // 분류 변경 시 카테고리 자동 동기화
                        if s == .transfer { draft.category = "이체" }
                        else if s == .savings { draft.category = "저축" }
                        else if s == .income  { draft.category = "수입" }
                    } label: {
                        Label(s.rawValue, systemImage: s.icon)
                    }
                }
            } label: {
                Image(systemName: draft.sign.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(draft.sign.color)
                    .frame(width: 28, height: 28)
                    .background(draft.sign.color.opacity(0.12))
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)

            // 내용 + 카테고리
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(DateFormat.dayLabel.string(from: draft.date))
                        .font(.caption).foregroundStyle(.tertiary)
                    CategoryBadge(category: draft.category)
                }
            }

            Spacer()

            // 금액
            Text((draft.sign == .income ? "+" : "-") + formatKRW(draft.originalAmount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(draft.sign == .income ? Theme.green : .primary)

            // 펼침 버튼
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expandedEdit.toggle() }
            } label: {
                Image(systemName: expandedEdit ? "chevron.up" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var editPanel: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("카테고리").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $draft.category) {
                    ForEach(allCategories, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("메모").font(.caption).foregroundStyle(.secondary)
                TextField("메모 입력...", text: $draft.memo)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color.primary.opacity(0.03))
    }
}
