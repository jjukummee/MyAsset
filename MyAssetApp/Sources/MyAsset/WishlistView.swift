import SwiftUI

struct WishlistView: View {
    @ObservedObject private var store = DataStore.shared

    @State private var showForm = false
    @State private var editing: WishlistItem?
    @State private var detailItem: WishlistItem?
    @State private var filter: StatusFilter = .all
    @State private var sort: SortOption = .recent

    // 구매 완료 → 거래내역 추가 흐름
    @State private var purchasePrompt: WishlistItem?

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "전체"
        case considering = "고민 중"
        case wanted = "사고 싶음"
        case planned = "구매 예정"
        case purchased = "구매 완료"
        case paused = "보류"
        case abandoned = "포기"

        var id: String { rawValue }

        var status: WishlistStatus? {
            switch self {
            case .all: return nil
            case .considering: return .considering
            case .wanted: return .wanted
            case .planned: return .planned
            case .purchased: return .purchased
            case .paused: return .paused
            case .abandoned: return .abandoned
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case recent = "최근 등록순"
        case targetDate = "목표 구매일 빠른 순"
        case priceHigh = "가격 높은 순"
        case priceLow = "가격 낮은 순"
        case priority = "우선순위 높은 순"
        case name = "이름순"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statRow
                if store.wishlistItems.isEmpty {
                    emptyState
                } else {
                    controlBar
                    if filteredItems.isEmpty {
                        Text("해당하는 항목이 없어요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                            ForEach(filteredItems) { item in
                                card(item)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showForm) {
            WishlistForm(editing: nil)
        }
        .sheet(item: $editing) { item in
            WishlistForm(editing: item)
        }
        .sheet(item: $detailItem) { item in
            WishlistDetail(item: item,
                           onEdit: { item in
                               detailItem = nil
                               // 상세 시트가 닫힌 뒤 수정 시트를 띄워 전환 충돌 방지
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { editing = item }
                           },
                           onRequestPurchase: { detailItem = nil; purchasePrompt = $0 })
        }
        .confirmationDialog("거래내역에도 추가할까요?",
                            isPresented: Binding(get: { purchasePrompt != nil },
                                                 set: { if !$0 { purchasePrompt = nil } }),
                            titleVisibility: .visible) {
            Button("추가하기") {
                if let item = purchasePrompt { store.convertWishlistItemToTransaction(item) }
                purchasePrompt = nil
            }
            Button("완료만 하기") {
                if let item = purchasePrompt { store.markWishlistItemAsPurchased(item) }
                purchasePrompt = nil
            }
            Button("취소", role: .cancel) { purchasePrompt = nil }
        } message: {
            if let item = purchasePrompt {
                Text("\(item.name) · \(formatKRW(item.price))을(를) 지출 거래로 기록할 수 있어요.")
            }
        }
    }

    // MARK: 헤더

    private var header: some View {
        HStack {
            Text("위시리스트").font(.largeTitle.bold())
            Spacer()
            Button {
                editing = nil
                showForm = true
            } label: {
                Label("항목 추가", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }

    // MARK: 요약 카드

    private var statRow: some View {
        HStack(spacing: 16) {
            statCard(title: "전체 예상 금액", value: formatKRW(store.wishlistTotal),
                     icon: "tag", tint: Theme.accent)
            statCard(title: "구매 예정 금액", value: formatKRW(store.wishlistPlannedTotal),
                     icon: "cart", tint: Theme.purple)
            statCard(title: "구매 완료 금액", value: formatKRW(store.wishlistPurchasedTotal),
                     icon: "checkmark.circle", tint: Theme.green)
            statCard(title: "우선순위 높음", value: "\(store.wishlistHighPriorityCount)개",
                     icon: "flame", tint: Theme.red)
        }
    }

    private func statCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 22, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .card()
    }

    // MARK: 필터 / 정렬

    private var controlBar: some View {
        HStack {
            Picker("필터", selection: $filter) {
                ForEach(StatusFilter.allCases) { f in
                    Text("\(f.rawValue)\(countLabel(f))").tag(f)
                }
            }
            .frame(width: 200)
            Spacer()
            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option { Label(option.rawValue, systemImage: "checkmark") }
                        else { Text(option.rawValue) }
                    }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
            }
            .frame(width: 200)
        }
    }

    private func countLabel(_ f: StatusFilter) -> String {
        let count: Int
        if let s = f.status {
            count = store.wishlistItems.filter { $0.status == s }.count
        } else {
            count = store.wishlistItems.count
        }
        return count > 0 ? " (\(count))" : ""
    }

    private var filteredItems: [WishlistItem] {
        var items = store.wishlistItems
        if let s = filter.status {
            items = items.filter { $0.status == s }
        }
        switch sort {
        case .recent:
            items.sort { $0.createdAt > $1.createdAt }
        case .targetDate:
            items.sort { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
        case .priceHigh:
            items.sort { $0.price > $1.price }
        case .priceLow:
            items.sort { $0.price < $1.price }
        case .priority:
            items.sort { $0.priority.weight > $1.priority.weight }
        case .name:
            items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return items
    }

    // MARK: 카드

    private func card(_ item: WishlistItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statusBadge(item.status)
                Spacer()
                priorityBadge(item.priority)
            }
            Text(item.name)
                .font(.headline)
                .lineLimit(1)
            Text(formatKRW(item.price))
                .font(.title3.bold())
                .foregroundStyle(item.status == .purchased ? .secondary : .primary)
            HStack(spacing: 8) {
                wishCategoryBadge(item.category)
                if let target = item.targetDate {
                    Label(DateFormat.dayLabel.string(from: target), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(targetOverdue(item) ? Theme.red : .secondary)
                }
            }
            if !item.memo.isEmpty {
                Text(item.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
        .opacity(item.status == .purchased || item.status == .abandoned ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture { detailItem = item }
        .contextMenu {
            Button("수정") { editing = item }
            if item.status != .purchased {
                Button("구매 완료") { purchasePrompt = item }
            }
            Menu("상태 변경") {
                ForEach(WishlistStatus.allCases) { s in
                    Button(s.rawValue) { store.updateWishlistItemStatus(item, status: s) }
                }
            }
            Divider()
            Button("삭제", role: .destructive) { store.deleteWishlistItem(item) }
        }
    }

    private func targetOverdue(_ item: WishlistItem) -> Bool {
        guard let target = item.targetDate, item.status != .purchased else { return false }
        return target < Calendar.current.startOfDay(for: Date())
    }

    private func statusBadge(_ status: WishlistStatus) -> some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func priorityBadge(_ priority: WishlistPriority) -> some View {
        Text(priority.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(priority.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(priority.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func wishCategoryBadge(_ category: String) -> some View {
        Text(category)
            .font(.caption.weight(.medium))
            .foregroundStyle(WishlistItem.categoryColor(for: category))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(WishlistItem.categoryColor(for: category).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: 빈 상태

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48)).foregroundStyle(Theme.pink.gradient)
            Text("사고 싶은 물건을 등록해보세요").font(.title3.bold())
            Text("노트북, 아이패드, 여행 준비물처럼 나중에 구매하고 싶은 항목을\n가격·우선순위·목표 구매일과 함께 정리할 수 있어요.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                editing = nil
                showForm = true
            } label: {
                Label("첫 항목 등록", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 위시리스트 폼

struct WishlistForm: View {
    var editing: WishlistItem?

    @ObservedObject private var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var price = 0
    @State private var category = "기타"
    @State private var priority: WishlistPriority = .medium
    @State private var hasTargetDate = false
    @State private var targetDate = Date()
    @State private var purchaseURL = ""
    @State private var memo = ""
    @State private var status: WishlistStatus = .wanted
    @State private var showDeleteConfirm = false

    private var targetIsPast: Bool {
        hasTargetDate && targetDate < Calendar.current.startOfDay(for: Date())
    }

    private var urlInvalid: Bool {
        let trimmed = purchaseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed) else { return true }
        return !(url.scheme == "http" || url.scheme == "https")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "위시리스트 추가" : "항목 수정").font(.title3.bold())
                Spacer()
            }
            .padding(20)

            Form {
                Section {
                    TextField("항목명", text: $name, prompt: Text("예: 에어팟 맥스"))
                    TextField("예상 가격", value: $price, format: .number)
                    Picker("카테고리", selection: $category) {
                        ForEach(WishlistItem.categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("우선순위", selection: $priority) {
                        ForEach(WishlistPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("상태", selection: $status) {
                        ForEach(WishlistStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    Toggle("목표 구매일 설정", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("목표 구매일", selection: $targetDate, displayedComponents: .date)
                        if targetIsPast {
                            Label("목표 구매일이 이미 지난 날짜예요.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Theme.orange)
                        }
                    }
                }

                Section {
                    TextField("구매 링크", text: $purchaseURL, prompt: Text("https://"))
                    if urlInvalid {
                        Label("올바른 링크 형식이 아니에요.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Theme.orange)
                    }
                    TextField("메모", text: $memo, prompt: Text("예: 할인하면 구매하기"), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            // 검증 안내
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                validationNote("항목명을 입력해 주세요.")
            } else if price <= 0 {
                validationNote("가격은 0원보다 커야 해요.")
            }

            HStack {
                if editing != nil {
                    Button("삭제", role: .destructive) { showDeleteConfirm = true }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button(editing == nil ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || price <= 0)
            }
            .padding(20)
        }
        .frame(width: 460, height: 640)
        .onAppear { prefill() }
        .confirmationDialog("이 항목을 위시리스트에서 삭제할까요? 삭제한 항목은 복구할 수 없어요.",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                if let editing { store.deleteWishlistItem(editing) }
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func validationNote(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func prefill() {
        guard let editing else { return }
        name = editing.name
        price = editing.price
        category = editing.category
        priority = editing.priority
        if let target = editing.targetDate {
            hasTargetDate = true
            targetDate = target
        }
        purchaseURL = editing.purchaseURL
        memo = editing.memo
        status = editing.status
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, price > 0 else { return }

        var item = editing ?? WishlistItem(name: trimmedName, price: price)
        item.name = trimmedName
        item.price = price
        item.category = category
        item.priority = priority
        item.targetDate = hasTargetDate ? targetDate : nil
        item.purchaseURL = purchaseURL.trimmingCharacters(in: .whitespaces)
        item.memo = memo
        item.status = status
        if status == .purchased && item.purchasedAt == nil {
            item.purchasedAt = Date()
        }

        if editing == nil {
            store.addWishlistItem(item)
        } else {
            store.updateWishlistItem(item)
        }
        dismiss()
    }
}

// MARK: - 위시리스트 상세

struct WishlistDetail: View {
    let item: WishlistItem
    var onEdit: (WishlistItem) -> Void
    var onRequestPurchase: (WishlistItem) -> Void

    @ObservedObject private var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    /// 스토어의 최신 상태 반영 (상태 변경 후에도 갱신)
    private var current: WishlistItem {
        store.wishlistItems.first { $0.id == item.id } ?? item
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label(current.status.rawValue, systemImage: current.status.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(current.status.color)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(current.status.color.opacity(0.12))
                            .clipShape(Capsule())
                        Spacer()
                        Text(current.priority.rawValue + " 우선순위")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(current.priority.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(current.priority.color.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(current.name).font(.title2.bold())
                    Text(formatKRW(current.price)).font(.title.bold()).foregroundStyle(Theme.accent)

                    infoRow("카테고리", current.category)
                    if let target = current.targetDate {
                        infoRow("목표 구매일", DateFormat.fullDay.string(from: target))
                    }
                    if current.hasValidURL {
                        HStack {
                            Text("구매 링크").foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Link(destination: URL(string: current.purchaseURL)!) {
                                Label("상품 페이지 열기", systemImage: "link")
                            }
                        }
                        .font(.subheadline)
                    } else if !current.purchaseURL.isEmpty {
                        infoRow("구매 링크", current.purchaseURL + " (형식 오류)")
                    }
                    if !current.memo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("메모").font(.subheadline).foregroundStyle(.secondary)
                            Text(current.memo).font(.body)
                        }
                    }

                    Divider()
                    infoRow("등록일", DateFormat.day.string(from: current.createdAt))
                    infoRow("수정일", DateFormat.day.string(from: current.updatedAt))
                    if let purchased = current.purchasedAt {
                        infoRow("구매 완료일", DateFormat.day.string(from: purchased))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()

            // 액션 버튼
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button { onEdit(current) } label: {
                        Label("수정", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                    if current.status != .purchased {
                        Button { onRequestPurchase(current) } label: {
                            Label("구매 완료", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.green)
                    } else {
                        Button { store.convertWishlistItemToTransaction(current) } label: {
                            Label("거래내역에 추가", systemImage: "plus.circle").frame(maxWidth: .infinity)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { store.updateWishlistItemStatus(current, status: .paused) } label: {
                        Label("보류", systemImage: "pause.circle").frame(maxWidth: .infinity)
                    }
                    Button { store.updateWishlistItemStatus(current, status: .abandoned) } label: {
                        Label("포기", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("삭제", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                }
                Button("닫기") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(width: 440, height: 600)
        .confirmationDialog("이 항목을 위시리스트에서 삭제할까요? 삭제한 항목은 복구할 수 없어요.",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                store.deleteWishlistItem(current)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.subheadline)
    }
}
