import SwiftUI

struct EventsView: View {
    @ObservedObject private var life = LifeStore.shared

    @State private var showForm = false
    @State private var editing: LifeEvent?
    @State private var viewMode: ViewMode = .list
    @State private var calendarMonth = Date()

    private enum ViewMode: String, CaseIterable {
        case list = "목록"
        case calendar = "캘린더"
    }

    private var pending: [LifeEvent] { life.events.filter { !$0.isDone }.sorted { $0.date < $1.date } }
    private var done: [LifeEvent] { life.events.filter(\.isDone).sorted { $0.date > $1.date } }

    private var overdue: [LifeEvent] { pending.filter { $0.dday < 0 } }
    private var todayEvents: [LifeEvent] { pending.filter { $0.dday == 0 } }
    private var thisWeek: [LifeEvent] { pending.filter { (1...7).contains($0.dday) } }
    private var thisMonth: [LifeEvent] { pending.filter { (8...30).contains($0.dday) } }
    private var later: [LifeEvent] { pending.filter { $0.dday > 30 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("일정·D-day").font(.largeTitle.bold())
                        Text("납부일, 만료일, 기념일을 놓치지 않게 관리하세요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
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
                        Label("일정 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }

                if life.events.isEmpty {
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
            EventForm(editing: nil)
        }
        .sheet(item: $editing) { event in
            EventForm(editing: event)
        }
    }

    // MARK: 목록

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !overdue.isEmpty {
                section("지난 일정", events: overdue, tint: Theme.red)
            }
            if !todayEvents.isEmpty {
                section("오늘", events: todayEvents, tint: Theme.red)
            }
            if !thisWeek.isEmpty {
                section("이번 주", events: thisWeek, tint: Theme.orange)
            }
            if !thisMonth.isEmpty {
                section("이번 달", events: thisMonth, tint: .secondary)
            }
            if !later.isEmpty {
                section("나중", events: later, tint: .secondary)
            }
            if pending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(Theme.green)
                    Text("예정된 일정이 없습니다.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            if !done.isEmpty {
                doneSection
            }
        }
    }

    private func section(_ title: String, events: [LifeEvent], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                Text("\(events.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }
            VStack(spacing: 8) {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: LifeEvent) -> some View {
        HStack(spacing: 14) {
            Button {
                life.completeEvent(event)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(event.repeatRule == .none ? "완료 처리" : "완료 — 다음 회차로 이동")

            Image(systemName: event.type.icon)
                .font(.system(size: 26))
                .foregroundStyle(event.type.color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title).font(.headline)
                    if event.repeatRule != .none {
                        Text(event.repeatRule.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(DateFormat.dayLabel.string(from: event.date))
                        .font(.caption).foregroundStyle(.secondary)
                    if !event.memo.isEmpty {
                        Text("· \(event.memo)").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(ddayLabel(event.dday))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ddayColor(event.dday))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(ddayColor(event.dday).opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            editing = event
        }
        .contextMenu {
            Button("수정") {
                editing = event
            }
            Button("완료 처리") { life.completeEvent(event) }
            Divider()
            Button("삭제", role: .destructive) { life.deleteEvent(event) }
        }
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("완료된 일정").font(.headline).padding(.top, 8)
            VStack(spacing: 6) {
                ForEach(done.prefix(10)) { event in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                        Text(event.title).font(.subheadline).strikethrough().foregroundStyle(.secondary)
                        Spacer()
                        Text(DateFormat.dayLabel.string(from: event.date))
                            .font(.caption).foregroundStyle(.tertiary)
                        Button("복원") { life.restoreEvent(event) }
                            .controlSize(.small)
                        Button(role: .destructive) {
                            life.deleteEvent(event)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .card()
                    .opacity(0.8)
                }
            }
        }
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
                let total = eventsByDay.values.reduce(0) { $0 + $1.count }
                if total > 0 {
                    Text("이달 일정 \(total)건")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
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

    private var eventsByDay: [Int: [LifeEvent]] {
        let cal = Calendar.current
        var dict: [Int: [LifeEvent]] = [:]
        for event in life.events.filter({ !$0.isDone }) {
            guard cal.isDate(event.date, equalTo: calendarMonth, toGranularity: .month) else { continue }
            let day = cal.component(.day, from: event.date)
            dict[day, default: []].append(event)
        }
        return dict
    }

    @ViewBuilder
    private func calendarCell(_ day: Int?) -> some View {
        if let day {
            let events = eventsByDay[day] ?? []
            let isToday = isTodayCell(day)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : .primary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Theme.accent : Color.clear)
                    .clipShape(Circle())
                ForEach(events.prefix(3)) { event in
                    Button {
                        editing = event
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: event.type.icon)
                                .font(.system(size: 8))
                                .foregroundStyle(event.type.color)
                            Text(event.title)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(event.type.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                if events.count > 3 {
                    Text("+\(events.count - 3) 더 보기")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(events.isEmpty ? Color.clear : Color.primary.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Theme.accent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            Color.clear.frame(minHeight: 88)
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
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48)).foregroundStyle(Theme.accent.gradient)
            Text("일정을 등록해보세요").font(.title3.bold())
            Text("월세 납부, 보험 갱신, 약정 만료, 생일까지 —\nD-day로 한눈에 보고 놓치지 않을 수 있습니다.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                editing = nil
                showForm = true
            } label: {
                Label("첫 일정 추가", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - 일정 폼

struct EventForm: View {
    var editing: LifeEvent?

    @ObservedObject private var life = LifeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date = Date()
    @State private var type: LifeEvent.EventType = .general
    @State private var repeatRule: LifeEvent.RepeatRule = .none
    @State private var memo = ""

    private static let presets: [(title: String, type: LifeEvent.EventType, rule: LifeEvent.RepeatRule)] = [
        ("월세 납부", .payment, .monthly),
        ("관리비 납부", .payment, .monthly),
        ("카드 대금 결제", .payment, .monthly),
        ("보험 갱신", .renewal, .yearly),
        ("휴대폰 약정 만료", .renewal, .none),
        ("건강검진", .appointment, .yearly),
        ("부모님 생신", .anniversary, .yearly),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "일정 추가" : "일정 수정").font(.title3.bold())
                Spacer()
                if editing == nil {
                    Menu {
                        ForEach(Self.presets, id: \.title) { preset in
                            Button(preset.title) {
                                title = preset.title
                                type = preset.type
                                repeatRule = preset.rule
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
                TextField("제목", text: $title, prompt: Text("예: 자동차보험 갱신"))
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                Picker("종류", selection: $type) {
                    ForEach(LifeEvent.EventType.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("반복", selection: $repeatRule) {
                    ForEach(LifeEvent.RepeatRule.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("메모", text: $memo)
            }
            .formStyle(.grouped)

            HStack {
                if let editing {
                    Button("삭제", role: .destructive) {
                        life.deleteEvent(editing)
                        dismiss()
                    }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button(editing == nil ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(title.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 440, height: 420)
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let editing else { return }
        title = editing.title
        date = editing.date
        type = editing.type
        repeatRule = editing.repeatRule
        memo = editing.memo
    }

    private func save() {
        var event = editing ?? LifeEvent(title: title, date: date)
        event.title = title
        event.date = date
        event.type = type
        event.repeatRule = repeatRule
        event.memo = memo
        if editing == nil {
            life.addEvent(event)
        } else {
            life.updateEvent(event)
        }
        dismiss()
    }
}
