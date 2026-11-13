import SwiftUI
import Foundation

// MARK: - 사용자 데이터 모델

struct UserAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var bank: String
    var name: String
    var accountNumber: String
    var balance: Int
    var colorHex: String
    var type: String   // 입출금 / 예적금 / 증권 / 현금

    var color: Color { Color(hexString: colorHex) ?? Theme.accent }
    var initials: String { String(bank.prefix(2)) }

    static let types = ["입출금", "예적금", "증권", "현금"]
}

struct UserTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var title: String
    var amount: Int          // 지출 음수, 수입 양수
    var category: String
    var accountID: UUID?
    var memo: String = ""
    var paymentMethod: String? = nil   // 거래수단(현대카드X / 카카오페이 머니 / 계좌명) — 가져오기 시 채워짐
}

struct UserBudget: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: String
    var limit: Int
}

// MARK: - 위시리스트 모델

enum WishlistPriority: String, Codable, CaseIterable, Identifiable {
    case low = "낮음"
    case medium = "보통"
    case high = "높음"

    var id: String { rawValue }

    /// 정렬용 가중치 (높음이 큼)
    var weight: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var color: Color {
        switch self {
        case .low: return Theme.teal
        case .medium: return Theme.accent
        case .high: return Theme.red
        }
    }
}

enum WishlistStatus: String, Codable, CaseIterable, Identifiable {
    case considering = "고민 중"
    case wanted = "사고 싶음"
    case planned = "구매 예정"
    case purchased = "구매 완료"
    case paused = "보류"
    case abandoned = "포기"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .considering: return Theme.yellow
        case .wanted: return Theme.purple
        case .planned: return Theme.accent
        case .purchased: return Theme.green
        case .paused: return .gray
        case .abandoned: return Theme.red
        }
    }

    var icon: String {
        switch self {
        case .considering: return "questionmark.circle"
        case .wanted: return "heart"
        case .planned: return "cart"
        case .purchased: return "checkmark.circle.fill"
        case .paused: return "pause.circle"
        case .abandoned: return "xmark.circle"
        }
    }
}

struct WishlistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var price: Int                 // 예상 가격 (원)
    var category: String = "기타"
    var priority: WishlistPriority = .medium
    var targetDate: Date?
    var purchaseURL: String = ""
    var memo: String = ""
    var status: WishlistStatus = .wanted
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var purchasedAt: Date?

    /// 구매 링크가 유효한 형식인지
    var hasValidURL: Bool {
        let trimmed = purchaseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    /// 카테고리 목록 (위시리스트 전용)
    static let categories = [
        "전자기기", "의류", "생활용품", "가구", "취미",
        "여행", "선물", "건강", "기타",
    ]

    static func categoryColor(for name: String) -> Color {
        switch name {
        case "전자기기": return Theme.accent
        case "의류": return Theme.purple
        case "생활용품": return Theme.teal
        case "가구": return Color(hex: 0xA2845E)
        case "취미": return Theme.pink
        case "여행": return Theme.orange
        case "선물": return Theme.yellow
        case "건강": return Theme.green
        default: return .gray
        }
    }
}

// MARK: - 카테고리

struct SpendCategory: Identifiable, Hashable {
    let name: String
    let colorHex: String
    var id: String { name }
    var color: Color { Color(hexString: colorHex) ?? .gray }

    static let all: [SpendCategory] = [
        .init(name: "식비", colorHex: "#FF9500"),
        .init(name: "카페/간식", colorHex: "#A2845E"),
        .init(name: "쇼핑", colorHex: "#5856D6"),
        .init(name: "교통", colorHex: "#FF3B30"),
        .init(name: "주거/통신", colorHex: "#007AFF"),
        .init(name: "구독", colorHex: "#AF52DE"),
        .init(name: "의료/건강", colorHex: "#30B0C7"),
        .init(name: "여가/문화", colorHex: "#FF2D55"),
        .init(name: "교육", colorHex: "#5AC8FA"),
        .init(name: "경조사/선물", colorHex: "#FFCC00"),
        .init(name: "저축", colorHex: "#30B0C7"),
        .init(name: "수입", colorHex: "#34C759"),
        .init(name: "이체", colorHex: "#8E8E93"),
        .init(name: "기타", colorHex: "#98989D"),
    ]

