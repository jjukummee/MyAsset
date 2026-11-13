import SwiftUI

// MARK: - 카드·결제수단별 보기

struct PaymentMethodsView: View {
    @ObservedObject private var store = DataStore.shared
    @State private var anchor = Date()
    @State private var expanded: Set<String> = []

    private let unassigned = "미지정"
    static let pinnedCard = "현대카드X"          // 카드 최상단 고정
    static let benefitThreshold = 500_000        // 현대카드X 월 실적 기준

    // 결제수단별 묶음 (카드 → 간편결제 → 계좌 → 기타, 그 안에서 결정적 정렬)
    private var groups: [MethodGroup] {
        let txs = store.transactions(inMonth: anchor)
        var bucket: [String: [UserTransaction]] = [:]
        for tx in txs {
            let key = (tx.paymentMethod?.isEmpty == false) ? tx.paymentMethod! : unassigned
            bucket[key, default: []].append(tx)
        }
        let built = bucket.map { key, list in
            MethodGroup(
                name: key,
                txs: list.sorted { $0.date > $1.date },
                spent: list.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount },
                received: list.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
            )
        }
        // 결정적 정렬: (1)유형 순서 (2)현대카드X 고정 (3)지출 큰 순 (4)이름 — 동점에도 순서 불변
        return built.sorted { a, b in
            if a.kind.order != b.kind.order { return a.kind.order < b.kind.order }
            let aPin = a.name == Self.pinnedCard, bPin = b.name == Self.pinnedCard
            if aPin != bPin { return aPin }
            if a.spent != b.spent { return a.spent > b.spent }
            return a.name < b.name
        }
    }

    private var totalSpent: Int { groups.reduce(0) { $0 + $1.spent } }
    private var totalReceived: Int { groups.reduce(0) { $0 + $1.received } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                monthBar
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in
                        methodCard(group)
                    }
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("카드·결제수단").font(.largeTitle.bold())
            Text("결제수단별로 묶어 보고, 카드 사용액을 한눈에 확인하세요")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var monthBar: some View {
        HStack(spacing: 14) {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.bordered)
            Text(DateFormat.monthLabel.string(from: anchor))
                .font(.title3.weight(.semibold)).frame(width: 130)
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered)
                .disabled(Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: .month))
            Spacer()
            Label("+\(formatKRW(totalReceived))", systemImage: "arrow.down.left")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green)
            Label("-\(formatKRW(totalSpent))", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.red)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("이달에는 거래가 없습니다.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func methodCard(_ group: MethodGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                toggle(group.name)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.kind.icon)
                        .font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(group.kind.color.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.subheadline.weight(.semibold))
                        Text("\(group.kind.label) · \(group.txs.count)건").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if group.spent > 0 {
                            Text("-\(formatKRW(group.spent))")
                                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.red)
                        }
                        if group.received > 0 {
                            Text("+\(formatKRW(group.received))")
                                .font(group.spent > 0 ? .caption : .subheadline.weight(.bold))
                                .foregroundStyle(Theme.green)
                        }
                        if group.spent == 0 && group.received == 0 {
                            Text("0원").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: expanded.contains(group.name) ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 현대카드X 실적(50만원) 표시
            if group.name == Self.pinnedCard {
                benefitBar(spent: group.spent)
            }

            if expanded.contains(group.name) {
                Divider().padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(group.txs) { tx in
                        HStack(spacing: 12) {
                            CategoryDot(category: tx.category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title).font(.subheadline)
                                Text(DateFormat.day.string(from: tx.date)).font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            CategoryBadge(category: tx.category)
                            Text((tx.amount > 0 ? "+" : "") + formatKRW(tx.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tx.amount > 0 ? Theme.green : .primary)
                                .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .card()
    }

    // 현대카드X 월 실적 진행바
    private func benefitBar(spent: Int) -> some View {
        let goal = Self.benefitThreshold
        let achieved = spent >= goal
        let remain = max(0, goal - spent)
        let progress = min(1.0, Double(spent) / Double(goal))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: achieved ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(achieved ? Theme.green : Theme.accent)
                if achieved {
                    Text("이번 달 실적 달성 (50만원 이상)")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                } else {
                    Text("실적까지 \(formatKRW(remain)) 남음")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Spacer()
                Text("\(formatKRW(spent)) / \(formatKRW(goal))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    Capsule().fill((achieved ? Theme.green : Theme.accent).gradient)
                        .frame(width: max(6, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func toggle(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: anchor) {
            anchor = next
        }
    }
}

// MARK: - 모델 / 결제수단 종류

private struct MethodGroup: Identifiable {
    let name: String
    let txs: [UserTransaction]
    let spent: Int
    let received: Int
    var id: String { name }
    var kind: MethodKind { MethodKind.of(name) }
}

private enum MethodKind {
    case card, pay, account, other

    static func of(_ name: String) -> MethodKind {
        let n = name.lowercased()
        if n.contains("카드") || n.contains("체크") { return .card }
        if ["카카오페이", "토스", "네이버페이", "페이", "머니", "포인트"].contains(where: { n.contains($0.lowercased()) }) { return .pay }
        if n.contains("계좌") || n.contains("통장") || n.contains("뱅크") || n.contains("예금") { return .account }
        return .other
    }

    // 정렬 순서: 카드 → 간편결제 → 계좌 → 기타
    var order: Int {
        switch self {
        case .card: return 0
        case .pay: return 1
        case .account: return 2
        case .other: return 3
        }
    }

    var label: String {
        switch self {
        case .card: return "카드"
        case .pay: return "간편결제"
        case .account: return "계좌"
        case .other: return "기타"
        }
    }

    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .pay: return "wallet.pass.fill"
        case .account: return "building.columns.fill"
        case .other: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .card: return Theme.accent
        case .pay: return Theme.purple
        case .account: return Theme.green
        case .other: return .gray
        }
    }
}
