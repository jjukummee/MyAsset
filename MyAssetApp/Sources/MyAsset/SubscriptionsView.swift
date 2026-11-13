import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var life = LifeStore.shared

    @State private var viewMode: ViewMode = .list
    @State private var calendarMonth = Date()
    @State private var showForm = false
    @State private var editing: Subscription?

    private enum ViewMode: String, CaseIterable {
        case list = "목록"
        case calendar = "캘린더"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("구독·정기결제").font(.largeTitle.bold())
                    Spacer()
                    Picker("", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Button {
                        editing = nil
                        showForm = true
                    } label: {
                        Label("구독 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }

                ForEach(life.trialsEndingSoon(within: 3)) { sub in
                    trialBanner(sub)
                }

                statRow

                if life.subscriptions.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .list: listContent
                    case .calendar: calendarContent
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showForm) {
            SubscriptionForm(editing: nil)
        }
        .sheet(item: $editing) { sub in
            SubscriptionForm(editing: sub)
        }
    }

    // MARK: 통계

    private var statRow: some View {
        HStack(spacing: 16) {
            statCard(title: "월 구독료", value: formatKRW(life.monthlySubscriptionCost),
                     icon: "arrow.triangle.2.circlepath", tint: Theme.purple)
            statCard(title: "연간 환산", value: formatKRWCompact(life.monthlySubscriptionCost * 12),
                     icon: "calendar", tint: Theme.accent)
            statCard(title: "활성 구독", value: "\(life.activeSubscriptions.count)개",
                     icon: "checkmark.circle", tint: Theme.green)
            statCard(title: "이번 달 결제", value: formatKRW(monthTotal(for: Date())),
                     icon: "creditcard", tint: Theme.orange)
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

    private func trialBanner(_ sub: Subscription) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.red)
            Text("\(sub.name) 무료체험이 \(ddayLabel(daysFromToday(sub.trialEndDate ?? Date()))) 종료됩니다. 계속 쓸지 결정하세요 — 종료 후 \(formatKRW(sub.amount))이 결제됩니다.")
                .font(.caption)
            Spacer()
            Button("수정") {
                editing = sub
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: 목록

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                ForEach(life.activeSubscriptions.sorted { $0.nextBilling() < $1.nextBilling() }) { sub in
                    subscriptionRow(sub)
                }
            }

            if !life.inactiveSubscriptions.isEmpty {
                Text("해지·중지된 구독").font(.headline).padding(.top, 8)
                VStack(spacing: 10) {
                    ForEach(life.inactiveSubscriptions) { sub in
                        inactiveRow(sub)
                    }
                }
            }
        }
    }

    private func subscriptionRow(_ sub: Subscription) -> some View {
        let next = sub.nextBilling()
        let days = daysFromToday(next)
        return HStack(spacing: 14) {
            SubscriptionLogoView(logoAsset: sub.logoAsset, fallbackColor: sub.color, fallbackInitials: sub.initials, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sub.name).font(.headline)
                    if sub.isTrial {
                        Text("무료체험")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.orange.opacity(0.15))
                            .foregroundStyle(Theme.orange)
                            .clipShape(Capsule())
                    }
                    if sub.autoRecord {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .help("결제일에 가계부 자동 기록")
                    }
                }
                Text("\(sub.cycle.rawValue) · 다음 결제 \(DateFormat.dayLabel.string(from: next))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ddayLabel(days))
                .font(.caption.weight(.bold))
                .foregroundStyle(ddayColor(days))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(ddayColor(days).opacity(0.1))
                .clipShape(Capsule())
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatKRW(sub.amount)).font(.title3.bold())
                if sub.cycle != .monthly {
                    Text("월 \(formatKRWCompact(sub.monthlyEquivalent))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            editing = sub
        }
        .contextMenu {
            Button("수정") {
                editing = sub
            }
            Button("해지로 표시") { life.setSubscriptionActive(sub, active: false) }
            Divider()
            Button("삭제", role: .destructive) { life.deleteSubscription(sub) }
        }
    }

    private func inactiveRow(_ sub: Subscription) -> some View {
        HStack(spacing: 14) {
            SubscriptionLogoView(logoAsset: sub.logoAsset, fallbackColor: .gray, fallbackInitials: sub.initials, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text("\(sub.cycle.rawValue) \(formatKRW(sub.amount))").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("재개") { life.setSubscriptionActive(sub, active: true) }
                .controlSize(.small)
            Button(role: .destructive) {
                life.deleteSubscription(sub)
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .padding(14)
        .card()
        .opacity(0.75)
    }

    // MARK: 캘린더

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth)!
                } label: { Image(systemName: "chevron.left") }
                Text(DateFormat.monthLabel.string(from: calendarMonth))
                    .font(.headline)
                    .frame(width: 120)
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth)!
                } label: { Image(systemName: "chevron.right") }
                Button("오늘") { calendarMonth = Date() }
                    .controlSize(.small)
                Spacer()
                Text("이달 결제 합계: \(formatKRW(monthTotal(for: calendarMonth)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(day == "일" ? Theme.red : (day == "토" ? Theme.accent : .secondary))
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    calendarCell(day)
                }
            }
            .padding(16)
            .card()
        }
    }

    private var monthCells: [Int?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: calendarMonth),
              let range = cal.range(of: .day, in: .month, for: calendarMonth) else { return [] }
        let offset = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { Optional($0) }
    }

    private var paymentsByDay: [Int: [Subscription]] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: calendarMonth) else { return [:] }
        var dict: [Int: [Subscription]] = [:]
        for sub in life.activeSubscriptions {
            for date in sub.billingDates(from: interval.start, to: interval.end.addingTimeInterval(-1)) {
                dict[cal.component(.day, from: date), default: []].append(sub)
            }
        }
        return dict
    }

    private func monthTotal(for month: Date) -> Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return 0 }
        return life.activeSubscriptions.reduce(0) { sum, sub in
            sum + sub.billingDates(from: interval.start, to: interval.end.addingTimeInterval(-1)).count * sub.amount
        }
    }

    @ViewBuilder
    private func calendarCell(_ day: Int?) -> some View {
        if let day {
            let payments = paymentsByDay[day] ?? []
            let isToday = isTodayCell(day)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : .primary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Theme.accent : Color.clear)
                    .clipShape(Circle())
                ForEach(payments.prefix(2)) { sub in
                    HStack(spacing: 4) {
                        Circle().fill(sub.color).frame(width: 6, height: 6)
                        Text(sub.name).font(.system(size: 10)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(sub.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if payments.count > 2 {
                    Text("+\(payments.count - 2)").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(payments.isEmpty ? Color.clear : Theme.accent.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            Color.clear.frame(minHeight: 76)
        }
    }

    private func isTodayCell(_ day: Int) -> Bool {
        let cal = Calendar.current
        return cal.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
            && cal.component(.day, from: Date()) == day
    }

    // MARK: 빈 상태

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 48)).foregroundStyle(Theme.purple.gradient)
            Text("구독 서비스를 등록해보세요").font(.title3.bold())
            Text("넷플릭스, 유튜브 같은 반복 결제를 등록하면\n다음 결제일과 월 고정비를 자동으로 계산하고, 결제일에 가계부에 기록해드립니다.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                editing = nil
                showForm = true
            } label: {
                Label("첫 구독 등록", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 구독 폼

struct SubscriptionForm: View {
    var editing: Subscription?

    @ObservedObject private var life = LifeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amount = 0
    @State private var cycle: Subscription.Cycle = .monthly
    @State private var anchorDate = Date()
    @State private var category = "구독"
    @State private var colorHex = "#AF52DE"
    @State private var isTrial = false
    @State private var trialEnd = Date()
    @State private var autoRecord = true
    @State private var accountID: UUID?
    @State private var memo = ""
    @State private var showDeleteConfirm = false

    private static let presets: [(name: String, amount: Int, colorHex: String)] = [
        ("넷플릭스", 17_000, "#E50914"),
        ("유튜브 프리미엄", 14_900, "#FF0000"),
        ("쿠팡 와우", 7_890, "#346AFF"),
        ("디즈니+", 9_900, "#01147C"),
        ("티빙", 9_500, "#FF153C"),
        ("멜론", 10_900, "#00CD3C"),
        ("스포티파이", 10_900, "#1DB954"),
        ("ChatGPT Plus", 29_000, "#10A37F"),
        ("iCloud+", 4_400, "#3693F3"),
        ("통신비", 55_000, "#007AFF"),
        ("헬스장", 89_000, "#34C759"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "구독 추가" : "구독 수정").font(.title3.bold())
                Spacer()
                if editing == nil {
                    Menu {
                        ForEach(Self.presets, id: \.name) { preset in
                            Button("\(preset.name) — \(formatKRW(preset.amount))") {
                                name = preset.name
                                amount = preset.amount
                                colorHex = preset.colorHex
                            }
                        }
                    } label: {
                        Label("빠른 입력", systemImage: "sparkles")
                    }
                    .frame(width: 130)
                }
            }
            .padding(20)

            Form {
                Section {
                    TextField("이름", text: $name, prompt: Text("예: 넷플릭스"))
                    TextField("금액", value: $amount, format: .number)
                    Picker("결제 주기", selection: $cycle) {
                        ForEach(Subscription.Cycle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("결제일 (기준일)", selection: $anchorDate, displayedComponents: .date)
                    Picker("카테고리", selection: $category) {
                        ForEach(SpendCategory.expenseNames, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Toggle("무료체험 중", isOn: $isTrial)
                    if isTrial {
                        DatePicker("체험 종료일", selection: $trialEnd, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("결제일에 가계부 자동 기록", isOn: $autoRecord)
                }

                Section {
                    HStack(spacing: 8) {
                        Text("색상").frame(width: 60, alignment: .leading)
                        ForEach(Theme.accountPalette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hexString: hex) ?? .gray)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.primary.opacity(colorHex == hex ? 0.8 : 0), lineWidth: 2))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    TextField("메모", text: $memo)
                }
            }
            .formStyle(.grouped)

            HStack {
                if editing != nil {
                    Button("삭제", role: .destructive) { showDeleteConfirm = true }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button(editing == nil ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(name.isEmpty || amount <= 0)
            }
            .padding(20)
        }
        .frame(width: 460, height: 620)
        .onAppear { prefill() }
        .confirmationDialog("이 구독을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                if let editing { life.deleteSubscription(editing) }
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func prefill() {
        guard let editing else { return }
        name = editing.name
        amount = editing.amount
        cycle = editing.cycle
        anchorDate = editing.anchorDate
        category = editing.category
        colorHex = editing.colorHex
        isTrial = editing.isTrial
        trialEnd = editing.trialEndDate ?? Date()
        autoRecord = editing.autoRecord
        accountID = editing.accountID
        memo = editing.memo
    }

    private func save() {
        var sub = editing ?? Subscription(name: name, amount: amount)
        sub.name = name
        sub.amount = amount
        sub.cycle = cycle
        sub.anchorDate = anchorDate
        sub.category = category
        sub.colorHex = colorHex
        sub.isTrial = isTrial
        sub.trialEndDate = isTrial ? trialEnd : nil
        sub.autoRecord = autoRecord
        sub.accountID = autoRecord ? accountID : nil
        sub.memo = memo
        if editing == nil {
            life.addSubscription(sub)
        } else {
            life.updateSubscription(sub)
        }
        dismiss()
    }
}