    static func color(for name: String) -> Color {
        all.first { $0.name == name }?.color ?? .gray
    }

    static var expenseNames: [String] {
        all.map(\.name).filter { $0 != "수입" }
    }
}

// MARK: - 자동 카테고리 분류

enum AutoCategory {
    static let rules: [(keywords: [String], category: String)] = [
        (["스타벅스", "투썸", "이디야", "메가커피", "컴포즈", "커피", "카페", "배스킨", "베스킨", "파리바게뜨", "뚜레쥬르", "던킨"], "카페/간식"),
        (["넷플릭스", "유튜브", "멜론", "스포티파이", "디즈니", "왓챠", "애플", "티빙", "쿠팡플레이", "구독"], "구독"),
        (["쿠팡", "지마켓", "11번가", "옥션", "무신사", "올리브영", "다이소", "네이버페이", "SSG", "위메프"], "쇼핑"),
        (["지하철", "버스", "택시", "카카오T", "코레일", "SRT", "KTX", "주유", "충전", "하이패스", "주차"], "교통"),
        (["GS25", "CU", "세븐일레븐", "이마트24", "편의점", "이마트", "홈플러스", "롯데마트", "컬리", "배달의민족", "배민", "요기요", "쿠팡이츠", "맥도날드", "버거킹", "롯데리아", "김밥", "식당"], "식비"),
        (["통신", "SKT", "LG유플러스", "KT", "관리비", "월세", "전세", "전기", "가스", "수도", "인터넷"], "주거/통신"),
        (["병원", "약국", "의원", "치과", "한의원", "검진"], "의료/건강"),
        (["CGV", "메가박스", "롯데시네마", "영화", "스팀", "PC방", "노래방", "콘서트", "공연"], "여가/문화"),
        (["학원", "인강", "교재", "수강", "강의"], "교육"),
        (["축의", "조의", "부조", "선물"], "경조사/선물"),
        (["급여", "월급", "상여", "성과급", "이자", "배당", "환급"], "수입"),
        (["이체", "송금"], "이체"),
    ]

    static func categorize(_ text: String, amount: Int) -> String {
        for rule in rules where rule.keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return rule.category
        }
        return amount > 0 ? "수입" : "기타"
    }
}

// MARK: - 파일 시스템 감시

private final class FileSystemWatcher {
    private let url: URL
    private let queue: DispatchQueue
    private let handler: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var isStopped = false

    init(url: URL, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.handler = handler
        arm()
    }

    /// 파일을 열고 감시 시작. `.atomic` 저장(rename/delete)으로 inode가 교체되면
    /// 기존 fd가 무효화되므로, 그 이벤트를 받으면 소스를 닫고 새 inode에 다시 건다.
    private func arm() {
        if isStopped { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 파일이 잠깐 사라진 경우(교체 직후 등) 짧게 대기 후 재시도
            queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.arm() }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self, let s = self.source else { return }
            let flags = s.data
            self.handler()
            // inode가 교체된 경우 현재 소스를 취소 → cancelHandler에서 재무장
            if flags.contains(.rename) || flags.contains(.delete) {
                s.cancel()
            }
        }
        src.setCancelHandler { [weak self] in
            close(fd)
            guard let self, !self.isStopped else { return }
            self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
        }
        self.source = src
        src.resume()
    }

    deinit {
        isStopped = true
        source?.cancel()
    }
}

