import SwiftUI
import Charts

struct DashboardView: View {
    @Binding var selection: Screen

    @ObservedObject private var store = DataStore.shared
    @ObservedObject private var life = LifeStore.shared
    @ObservedObject private var greetingStore = OllamaGreetingStore.shared
    @ObservedObject private var weatherStore = WeatherStore.shared

    @State private var showImportReview = false

    private var expense: Int { store.expense(inMonth: Date()) }
    private var spending: [(category: String, amount: Int)] { store.spendingByCategory(inMonth: Date()) }

    var body: some View {
        Group {
            if store.isEmpty && life.isEmpty {
                OnboardingView()
            } else {
                dashboard
            }
        }
        .onAppear {
            life.processAutoRecords()
            life.cleanupCompletedEvents()
            Task { await greetingStore.refresh(context: greetingContext) }
        }
        .onChange(of: weatherStore.weather?.updatedAt) { _, _ in
            Task { await greetingStore.refresh(context: greetingContext) }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                alertBanners
                summaryRow

                HStack(alignment: .top, spacing: 20) {
                    upcomingCard.frame(maxWidth: .infinity)
                    todoCard.frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 20) {
                    spendingCard.frame(width: 340)
                    recentCard.frame(maxWidth: .infinity)
                }

                if !store.wishlistItems.isEmpty {
                    wishlistCard
                }

                if !store.budgets.isEmpty {
                    budgetStrip
                }
            }
            .padding(28)
        }
    }

    // MARK: 위시리스트 요약

    private var wishlistCard: some View {
        let active = store.wishlistActiveItems
        let topPriority = active.sorted { $0.priority.weight > $1.priority.weight }.first
        let cal = Calendar.current
        let thisMonth = active.filter {
            guard let target = $0.targetDate else { return false }
            return cal.isDate(target, equalTo: Date(), toGranularity: .month)
        }
        let thisMonthTotal = thisMonth.reduce(0) { $0 + $1.price }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.text.square").foregroundStyle(Theme.pink)
                Text("위시리스트").font(.headline)
                Spacer()
                Button("전체 보기") { selection = .wishlist }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("구매 예정 항목이 \(active.count)개 있어요.")
                        .font(.subheadline.weight(.medium))
                    if thisMonthTotal > 0 {
                        Text("이번 달 구매 예정 금액은 \(formatKRW(thisMonthTotal))이에요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let top = topPriority {
                        Text("가장 우선순위가 높은 항목은 \(top.name)예요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("전체 예상 금액").font(.caption).foregroundStyle(.secondary)
                    Text(formatKRW(store.wishlistPlannedTotal))
                        .font(.title3.bold()).foregroundStyle(Theme.pink)
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 헤더

    private var staticGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "좋은 아침이에요 👋"
        case 11..<17: return "좋은 오후예요 👋"
        case 17..<22: return "좋은 저녁이에요 👋"
        default: return "늦은 밤이네요 🌙"
        }
    }

    private var greetingContext: OllamaGreetingStore.Context {
        let cal = Calendar.current
        let weekdays = ["", "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
        let weekday = weekdays[cal.component(.weekday, from: Date())]
        let currentHour = cal.component(.hour, from: Date())

        // 일정
        let pendingEvents = life.events.filter { !$0.isDone }
        let todayTitles = pendingEvents.filter { $0.dday == 0 }.map(\.title)
        let tomorrowTitles = pendingEvents.filter { $0.dday == 1 }.map(\.title)
        let upcoming = pendingEvents
            .filter { $0.dday > 1 && $0.dday <= 7 }
            .sorted { $0.dday < $1.dday }
            .prefix(3)
            .map { (title: $0.title, daysLeft: $0.dday) }

        // 구독 결제
        let dueToday = life.subscriptionsDueToday()
        let dueSoon = life.activeSubscriptions
            .map { (sub: $0, days: daysFromToday($0.nextBilling())) }
            .filter { $0.days > 0 && $0.days <= 3 }
            .sorted { $0.days < $1.days }
            .prefix(2)
            .map { (name: $0.sub.name, daysLeft: $0.days) }

        // 예산
        let overBudgets = store.budgets
            .filter { store.spent(category: $0.category, inMonth: Date()) > $0.limit }
            .map(\.category)

        // 체크리스트
        let activeLists = life.checklists.filter { !$0.isComplete }
        let checklistNames = activeLists.map(\.name)
        let pendingItems = activeLists
            .flatMap { list in list.items.filter { !$0.isDone }.prefix(2).map(\.text) }
            .prefix(3)
            .map { String($0) }

        // 날씨
        var weatherToday: String? = nil
        var weatherTomorrow: String? = nil
        var rainHours: [String] = []

        if let w = weatherStore.weather {
            let t = w.today
            var todayStr = "\(t.condition) 최고 \(t.tempHigh)도 최저 \(t.tempLow)도"
            if let desc = t.description, !desc.isEmpty { todayStr += " (\(desc))" }
            weatherToday = todayStr

            // 내일 날씨
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let tomorrowStr = fmt.string(from: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            if let tmrw = w.weekly.first(where: { $0.date == tomorrowStr }) {
                weatherTomorrow = "\(tmrw.condition) 최고 \(tmrw.tempHigh)도 최저 \(tmrw.tempLow)도"
            }

            // 향후 시간대 중 비 예보
            let rainConditions = ["비", "소나기", "천둥번개"]
            rainHours = w.hourly.compactMap { h -> String? in
                let parts = h.time.split(separator: ":").compactMap { Int($0) }
                guard let hr = parts.first, hr > currentHour else { return nil }
                let isRain = rainConditions.contains(where: { h.condition.contains($0) })
                               || h.precipProbability >= 50
                guard isRain else { return nil }
                if hr < 12 { return "오전 \(hr)시" }
                else if hr == 12 { return "낮 12시" }
                else { return "오후 \(hr - 12)시" }
            }
        }

        return OllamaGreetingStore.Context(
            hour: currentHour,
            weekday: weekday,
            todayEventTitles: todayTitles,
            tomorrowEventTitles: tomorrowTitles,
            upcomingEvents: Array(upcoming),
            subscriptionsDueToday: dueToday.map { (name: $0.name, amount: $0.amount) },
            subscriptionsDueSoon: Array(dueSoon),
            overBudgetCategories: overBudgets,
            activeChecklists: checklistNames,
            pendingChecklistItems: Array(pendingItems),
            weatherToday: weatherToday,
            weatherTomorrow: weatherTomorrow,
            rainExpectedHours: rainHours
        )
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormat.fullDay.string(from: Date()))
                    .font(.subheadline).foregroundStyle(.secondary)
                let hour = Calendar.current.component(.hour, from: Date())
                let emoji = OllamaGreetingStore.emoji(for: hour)
                let displayText = greetingStore.aiGreeting.map { "\(emoji) \($0)" } ?? staticGreeting
                Text(displayText)
                    .font(.largeTitle.bold())
                    .animation(.easeInOut(duration: 0.5), value: greetingStore.aiGreeting)
            }
            Spacer()
            if greetingStore.isGenerating {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse)
            }
        }
    }

    // MARK: 알림 배너

    private struct AlertItem: Identifiable {
        let id: String
        let icon: String
        let text: String
        let color: Color
        let target: Screen
    }

    private var alerts: [AlertItem] {
        var items: [AlertItem] = []

        let due = life.events.filter { !$0.isDone && $0.dday <= 0 }
        if !due.isEmpty {
            let overdueCount = due.filter { $0.dday < 0 }.count
            let text = overdueCount > 0
                ? "확인이 필요한 일정 \(due.count)건 (지난 일정 \(overdueCount)건 포함)"
                : "오늘 일정 \(due.count)건이 있어요"
            items.append(AlertItem(id: "events", icon: "calendar.badge.exclamationmark",
                                   text: text, color: Theme.orange, target: .events))
        }

        if let trial = life.trialsEndingSoon(within: 3).first {
            let d = daysFromToday(trial.trialEndDate ?? Date())
            items.append(AlertItem(id: "trial", icon: "exclamationmark.triangle.fill",
                                   text: "\(trial.name) 무료체험이 \(ddayLabel(d)) 종료 — 해지 여부를 결정하세요",
                                   color: Theme.red, target: .subscriptions))
        }

        let dueToday = life.subscriptionsDueToday()
        if !dueToday.isEmpty {
            let total = dueToday.reduce(0) { $0 + $1.amount }
            items.append(AlertItem(id: "payments", icon: "creditcard.fill",
                                   text: "오늘 정기결제 \(dueToday.count)건 · 합계 \(formatKRW(total))",
                                   color: Theme.purple, target: .subscriptions))
        }

        let overBudgets = store.budgets.filter { store.spent(category: $0.category, inMonth: Date()) > $0.limit }
        if let first = overBudgets.first {
            let text = overBudgets.count == 1
                ? "\(first.category) 예산을 초과했어요"
                : "\(first.category) 외 \(overBudgets.count - 1)개 카테고리가 예산을 초과했어요"
            items.append(AlertItem(id: "budget", icon: "chart.bar.fill",
                                   text: text, color: Theme.red, target: .analysis))
        }

        return Array(items.prefix(3))
    }

    @ViewBuilder
    private var alertBanners: some View {
        VStack(spacing: 8) {
            // 외부 업데이트 배너 (Claude가 data.json을 수정했을 때)
            if let info = store.externalUpdateInfo {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("거래내역 \(info.addedCount)건이 새로 업데이트되었습니다 — 내역을 확인하고 수정하세요")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("검토") {
                        showImportReview = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    Button {
                        store.dismissExternalUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Theme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .sheet(isPresented: $showImportReview) {
                    ImportReviewView()
                }
            }

            if !alerts.isEmpty {
                ForEach(alerts) { alert in
                    Button {
                        selection = alert.target
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: alert.icon).foregroundStyle(alert.color)
                            Text(alert.text).font(.caption.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(alert.color.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 요약 카드

    private var summaryRow: some View {
        HStack(spacing: 16) {
            summaryCard(title: "이번 달 지출", value: formatKRW(expense),
                        sub: nil, icon: "arrow.up.right.circle.fill", tint: Theme.red, target: .analysis)
            summaryCard(title: "월 고정지출", value: formatKRW(life.monthlySubscriptionCost),
                        sub: "구독 \(life.activeSubscriptions.count)개", icon: "arrow.triangle.2.circlepath.circle.fill",
                        tint: Theme.purple, target: .subscriptions)
        }
    }

    private func summaryCard(title: String, value: String, sub: String?, icon: String, tint: Color, target: Screen) -> some View {
        Button {
            selection = target
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(.primary)
                Text(sub ?? " ").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: 다가오는 일정·결제

    private struct Upcoming: Identifiable {
        let id: String
        let date: Date
        let title: String
        let subtitle: String
        let amount: Int?
        let color: Color
        let icon: String
    }

    private var upcomingItems: [Upcoming] {
        var items: [Upcoming] = []

        for event in life.events where !event.isDone {
            let d = event.dday
            guard d >= -7, d <= 30 else { continue }
            items.append(Upcoming(id: "ev-\(event.id)", date: event.date, title: event.title,
                                  subtitle: event.type.rawValue, amount: nil,
                                  color: event.type.color, icon: event.type.icon))
        }

        for sub in life.activeSubscriptions {
            let next = sub.nextBilling()
            guard daysFromToday(next) <= 30 else { continue }
            items.append(Upcoming(id: "sub-\(sub.id)", date: next, title: sub.name,
                                  subtitle: "정기결제 · \(sub.cycle.rawValue)", amount: sub.amount,
                                  color: sub.color, icon: "arrow.triangle.2.circlepath.circle.fill"))
        }

        return items.sorted { $0.date < $1.date }
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("다가오는 일정·결제").font(.headline)
                Spacer()
                Button("전체 보기") { selection = .events }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            if upcomingItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("30일 내 예정된 일정·결제가 없습니다.").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("일정 추가") { selection = .events }.controlSize(.small)
                        Button("구독 추가") { selection = .subscriptions }.controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingItems.prefix(6).enumerated()), id: \.element.id) { idx, item in
                        let d = daysFromToday(item.date)
                        HStack(spacing: 12) {
                            Text(ddayLabel(d))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ddayColor(d))
                                .frame(width: 52)
                                .padding(.vertical, 3)
                                .background(ddayColor(d).opacity(0.1))
                                .clipShape(Capsule())
                            Image(systemName: item.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(item.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("\(DateFormat.dayLabel.string(from: item.date)) · \(item.subtitle)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let amount = item.amount {
                                Text(formatKRW(amount)).font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 9)
                        if idx != min(upcomingItems.count, 6) - 1 { Divider() }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 이번 달 지출

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("이번 달 지출").font(.headline)
                Spacer()
                Button("분석 보기") { selection = .analysis }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            if spending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("이번 달 지출 내역이 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                ZStack {
                    Chart(spending, id: \.category) { item in
                        SectorMark(angle: .value("금액", item.amount), innerRadius: .ratio(0.68), angularInset: 1.5)
                            .foregroundStyle(SpendCategory.color(for: item.category))
                            .cornerRadius(3)
                    }
                    VStack(spacing: 2) {
                        Text("총 지출").font(.caption2).foregroundStyle(.secondary)
                        Text(formatKRWCompact(expense)).font(.headline.bold())
                    }
                }
                .frame(height: 150)

                VStack(spacing: 8) {
                    ForEach(spending.prefix(5), id: \.category) { item in
                        HStack {
                            CategoryDot(category: item.category)
                            Text(item.category).font(.subheadline)
                            Spacer()
                            Text(formatKRWCompact(item.amount)).font(.subheadline.weight(.semibold))
                            Text("\(expense > 0 ? Int(Double(item.amount) / Double(expense) * 100) : 0)%")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 최근 거래

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 거래").font(.headline)
                Spacer()
                Button("전체 보기") { selection = .transactions }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            if store.transactions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("거래내역 탭에서 첫 거래를 기록해보세요.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.transactions.prefix(6).enumerated()), id: \.element.id) { idx, tx in
                        HStack {
                            CategoryDot(category: tx.category)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tx.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(DateFormat.dayLabel.string(from: tx.date))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((tx.amount > 0 ? "+" : "") + formatKRW(tx.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tx.amount > 0 ? Theme.green : .primary)
                        }
                        .padding(.vertical, 9)
                        if idx != min(store.transactions.count, 6) - 1 { Divider() }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 할 일

    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("할 일").font(.headline)
                Spacer()
                Button("전체 보기") { selection = .checklists }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }

            let active = life.checklists.filter { !$0.isComplete }
            if active.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("진행 중인 체크리스트가 없습니다.").font(.caption).foregroundStyle(.secondary)
                    Button("체크리스트 만들기") { selection = .checklists }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(active.prefix(2)) { list in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Image(systemName: list.icon).font(.caption).foregroundStyle(Theme.accent)
                                Text(list.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(list.doneCount)/\(list.items.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: list.progress).tint(Theme.accent)
                            ForEach(list.items.filter { !$0.isDone }.prefix(2)) { item in
                                Button {
                                    life.toggleItem(listID: list.id, itemID: item.id)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "circle").font(.caption).foregroundStyle(.tertiary)
                                        Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 예산 스트립

    private var budgetStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("예산 현황").font(.headline)

            HStack(spacing: 16) {
                ForEach(store.budgets.prefix(5)) { budget in
                    let spent = store.spent(category: budget.category, inMonth: Date())
                    let ratio = budget.limit > 0 ? min(1.0, Double(spent) / Double(budget.limit)) : 0
                    let over = spent > budget.limit

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            CategoryDot(category: budget.category)
                            Text(budget.category).font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(ratio * 100))%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(over ? Theme.red : .secondary)
                        }
                        ProgressView(value: ratio)
                            .tint(over ? Theme.red : SpendCategory.color(for: budget.category))
                        Text("\(formatKRWCompact(spent)) / \(formatKRWCompact(budget.limit))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .card()
                }
            }
        }
    }
}

// MARK: - 온보딩 (빈 상태)

struct OnboardingView: View {
    private let features: [(icon: String, title: String, desc: String, tint: Color)] = [
        ("wonsign.circle.fill", "가계부·예산", "지출 기록과 자동 분류, 예산 초과 경고", Theme.accent),
        ("arrow.triangle.2.circlepath.circle.fill", "구독 관리", "반복 결제 자동 기록, 무료체험 종료 알림", Theme.purple),
        ("calendar.circle.fill", "일정 D-day", "납부일·만료일·기념일을 놓치지 않게", Theme.orange),
        ("checkmark.circle.fill", "체크리스트", "이사·여행·월말 정산 템플릿 제공", Theme.green),
        ("gift.circle.fill", "혜택 찾기", "나이·지역에 맞는 지원금 매칭", Theme.pink),
        ("cross.circle.fill", "건강·응급", "증상별 진료과 안내, 응급 연락처", Theme.red),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                Image(systemName: "house.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.accent.gradient)

                VStack(spacing: 8) {
                    Text("MyLife에 오신 걸 환영합니다").font(.title.bold())
                    Text("돈 관리부터 구독, 일정, 건강까지 — 일상의 흩어진 관리를 한 곳에 모았습니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(features, id: \.title) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(feature.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.subheadline.weight(.semibold))
                                Text(feature.desc).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .card()
                    }
                }
                .frame(maxWidth: 740)

                VStack(spacing: 12) {
                    Text("이렇게 시작해보세요")
                        .font(.caption).foregroundStyle(.tertiary)

                    HStack(spacing: 24) {
                        onboardingStep(number: "1", text: "거래내역 탭에서\n거래 기록")
                        onboardingStep(number: "2", text: "구독·정기결제\n등록")
                        onboardingStep(number: "3", text: "일정·체크리스트\n관리")
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    private func onboardingStep(number: String, text: String) -> some View {
        VStack(spacing: 8) {
            Text(number)
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12))
                .foregroundStyle(Theme.accent)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .card()
    }
}
