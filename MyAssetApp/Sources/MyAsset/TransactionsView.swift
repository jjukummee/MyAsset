import SwiftUI
import UniformTypeIdentifiers

struct TransactionsView: View {
    @ObservedObject private var store = DataStore.shared

    @State private var anchor = Date()
    @State private var filter = "전체"
    @State private var showAddSheet = false
    @State private var editingTx: UserTransaction?
    @State private var viewMode: ViewMode = .list
    @State private var selectedDay: Int?

    private let filters = ["전체", "수입", "지출", "이체"]

    private enum ViewMode: String, CaseIterable {
        case list = "목록"
        case calendar = "캘린더"
    }

    private var monthTxs: [UserTransaction] {
        store.transactions(inMonth: anchor).filter { tx in
            switch filter {
            case "수입": return tx.amount > 0 && tx.category != "이체"
            case "지출": return tx.amount < 0 && tx.category != "이체"
            case "이체": return tx.category == "이체"
            default: return true
            }
        }
    }

    private var grouped: [(day: String, txs: [UserTransaction])] {
        Dictionary(grouping: monthTxs) { DateFormat.day.string(from: $0.date) }
            .sorted { $0.key > $1.key }
            .map { key, value in
                let label = value.first.map { DateFormat.dayLabel.string(from: $0.date) } ?? key
                return (label, value)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                monthSummary
                controls

                switch viewMode {
                case .list:
                    if monthTxs.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.day) { group in
                            daySection(group)
                        }
                    }
                case .calendar:
                    calendarContent
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showAddSheet) {
            TransactionForm(existing: nil, defaultDate: anchor)
        }
        .sheet(item: $editingTx) { tx in
            TransactionForm(existing: tx, defaultDate: anchor)
        }
    }

    private var header: some View {
        HStack {
            Text("거래내역").font(.largeTitle.bold())
            Spacer()
            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
            Button {
                showAddSheet = true
            } label: {
                Label("거래 추가", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var monthSummary: some View {
        HStack(spacing: 14) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered)
            Text(DateFormat.monthLabel.string(from: anchor))
                .font(.title3.weight(.semibold))
                .frame(width: 130)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered)
                .disabled(Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: .month))

            Spacer()

            Label("+\(formatKRW(store.income(inMonth: anchor)))", systemImage: "arrow.down.left")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green)
            Label("-\(formatKRW(store.expense(inMonth: anchor)))", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.red)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(filters, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .labelsHidden()
            // 세그먼트 Picker가 라벨 영역을 예약해 좌측에 여백이 생김 → 컨트롤 좌측을 제목 "거"에 맞추기 위해 보정
            .padding(.leading, -52)

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("이달에는 거래가 없습니다.").font(.subheadline).foregroundStyle(.secondary)
            Button("거래 추가") { showAddSheet = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .card()
    }

    private func daySection(_ group: (day: String, txs: [UserTransaction])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.day).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let dayTotal = group.txs.filter { $0.category != "이체" }.reduce(0) { $0 + $1.amount }
                if dayTotal != 0 {
                    Text((dayTotal > 0 ? "+" : "") + formatKRW(dayTotal))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dayTotal > 0 ? Theme.green : .secondary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(group.txs.enumerated()), id: \.element.id) { idx, tx in
                    transactionRow(tx)
                    if idx != group.txs.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .card()
        }
    }

    private func transactionRow(_ tx: UserTransaction) -> some View {
        HStack(spacing: 12) {
            CategoryDot(category: tx.category)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.title).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    CategoryBadge(category: tx.category)
                    if !tx.memo.isEmpty {
                        Text(tx.memo).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }

            Spacer()

            Text((tx.amount > 0 ? "+" : "") + formatKRW(tx.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tx.amount > 0 ? Theme.green : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editingTx = tx }
        .contextMenu {
            Button("수정") { editingTx = tx }
            Button("삭제", role: .destructive) { store.deleteTransaction(tx) }
        }
    }

    // MARK: - 캘린더 뷰

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            selectedDayDetail
        }
    }

    private var monthCells: [Int?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: anchor),
              let range = cal.range(of: .day, in: .month, for: anchor) else { return [] }
        let offset = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { Optional($0) }
    }

    private var txsByDay: [Int: [UserTransaction]] {
        let cal = Calendar.current
        var dict: [Int: [UserTransaction]] = [:]
        for tx in monthTxs {
            dict[cal.component(.day, from: tx.date), default: []].append(tx)
        }
        return dict
    }

    private func isToday(_ day: Int) -> Bool {
        let cal = Calendar.current
        guard cal.isDate(anchor, equalTo: Date(), toGranularity: .month) else { return false }
        return cal.component(.day, from: Date()) == day
    }

    @ViewBuilder
    private func calendarCell(_ day: Int?) -> some View {
        if let day {
            let txs = txsByDay[day] ?? []
            let income = txs.filter { $0.amount > 0 && $0.category != "이체" }.reduce(0) { $0 + $1.amount }
            let expense = txs.filter { $0.amount < 0 && $0.category != "이체" }.reduce(0) { $0 + $1.amount }
            let isSelected = selectedDay == day

            VStack(alignment: .leading, spacing: 3) {
                Text("\(day)")
                    .font(.caption.weight(isToday(day) ? .bold : .regular))
                    .foregroundStyle(isToday(day) ? Color.white : .primary)
                    .frame(width: 22, height: 22)
                    .background(isToday(day) ? Theme.accent : Color.clear)
                    .clipShape(Circle())

                Spacer(minLength: 0)

                if income > 0 {
                    Text("+\(formatKRWCompact(income))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.green)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if expense < 0 {
                    Text(formatKRWCompact(expense))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 62)
            .padding(6)
            .background(isSelected ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture {
                selectedDay = (selectedDay == day) ? nil : day
            }
        } else {
            Color.clear.frame(height: 62)
        }
    }

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let day = selectedDay, let txs = txsByDay[day], !txs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dayDetailLabel(day)).font(.headline)
                    Spacer()
                    let total = txs.filter { $0.category != "이체" }.reduce(0) { $0 + $1.amount }
                    if total != 0 {
                        Text((total > 0 ? "+" : "") + formatKRW(total))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(total > 0 ? Theme.green : .primary)
                    }
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { idx, tx in
                        transactionRow(tx)
                        if idx != txs.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .card()
            }
        } else if selectedDay != nil {
            Text("이 날에는 거래가 없습니다.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .card()
        } else {
            Text("날짜를 선택하면 상세 내역이 표시됩니다.")
                .font(.subheadline).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        }
    }

    private func dayDetailLabel(_ day: Int) -> String {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: anchor)
        comps.day = day
        if let date = cal.date(from: comps) {
            return DateFormat.dayLabel.string(from: date)
        }
        return "\(day)일"
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: anchor) {
            anchor = next
            selectedDay = nil
        }
    }
}

