import SwiftUI
import Foundation

// MARK: - 구독/정기결제

struct Subscription: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Int
    var cycle: Cycle = .monthly
    var anchorDate: Date = Date()        // 첫(기준) 결제일 — 이후 주기 계산의 기준점
    var category: String = "구독"
    var colorHex: String = "#AF52DE"
    var isTrial: Bool = false
    var trialEndDate: Date? = nil
    var autoRecord: Bool = true          // 결제일에 가계부 자동 기록
    var accountID: UUID? = nil
    var memo: String = ""
    var isActive: Bool = true
    var lastRecorded: Date? = nil        // 이 날짜까지의 결제는 기록 완료로 간주

    enum Cycle: String, Codable, CaseIterable, Identifiable {
        case weekly = "매주"
        case monthly = "매월"
        case yearly = "매년"

        var id: String { rawValue }

        var component: Calendar.Component {
            switch self {
            case .weekly: return .weekOfYear
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    var color: Color { Color(hexString: colorHex) ?? Theme.purple }
    var initials: String { String(name.prefix(2)) }

    /// 서비스 이름으로 번들에 포함된 로고 에셋(Resources/Logos/*.png)을 매칭. 없으면 nil.
    var logoAsset: String? {
        let n = name.lowercased()
        if n.contains("chatgpt") || n.contains("챗지피티") || n.contains("챗gpt") { return "chatgpt" }
        if n.contains("claude") || n.contains("클로드") { return "claude" }
        if n.contains("tesla") || n.contains("테슬라") { return "tesla" }
        if n.contains("coupang") || n.contains("쿠팡") { return "coupang" }
        return nil
    }

    /// 월 환산 금액
    var monthlyEquivalent: Int {
        switch cycle {
        case .weekly: return amount * 52 / 12
        case .monthly: return amount
        case .yearly: return amount / 12
        }
    }

    /// 기준일(포함) 이후 첫 결제일
    func nextBilling(onOrAfter date: Date = Date()) -> Date {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: anchorDate)
        let target = cal.startOfDay(for: date)
        if anchor >= target { return anchor }
        var k = 1
        while k <= 2400 {
            if let candidate = cal.date(byAdding: cycle.component, value: k, to: anchor),
               candidate >= target {
                return candidate
            }
            k += 1
        }
        return target
    }

    /// [start, end] 구간에 속하는 결제일 목록
    func billingDates(from start: Date, to end: Date) -> [Date] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: anchorDate)
        let lower = cal.startOfDay(for: start)
        let upper = cal.startOfDay(for: end)
        guard anchor <= upper else { return [] }
        var result: [Date] = []
        var k = 0
        while k <= 2400 {
            guard let candidate = cal.date(byAdding: cycle.component, value: k, to: anchor) else { break }
            if candidate > upper { break }
            if candidate >= lower { result.append(candidate) }
            k += 1
        }
        return result
    }
}

// MARK: - 일정/D-day

struct LifeEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var type: EventType = .general
    var repeatRule: RepeatRule = .none
    var memo: String = ""
    var isDone: Bool = false

    enum EventType: String, Codable, CaseIterable, Identifiable {
        case payment = "납부"
        case renewal = "만료·갱신"
        case appointment = "약속·예약"
        case anniversary = "생일·기념일"
        case general = "일반"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .payment: return "wonsign.circle.fill"
            case .renewal: return "arrow.triangle.2.circlepath.circle.fill"
            case .appointment: return "calendar.circle.fill"
            case .anniversary: return "gift.circle.fill"
            case .general: return "bell.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .payment: return Theme.accent
            case .renewal: return Theme.orange
            case .appointment: return Theme.teal
            case .anniversary: return Theme.pink
            case .general: return Theme.purple
            }
        }
    }

    enum RepeatRule: String, Codable, CaseIterable, Identifiable {
        case none = "반복 없음"
        case monthly = "매월"
        case yearly = "매년"

        var id: String { rawValue }
    }

    var dday: Int { daysFromToday(date) }
}

/// 오늘 기준 날짜 차이 (미래 양수, 과거 음수)
func daysFromToday(_ date: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
}

func ddayLabel(_ days: Int) -> String {
    if days == 0 { return "D-DAY" }
    return days > 0 ? "D-\(days)" : "D+\(-days)"
}

func ddayColor(_ days: Int) -> Color {
    if days < 0 { return Theme.red }
    if days == 0 { return Theme.red }
    if days <= 7 { return Theme.orange }
    return .secondary
}

