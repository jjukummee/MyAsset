import SwiftUI
import Charts

struct AnalysisView: View {
    @ObservedObject private var store = DataStore.shared
    @State private var anchor = Date()
    @State private var expandedCategories: Set<String> = []

    private var spending: [(category: String, amount: Int)] { store.spendingByCategory(inMonth: anchor) }
    private var monthly: [(label: String, amount: Int)] { store.monthlyExpenses(months: 6, endingAt: anchor) }

    // 저축 제외 총 지출
    private var expense: Int {
        spending.filter { $0.category != "저축" }.reduce(0) { $0 + $1.amount }
    }
    private var lastMonthExpense: Int {
        guard let prev = Calendar.current.date(byAdding: .month, value: -1, to: anchor) else { return 0 }
        return store.spendingByCategory(inMonth: prev)
            .filter { $0.category != "저축" }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("지출 분석").font(.largeTitle.bold())
                    Spacer()
                    monthNav
                }

                statsRow

                HStack(alignment: .top, spacing: 20) {
                    trendCard.frame(maxWidth: .infinity)
                    categoryCard.frame(maxWidth: .infinity)
                }

                categoryDetailCard

                if !spending.isEmpty {
                    topSpendingCard
                }
            }
            .padding(28)
        }
    }

    private var monthNav: some View {
        HStack(spacing: 10) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered)
            Text(DateFormat.monthLabel.string(from: anchor))
                .font(.title3.weight(.semibold))
                .frame(width: 120)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered)
                .disabled(Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: .month))
        }
    }

    private var statsRow: some View {
        let delta = expense - lastMonthExpense
        let deltaPercent = lastMonthExpense > 0 ? Double(delta) / Double(lastMonthExpense) * 100 : 0

        let hyundai = store.cardSpending("현대카드X", inMonth: anchor)

        return HStack(spacing: 16) {
            statCard(title: "총 지출 (저축 제외)", value: formatKRW(expense), tint: Theme.red)
            statCard(
                title: "전월 대비",
                value: lastMonthExpense > 0
                    ? String(format: "%@%.1f%%", delta >= 0 ? "+" : "", deltaPercent)
                    : "—",
                tint: delta > 0 ? Theme.red : Theme.green)
            statCard(title: "현대카드X 소비", value: formatKRW(hyundai), tint: Theme.accent)
            statCard(title: "지출 건수", value: "\(store.transactions(inMonth: anchor).filter { $0.amount < 0 && $0.category != "이체" }.count)건", tint: Theme.purple)
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .card()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("월별 지출 추이").font(.headline)

            Chart(monthly, id: \.label) { item in
                BarMark(x: .value("월", item.label), y: .value("지출", item.amount))
                    .foregroundStyle(item.label == monthly.last?.label ? Theme.accent : Color.primary.opacity(0.12))
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        if item.amount > 0 && item.label == monthly.last?.label {
                            Text(formatKRWCompact(item.amount))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Int.self) {
                            Text(formatKRWCompact(amount)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(20)
        .card()
    }

    private var categoryCard: some View {
        let total = spending.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 14) {
            Text("카테고리별 비중").font(.headline)

            if spending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("지출 내역이 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                HStack(spacing: 20) {
                    ZStack {
                        Chart(spending, id: \.category) { item in
                            SectorMark(angle: .value("금액", item.amount), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(SpendCategory.color(for: item.category))
                                .cornerRadius(3)
                        }
                        if let top = spending.first {
                            VStack(spacing: 2) {
                                Text("최다").font(.caption2).foregroundStyle(.secondary)
                                Text(top.category)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(SpendCategory.color(for: top.category))
                            }
                        }
                    }
                    .frame(width: 150, height: 150)

                    VStack(spacing: 10) {
                        ForEach(spending.prefix(7), id: \.category) { item in
                            let pct = total > 0 ? Double(item.amount) / Double(total) : 0
                            VStack(spacing: 3) {
                                HStack {
                                    CategoryDot(category: item.category)
                                    Text(item.category).font(.caption.weight(.medium))
                                    Spacer()
                                    Text(formatKRW(item.amount)).font(.caption.weight(.semibold))
                                }
                                HStack(spacing: 6) {
                                    ProgressView(value: pct)
                                        .tint(SpendCategory.color(for: item.category))
                                    Text("\(Int(pct * 100))%")
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
        .padding(20)
        .card()
    }

    // MARK: 카테고리별 거래 내역

    private var categoryDetailCard: some View {
        let txAll = store.transactions(inMonth: anchor).filter { $0.amount < 0 && $0.category != "이체" }

        return VStack(alignment: .leading, spacing: 12) {
            Text("카테고리별 내역").font(.headline)

            if spending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("이달 지출 내역이 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(spending.enumerated()), id: \.element.category) { catIdx, cat in
                        let txs = txAll
                            .filter { $0.category == cat.category }
                            .sorted { $0.amount < $1.amount }  // 고액순
                        let isExpanded = expandedCategories.contains(cat.category)

                        VStack(spacing: 0) {
                            Button {
                                if isExpanded {
                                    expandedCategories.remove(cat.category)
                                } else {
                                    expandedCategories.insert(cat.category)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    CategoryDot(category: cat.category)
                                    Text(cat.category).font(.subheadline.weight(.semibold))
                                    Text("\(txs.count)건")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatKRW(cat.amount))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(SpendCategory.color(for: cat.category))
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isExpanded {
                                VStack(spacing: 0) {
                                    ForEach(Array(txs.enumerated()), id: \.element.id) { idx, tx in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(tx.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                Text(DateFormat.dayLabel.string(from: tx.date))
                                                    .font(.caption).foregroundStyle(.tertiary)
                                            }
                                            Spacer()
                                            Text(formatKRW(tx.amount))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        if idx < txs.count - 1 {
                                            Divider().padding(.leading, 16)
                                        }
                                    }
                                }
                                .padding(.bottom, 8)
                                .background(Color.primary.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.bottom, 6)
                            }
                        }

                        if catIdx < spending.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: TOP 5

    private var topSpendingCard: some View {
        let top = store.transactions(inMonth: anchor)
            .filter { $0.amount < 0 && $0.category != "이체" }
            .sorted { $0.amount < $1.amount }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 12) {
            Text("가장 큰 지출 TOP 5").font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { idx, tx in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(idx == 0 ? Theme.red.opacity(0.12) : Color.primary.opacity(0.05))
                            .foregroundStyle(idx == 0 ? Theme.red : .secondary)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tx.title).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                CategoryBadge(category: tx.category)
                                Text(DateFormat.dayLabel.string(from: tx.date))
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(formatKRW(tx.amount)).font(.subheadline.bold())
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    if idx != top.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .card()
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: anchor) {
            anchor = next
        }
    }
}