// MARK: - 거래 추가/수정 폼

struct TransactionForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = DataStore.shared

    let existing: UserTransaction?
    let defaultDate: Date

    @State private var title = ""
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var date = Date()
    @State private var category = "기타"
    @State private var accountID: UUID?
    @State private var memo = ""
    @State private var categoryTouched = false

    private var amountValue: Int? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
        guard let value = Int(cleaned), value > 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? "거래 추가" : "거래 수정").font(.title3.bold())

            Picker("종류", selection: $isExpense) {
                Text("지출").tag(true)
                Text("수입").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                Text("내용").font(.caption).foregroundStyle(.secondary)
                TextField("예: 스타벅스, 급여, 월세...", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: title) { _, newValue in
                        guard !categoryTouched, !newValue.isEmpty else { return }
                        category = AutoCategory.categorize(newValue, amount: isExpense ? -1 : 1)
                    }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("금액").font(.caption).foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("날짜").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("카테고리").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $category) {
                    ForEach(SpendCategory.all) { cat in
                        Text(cat.name).tag(cat.name)
                    }
                }
                .labelsHidden()
                .onChange(of: category) { _, _ in categoryTouched = true }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("메모 (선택)").font(.caption).foregroundStyle(.secondary)
                TextField("", text: $memo)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                if let existing {
                    Button("삭제", role: .destructive) {
                        store.deleteTransaction(existing)
                        dismiss()
                    }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button(existing == nil ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(title.isEmpty || amountValue == nil)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
        .onAppear(perform: populate)
    }

    private func populate() {
        if let existing {
            title = existing.title
            amountText = formatNumber(abs(existing.amount))
            isExpense = existing.amount < 0
            date = existing.date
            category = existing.category
            accountID = existing.accountID
            memo = existing.memo
            categoryTouched = true
        } else {
            date = Calendar.current.isDate(defaultDate, equalTo: Date(), toGranularity: .month) ? Date() : defaultDate
        }
    }

    private func save() {
        guard let value = amountValue else { return }
        let amount = isExpense ? -value : value
        var tx = existing ?? UserTransaction(date: date, title: title, amount: amount, category: category, accountID: accountID)
        tx.date = date
        tx.title = title
        tx.amount = amount
        tx.category = category
        tx.accountID = accountID
        tx.memo = memo

        if existing == nil {
            store.addTransaction(tx)
        } else {
            store.updateTransaction(tx)
        }
        dismiss()
    }
}