// MARK: - 체크리스트

struct ChecklistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var isDone: Bool = false
}

struct Checklist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String = "checklist"
    var items: [ChecklistItem] = []
    var createdAt: Date = Date()

    var doneCount: Int { items.filter(\.isDone).count }
    var progress: Double { items.isEmpty ? 0 : Double(doneCount) / Double(items.count) }
    var isComplete: Bool { !items.isEmpty && doneCount == items.count }
}

struct ChecklistTemplate: Identifiable {
    let name: String
    let icon: String
    let items: [String]

    var id: String { name }

    func instantiate() -> Checklist {
        Checklist(name: name, icon: icon, items: items.map { ChecklistItem(text: $0) })
    }

    static let all: [ChecklistTemplate] = [
        .init(name: "이사 준비", icon: "shippingbox", items: [
            "이사업체 견적 비교", "인터넷·TV 이전 신청", "전입신고", "우편물 주소 변경",
            "가스·전기·수도 정산", "입주 청소 예약", "짐 정리·포장", "냉장고 비우기",
        ]),
        .init(name: "월말 정산", icon: "wonsign.circle", items: [
            "이번 달 지출 확인", "예산 초과 항목 점검", "구독 서비스 점검",
            "카드 대금 확인", "다음 달 예산 조정",
        ]),
        .init(name: "여행 준비", icon: "airplane", items: [
            "숙소 예약", "교통편 예약", "여행자보험 가입", "환전·카드 한도 확인",
            "짐 싸기", "집 점검 (가스·창문·전원)",
        ]),
        .init(name: "연말정산 준비", icon: "doc.text.magnifyingglass", items: [
            "간소화 자료 확인", "의료비·교육비 영수증 정리", "기부금 영수증 준비",
            "월세 세액공제 서류", "청약통장 납입증명서",
        ]),
        .init(name: "대청소", icon: "sparkles", items: [
            "냉장고 정리", "화장실 청소", "침구 세탁", "환기구·필터 청소", "분리수거",
        ]),
        .init(name: "상비약 점검", icon: "pills", items: [
            "해열진통제", "소화제", "감기약", "밴드·소독약", "연고류", "유통기한 확인",
        ]),
    ]
}

// MARK: - 응급 연락처 / 프로필

struct EmergencyContact: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var relation: String = ""
    var phone: String = ""
}

struct UserProfile: Codable, Hashable {
    var birthYear: Int? = nil
    var region: String = ""
}

// MARK: - 생활 데이터 스토어

@MainActor
final class LifeStore: ObservableObject {
    static let shared = LifeStore()

    @Published private(set) var subscriptions: [Subscription] = []
    @Published private(set) var events: [LifeEvent] = []
    @Published private(set) var checklists: [Checklist] = []
    @Published private(set) var contacts: [EmergencyContact] = []
    @Published private(set) var profile = UserProfile()

    var isEmpty: Bool {
        subscriptions.isEmpty && events.isEmpty && checklists.isEmpty && contacts.isEmpty
    }

    private struct Persisted: Codable {
        var subscriptions: [Subscription] = []
        var events: [LifeEvent] = []
        var checklists: [Checklist] = []
        var contacts: [EmergencyContact] = []
        var profile = UserProfile()
    }