// MARK: - 데이터 스토어

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published private(set) var accounts: [UserAccount] = []
    @Published private(set) var transactions: [UserTransaction] = []   // 최신순 정렬 유지
    @Published private(set) var budgets: [UserBudget] = []
    @Published private(set) var wishlistItems: [WishlistItem] = []     // 최근 등록순(최신 먼저) 유지
    @Published private(set) var snapshots: [String: Int] = [:]         // "yyyy-MM" → 해당 월 총자산

    /// 외부(Claude 등)가 data.json을 업데이트했을 때 세팅 → 배너 표시용
    @Published var externalUpdateInfo: ExternalUpdateInfo? = nil

    struct ExternalUpdateInfo {
        let addedCount: Int
        let at: Date
    }

    var isEmpty: Bool { accounts.isEmpty && transactions.isEmpty }
    var totalAssets: Int { accounts.reduce(0) { $0 + $1.balance } }

    private struct Persisted: Codable {
        var accounts: [UserAccount] = []
        var transactions: [UserTransaction] = []
        var budgets: [UserBudget] = []
        var wishlistItems: [WishlistItem] = []
        var snapshots: [String: Int] = [:]

        init(accounts: [UserAccount] = [], transactions: [UserTransaction] = [],
             budgets: [UserBudget] = [], wishlistItems: [WishlistItem] = [],
             snapshots: [String: Int] = [:]) {
            self.accounts = accounts
            self.transactions = transactions
            self.budgets = budgets
            self.wishlistItems = wishlistItems
            self.snapshots = snapshots
        }

        // 구버전 data.json(위시리스트 키 없음)과의 호환을 위해 누락 키는 기본값 사용
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accounts = try c.decodeIfPresent([UserAccount].self, forKey: .accounts) ?? []
            transactions = try c.decodeIfPresent([UserTransaction].self, forKey: .transactions) ?? []
            budgets = try c.decodeIfPresent([UserBudget].self, forKey: .budgets) ?? []
            wishlistItems = try c.decodeIfPresent([WishlistItem].self, forKey: .wishlistItems) ?? []
            snapshots = try c.decodeIfPresent([String: Int].self, forKey: .snapshots) ?? [:]
        }
    }

    static var dataURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyAsset", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    /// persist() 호출 중일 때 true → 파일 감시 콜백 무시
    private var isSaving = false
    private var fileWatcher: FileSystemWatcher?

    private init() {
        load()
        persist()   // 이번 달 스냅샷 갱신
        setupFileWatcher()
    }

    // MARK: 파일 감시

    private func setupFileWatcher() {
        fileWatcher = FileSystemWatcher(url: Self.dataURL) { [weak self] in
            // .atomic 쓰기는 rename 이벤트를 연속으로 두 번 보낼 수 있어 debounce
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !self.isSaving else { return }
                let before = self.transactions.count
                self.load()
                let added = self.transactions.count - before
                if added > 0 {
                    self.externalUpdateInfo = ExternalUpdateInfo(addedCount: added, at: Date())
                }
            }
        }
    }

    func dismissExternalUpdate() {
        externalUpdateInfo = nil
    }

    // MARK: 저장/로드

    private func load() {
        guard let data = try? Data(contentsOf: Self.dataURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        accounts = decoded.accounts
        transactions = decoded.transactions.sorted { $0.date > $1.date }
        budgets = decoded.budgets
        wishlistItems = decoded.wishlistItems.sorted { $0.createdAt > $1.createdAt }
        snapshots = decoded.snapshots
    }

    private func persist() {
        isSaving = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isSaving = false }
        }
        snapshots[DateFormat.monthKey.string(from: Date())] = totalAssets
        let payload = Persisted(accounts: accounts, transactions: transactions, budgets: budgets, wishlistItems: wishlistItems, snapshots: snapshots)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Self.dataURL, options: .atomic)
        }
    }

    func exportData() -> Data {
        let payload = Persisted(accounts: accounts, transactions: transactions, budgets: budgets, wishlistItems: wishlistItems, snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }

    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(Persisted.self, from: data)
        accounts = decoded.accounts
        transactions = decoded.transactions.sorted { $0.date > $1.date }
        budgets = decoded.budgets
        wishlistItems = decoded.wishlistItems.sorted { $0.createdAt > $1.createdAt }
        snapshots = decoded.snapshots
        persist()
    }

    // MARK: 계좌 CRUD

    func addAccount(_ account: UserAccount) {
        accounts.append(account)
        persist()
    }

    func updateAccount(_ account: UserAccount) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        persist()
    }

    func deleteAccount(_ account: UserAccount) {
        accounts.removeAll { $0.id == account.id }
        // 거래는 보존하되 계좌 연결만 해제
        for idx in transactions.indices where transactions[idx].accountID == account.id {
            transactions[idx].accountID = nil
        }
        persist()
    }

    // MARK: 거래 CRUD

    func addTransaction(_ tx: UserTransaction) {
        transactions.append(tx)
        transactions.sort { $0.date > $1.date }
        applyBalanceDelta(accountID: tx.accountID, delta: tx.amount)
        persist()
    }

    func updateTransaction(_ tx: UserTransaction) {
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        let old = transactions[idx]
        applyBalanceDelta(accountID: old.accountID, delta: -old.amount)
        transactions[idx] = tx
        transactions.sort { $0.date > $1.date }
        applyBalanceDelta(accountID: tx.accountID, delta: tx.amount)
        persist()
    }

    func deleteTransaction(_ tx: UserTransaction) {
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        applyBalanceDelta(accountID: tx.accountID, delta: -tx.amount)
        transactions.remove(at: idx)
        persist()
    }

    private func applyBalanceDelta(accountID: UUID?, delta: Int) {
        guard let accountID, let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[idx].balance += delta
    }

    // MARK: 예산 CRUD

    func addBudget(_ budget: UserBudget) {
        budgets.append(budget)
        persist()
    }

    func updateBudget(_ budget: UserBudget) {
        guard let idx = budgets.firstIndex(where: { $0.id == budget.id }) else { return }
        budgets[idx] = budget
        persist()
    }

    func deleteBudget(_ budget: UserBudget) {
        budgets.removeAll { $0.id == budget.id }
        persist()
    }

    // MARK: 위시리스트 CRUD

    func addWishlistItem(_ item: WishlistItem) {
        var item = item
        item.createdAt = Date()
        item.updatedAt = item.createdAt
        wishlistItems.insert(item, at: 0)
        persist()
    }

    func updateWishlistItem(_ item: WishlistItem) {
        guard let idx = wishlistItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()
        wishlistItems[idx] = updated
        persist()
    }

    func deleteWishlistItem(_ item: WishlistItem) {
        wishlistItems.removeAll { $0.id == item.id }
        persist()
    }

    func updateWishlistItemStatus(_ item: WishlistItem, status: WishlistStatus) {
        guard let idx = wishlistItems.firstIndex(where: { $0.id == item.id }) else { return }
        wishlistItems[idx].status = status
        wishlistItems[idx].updatedAt = Date()
        if status == .purchased {
            wishlistItems[idx].purchasedAt = Date()
        } else {
            wishlistItems[idx].purchasedAt = nil
        }
        persist()
    }

    /// 구매 완료 처리 (구매일 기록)
    func markWishlistItemAsPurchased(_ item: WishlistItem) {
        updateWishlistItemStatus(item, status: .purchased)
    }

    /// 위시리스트 항목을 지출 거래로 추가. 항목은 구매 완료 처리됨.
    func convertWishlistItemToTransaction(_ item: WishlistItem, accountID: UUID? = nil) {
        let date = item.purchasedAt ?? Date()
        // 위시리스트 카테고리를 거래내역 카테고리로 매핑 (없으면 기타)
        let category = SpendCategory.all.contains { $0.name == item.category } ? item.category : "쇼핑"
        let tx = UserTransaction(
            date: date,
            title: item.name,
            amount: -abs(item.price),
            category: category,
            accountID: accountID,
            memo: "위시리스트에서 추가됨")
        addTransaction(tx)
        markWishlistItemAsPurchased(item)
    }

    // MARK: 위시리스트 통계

    var wishlistTotal: Int { wishlistItems.reduce(0) { $0 + $1.price } }

    /// 구매 예정(고민 중·사고 싶음·구매 예정) 금액
    var wishlistPlannedTotal: Int {
        wishlistItems
            .filter { [.considering, .wanted, .planned].contains($0.status) }
            .reduce(0) { $0 + $1.price }
    }

    var wishlistPurchasedTotal: Int {
        wishlistItems.filter { $0.status == .purchased }.reduce(0) { $0 + $1.price }
    }

    var wishlistHighPriorityCount: Int {
        wishlistItems.filter { $0.priority == .high && $0.status != .purchased && $0.status != .abandoned }.count
    }

    /// 구매 예정 상태 항목 (대시보드용)
    var wishlistActiveItems: [WishlistItem] {
        wishlistItems.filter { [.considering, .wanted, .planned].contains($0.status) }
    }

    // MARK: 통계

    func transactions(inMonth anchor: Date) -> [UserTransaction] {
        let key = DateFormat.monthKey.string(from: anchor)
        return transactions.filter { DateFormat.monthKey.string(from: $0.date) == key }
    }

    func income(inMonth anchor: Date) -> Int {
        transactions(inMonth: anchor)
            .filter { $0.amount > 0 && $0.category != "이체" }
            .reduce(0) { $0 + $1.amount }
    }

    func expense(inMonth anchor: Date) -> Int {
        // 저축은 지출이 아니므로 총 지출 계산에서 제외 (카테고리별 내역에는 유지)
        transactions(inMonth: anchor)
            .filter { $0.amount < 0 && $0.category != "이체" && $0.category != "저축" }
            .reduce(0) { $0 - $1.amount }
    }

    /// 특정 결제수단의 월 지출 합계(절댓값). 예: 현대카드X 실적 계산용
    func cardSpending(_ method: String, inMonth anchor: Date) -> Int {
        transactions(inMonth: anchor)
            .filter { $0.amount < 0 && $0.paymentMethod == method }
            .reduce(0) { $0 - $1.amount }
    }

    func spendingByCategory(inMonth anchor: Date) -> [(category: String, amount: Int)] {
        let spends = transactions(inMonth: anchor).filter { $0.amount < 0 && $0.category != "이체" }
        let grouped = Dictionary(grouping: spends, by: \.category)
            .mapValues { $0.reduce(0) { $0 - $1.amount } }
        return grouped.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    func spent(category: String, inMonth anchor: Date) -> Int {
        transactions(inMonth: anchor)
            .filter { $0.category == category && $0.amount < 0 }
            .reduce(0) { $0 - $1.amount }
    }

    /// 최근 n개월 (과거 → 현재 순) 지출 합계
    func monthlyExpenses(months: Int, endingAt anchor: Date = Date()) -> [(label: String, amount: Int)] {
        let calendar = Calendar.current
        return (0..<months).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: anchor) else { return nil }
            let label = "\(calendar.component(.month, from: month))월"
            return (label, expense(inMonth: month))
        }
    }

    /// 자산 추이 (월별 스냅샷, 과거 → 현재)
    var assetTrend: [(label: String, amount: Int)] {
        snapshots.sorted { $0.key < $1.key }
            .suffix(6)
            .map { key, value in
                let month = Int(key.suffix(2)) ?? 0
                return ("\(month)월", value)
            }
    }

    // MARK: 전체 초기화 / 데모

    func resetAll() {
        accounts = []
        transactions = []
        budgets = []
        wishlistItems = []
        snapshots = [:]
        try? FileManager.default.removeItem(at: Self.dataURL)
        objectWillChange.send()
    }

    func seedDemo() {
        let kb = UserAccount(bank: "KB국민은행", name: "직장인 우대통장", accountNumber: "110-***-***123",
                             balance: 8_540_000, colorHex: "#FFBC00", type: "입출금")
        let kakao = UserAccount(bank: "카카오뱅크", name: "세이프박스", accountNumber: "3333-**-***789",
                                balance: 15_000_000, colorHex: "#FFCC00", type: "예적금")
        let toss = UserAccount(bank: "토스뱅크", name: "모임통장", accountNumber: "100-***-***456",
                               balance: 1_200_000, colorHex: "#007AFF", type: "입출금")
        accounts.append(contentsOf: [kb, kakao, toss])

        let calendar = Calendar.current
        let today = Date()
        func daysAgo(_ n: Int, hour: Int = 12) -> Date {
            calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: today))!
                .addingTimeInterval(TimeInterval(hour * 3600))
        }

        var txs: [UserTransaction] = []

        // 월 단위 반복 (급여, 고정비) — 최근 3개월
        for m in 0..<3 {
            let base = m * 30
            txs.append(UserTransaction(date: daysAgo(base + 2, hour: 10), title: "급여", amount: 3_500_000, category: "수입", accountID: kb.id))
            txs.append(UserTransaction(date: daysAgo(base + 5, hour: 9), title: "월세", amount: -650_000, category: "주거/통신", accountID: kb.id))
            txs.append(UserTransaction(date: daysAgo(base + 6, hour: 9), title: "통신비 (SKT)", amount: -55_000, category: "주거/통신", accountID: kb.id))
            txs.append(UserTransaction(date: daysAgo(base + 8, hour: 14), title: "넷플릭스", amount: -13_500, category: "구독", accountID: kb.id))
            txs.append(UserTransaction(date: daysAgo(base + 3, hour: 20), title: "세이프박스 저축", amount: -500_000, category: "이체", accountID: kb.id))
        }

        // 일상 지출 패턴 (최근 30일)
        let daily: [(Int, String, Int, String)] = [
            (0, "스타벅스 강남점", -6_100, "카페/간식"),
            (1, "쿠팡 로켓배송", -38_900, "쇼핑"),
            (1, "GS25 편의점", -4_500, "식비"),
            (2, "배달의민족", -23_000, "식비"),
            (3, "지하철 교통카드 충전", -30_000, "교통"),
            (4, "올리브영", -27_400, "쇼핑"),
            (5, "김밥천국", -9_000, "식비"),
            (6, "CGV 영화", -15_000, "여가/문화"),
            (7, "이마트", -84_300, "식비"),
            (8, "메가커피", -3_800, "카페/간식"),
            (9, "택시", -12_400, "교통"),
            (11, "약국", -8_900, "의료/건강"),
            (13, "배달의민족", -19_500, "식비"),
            (14, "무신사", -69_000, "쇼핑"),
            (16, "스타벅스", -11_000, "카페/간식"),
            (18, "홈플러스", -56_700, "식비"),
            (20, "유튜브 프리미엄", -14_900, "구독"),
            (22, "친구 결혼식 축의금", -100_000, "경조사/선물"),
            (24, "버스", -1_500, "교통"),
            (26, "교보문고", -32_000, "교육"),
            (28, "당근마켓 판매", 45_000, "수입"),
        ]
        for (day, title, amount, category) in daily {
            txs.append(UserTransaction(date: daysAgo(day, hour: 13 + day % 8), title: title, amount: amount, category: category, accountID: kb.id))
        }

        transactions.append(contentsOf: txs)
        transactions.sort { $0.date > $1.date }

        budgets.append(contentsOf: [
            UserBudget(category: "식비", limit: 400_000),
            UserBudget(category: "카페/간식", limit: 60_000),
            UserBudget(category: "쇼핑", limit: 200_000),
            UserBudget(category: "교통", limit: 100_000),
        ])

        // 자산 추이 스냅샷 (데모)
        for offset in (1...5).reversed() {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: today) else { continue }
            let key = DateFormat.monthKey.string(from: month)
            snapshots[key] = totalAssets - offset * 800_000 - (offset % 2 == 0 ? 350_000 : -150_000)
        }

        persist()
    }

}