    static var dataURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyAsset", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("life.json")
    }

    private init() {
        load()
        processAutoRecords()
        cleanupCompletedEvents()
    }

    // MARK: 저장/로드

    private func load() {
        guard let data = try? Data(contentsOf: Self.dataURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        subscriptions = decoded.subscriptions
        events = decoded.events
        checklists = decoded.checklists
        contacts = decoded.contacts
        profile = decoded.profile
    }

    private func persist() {
        let payload = Persisted(subscriptions: subscriptions, events: events,
                                checklists: checklists, contacts: contacts, profile: profile)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Self.dataURL, options: .atomic)
        }
    }

    func exportData() -> Data {
        let payload = Persisted(subscriptions: subscriptions, events: events,
                                checklists: checklists, contacts: contacts, profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }

    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(Persisted.self, from: data)
        subscriptions = decoded.subscriptions
        events = decoded.events
        checklists = decoded.checklists
        contacts = decoded.contacts
        profile = decoded.profile
        persist()
    }

    func resetAll() {
        subscriptions = []
        events = []
        checklists = []
        contacts = []
        profile = UserProfile()
        try? FileManager.default.removeItem(at: Self.dataURL)
        objectWillChange.send()
    }

    // MARK: 구독 CRUD

    var activeSubscriptions: [Subscription] { subscriptions.filter(\.isActive) }
    var inactiveSubscriptions: [Subscription] { subscriptions.filter { !$0.isActive } }

    var monthlySubscriptionCost: Int {
        activeSubscriptions.reduce(0) { $0 + $1.monthlyEquivalent }
    }

    func trialsEndingSoon(within days: Int = 3) -> [Subscription] {
        activeSubscriptions.filter {
            guard $0.isTrial, let end = $0.trialEndDate else { return false }
            let d = daysFromToday(end)
            return d >= 0 && d <= days
        }
    }

    func subscriptionsDueToday() -> [Subscription] {
        activeSubscriptions.filter { daysFromToday($0.nextBilling()) == 0 }
    }

    func addSubscription(_ sub: Subscription) {
        var item = sub
        // 과거 결제일 백필 방지: 등록 전날까지는 기록 완료로 간주
        if item.lastRecorded == nil {
            item.lastRecorded = Calendar.current.date(byAdding: .day, value: -1,
                                                      to: Calendar.current.startOfDay(for: Date()))
        }
        subscriptions.append(item)
        persist()
        processAutoRecords()
    }

    func updateSubscription(_ sub: Subscription) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx] = sub
        persist()
        processAutoRecords()
    }

    func deleteSubscription(_ sub: Subscription) {
        subscriptions.removeAll { $0.id == sub.id }
        persist()
    }

    func setSubscriptionActive(_ sub: Subscription, active: Bool) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        subscriptions[idx].isActive = active
        if active {
            // 재개 시 중지 기간의 결제 백필 방지
            subscriptions[idx].lastRecorded = Calendar.current.date(
                byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
        }
        persist()
        processAutoRecords()
    }

    /// 결제일이 지난 구독을 가계부 거래로 자동 기록
    func processAutoRecords() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var changed = false

        for idx in subscriptions.indices {
            let sub = subscriptions[idx]
            guard sub.isActive, sub.autoRecord else { continue }
            // 무료체험 중에는 결제 기록 없음
            if sub.isTrial, let end = sub.trialEndDate, end > Date() { continue }

            let cutoff = sub.lastRecorded.map { cal.startOfDay(for: $0) }
                ?? cal.date(byAdding: .day, value: -1, to: today)!
            guard let from = cal.date(byAdding: .day, value: 1, to: cutoff) else { continue }

            let dues = sub.billingDates(from: from, to: today)
            if dues.isEmpty {
                if sub.lastRecorded == nil {
                    subscriptions[idx].lastRecorded = today
                    changed = true
                }
                continue
            }

            for due in dues {
                DataStore.shared.addTransaction(UserTransaction(
                    date: due.addingTimeInterval(9 * 3600),
                    title: sub.name,
                    amount: -sub.amount,
                    category: sub.category,
                    accountID: sub.accountID,
                    memo: "정기결제 자동 기록"))
            }
            subscriptions[idx].lastRecorded = today
            changed = true
        }

        if changed { persist() }
    }

    // MARK: 완료 일정 자동 삭제

    /// isDone이고 날짜가 하루 이상 지난 일정을 삭제
    func cleanupCompletedEvents() {
        let before = events.count
        events.removeAll { $0.isDone && daysFromToday($0.date) < 0 }
        if events.count != before { persist() }
    }

    // MARK: 일정 CRUD

    /// 오늘이거나 지난 미완료 일정 수 (사이드바 배지용)
    var dueEventCount: Int {
        events.filter { !$0.isDone && $0.dday <= 0 }.count
    }

    func addEvent(_ event: LifeEvent) {
        events.append(event)
        events.sort { $0.date < $1.date }
        persist()
    }

    func updateEvent(_ event: LifeEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx] = event
        events.sort { $0.date < $1.date }
        persist()
    }

    func deleteEvent(_ event: LifeEvent) {
        events.removeAll { $0.id == event.id }
        persist()
    }

    /// 완료 처리 — 반복 일정은 다음 회차로 이동
    func completeEvent(_ event: LifeEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        switch event.repeatRule {
        case .none:
            events[idx].isDone = true
        case .monthly, .yearly:
            let cal = Calendar.current
            let comp: Calendar.Component = event.repeatRule == .monthly ? .month : .year
            let today = cal.startOfDay(for: Date())
            var next = events[idx].date
            var guard_ = 0
            repeat {
                next = cal.date(byAdding: comp, value: 1, to: next) ?? next.addingTimeInterval(86400)
                guard_ += 1
            } while cal.startOfDay(for: next) <= today && guard_ < 1200
            events[idx].date = next
        }
        events.sort { $0.date < $1.date }
        persist()
    }

    func restoreEvent(_ event: LifeEvent) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx].isDone = false
        persist()
    }

    // MARK: 체크리스트 CRUD

    func checklist(id: UUID) -> Checklist? {
        checklists.first { $0.id == id }
    }

    func addChecklist(_ list: Checklist) {
        checklists.insert(list, at: 0)
        persist()
    }

    func deleteChecklist(id: UUID) {
        checklists.removeAll { $0.id == id }
        persist()
    }

    func renameChecklist(id: UUID, name: String) {
        guard let idx = checklists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        checklists[idx].name = name
        persist()
    }

    func toggleItem(listID: UUID, itemID: UUID) {
        guard let li = checklists.firstIndex(where: { $0.id == listID }),
              let ii = checklists[li].items.firstIndex(where: { $0.id == itemID }) else { return }
        checklists[li].items[ii].isDone.toggle()
        persist()
    }

    func addItem(listID: UUID, text: String) {
        guard let li = checklists.firstIndex(where: { $0.id == listID }), !text.isEmpty else { return }
        checklists[li].items.append(ChecklistItem(text: text))
        persist()
    }

    func deleteItem(listID: UUID, itemID: UUID) {
        guard let li = checklists.firstIndex(where: { $0.id == listID }) else { return }
        checklists[li].items.removeAll { $0.id == itemID }
        persist()
    }

    // MARK: 응급 연락처 CRUD

    func addContact(_ contact: EmergencyContact) {
        contacts.append(contact)
        persist()
    }

    func updateContact(_ contact: EmergencyContact) {
        guard let idx = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[idx] = contact
        persist()
    }

    func deleteContact(_ contact: EmergencyContact) {
        contacts.removeAll { $0.id == contact.id }
        persist()
    }

    // MARK: 프로필

    func saveProfile(birthYear: Int?, region: String) {
        profile = UserProfile(birthYear: birthYear, region: region)
        persist()
    }

    // MARK: 데모 데이터

    func seedDemo() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

        subscriptions.append(contentsOf: [
            Subscription(name: "넷플릭스", amount: 17_000, anchorDate: days(-26),
                         colorHex: "#E50914", autoRecord: false),
            Subscription(name: "유튜브 프리미엄", amount: 14_900, anchorDate: days(-10),
                         colorHex: "#FF0000", autoRecord: false),
            Subscription(name: "쿠팡 와우", amount: 7_890, anchorDate: days(-1),
                         colorHex: "#346AFF", autoRecord: false),
            Subscription(name: "iCloud+", amount: 4_400, anchorDate: days(-28),
                         colorHex: "#3693F3", autoRecord: false),
            Subscription(name: "디즈니+", amount: 9_900, anchorDate: days(2),
                         colorHex: "#01147C", isTrial: true, trialEndDate: days(2), autoRecord: false),
            Subscription(name: "헬스장", amount: 89_000, anchorDate: days(-5),
                         category: "의료/건강", colorHex: "#34C759", autoRecord: false),
        ])

        events.append(contentsOf: [
            LifeEvent(title: "월세 납부", date: days(5), type: .payment, repeatRule: .monthly),
            LifeEvent(title: "건강검진 예약", date: days(8), type: .appointment),
            LifeEvent(title: "자동차보험 갱신", date: days(12), type: .renewal, repeatRule: .yearly),
            LifeEvent(title: "엄마 생신", date: days(20), type: .anniversary, repeatRule: .yearly),
            LifeEvent(title: "휴대폰 약정 만료", date: days(45), type: .renewal),
        ])

        var moving = ChecklistTemplate.all[0].instantiate()
        moving.items[0].isDone = true
        moving.items[1].isDone = true
        checklists.append(contentsOf: [moving, ChecklistTemplate.all[1].instantiate()])

        contacts.append(contentsOf: [
            EmergencyContact(name: "어머니", relation: "가족", phone: "010-1234-5678"),
            EmergencyContact(name: "김철수", relation: "친구", phone: "010-9876-5432"),
        ])

        persist()
    }
}
