import SwiftUI

@main
struct MyAssetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1150, minHeight: 720)
        }
        .commands {
            SidebarCommands()
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case home = "홈"
    case weather = "날씨"
    case events = "일정·D-day"
    case checklists = "체크리스트"
    case benefits = "혜택·지원금"
    case health = "건강·응급"
    case transactions = "거래내역"
    case payments = "카드·결제수단"
    case subscriptions = "구독·정기결제"
    case wishlist = "위시리스트"
    case analysis = "지출분석"
    case settings = "설정"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .weather: return "cloud.sun.fill"
        case .events: return "calendar.badge.clock"
        case .checklists: return "checklist"
        case .benefits: return "gift"
        case .health: return "cross.case"
        case .transactions: return "list.bullet.rectangle"
        case .payments: return "creditcard"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .wishlist: return "heart.text.square"
        case .analysis: return "chart.pie"
        case .settings: return "gearshape"
        }
    }

    static let lifeSection: [Screen] = [.weather, .events, .checklists, .wishlist, .benefits, .health]
    static let moneySection: [Screen] = [.transactions, .analysis, .payments, .subscriptions]
}

struct ContentView: View {
    @State private var selection: Screen = .home
    @ObservedObject private var life = LifeStore.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(Screen.home.rawValue, systemImage: Screen.home.icon).tag(Screen.home)

                Section("생활") {
                    ForEach(Screen.lifeSection) { screen in
                        Label(screen.rawValue, systemImage: screen.icon)
                            .badge(badgeCount(for: screen))
                            .tag(screen)
                    }
                }
                Section("돈 관리") {
                    ForEach(Screen.moneySection) { screen in
                        Label(screen.rawValue, systemImage: screen.icon)
                            .badge(badgeCount(for: screen))
                            .tag(screen)
                    }
                }
                Section {
                    Label(Screen.settings.rawValue, systemImage: Screen.settings.icon).tag(Screen.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .navigationTitle("MyLife")
        } detail: {
            switch selection {
            case .home: DashboardView(selection: $selection)
            case .transactions: TransactionsView()
            case .payments: PaymentMethodsView()
            case .subscriptions: SubscriptionsView()
            case .wishlist: WishlistView()
            case .analysis: AnalysisView()
            case .events: EventsView()
            case .checklists: ChecklistsView()
            case .benefits: BenefitsView()
            case .health: HealthView()
            case .weather: WeatherView()
            case .settings: SettingsView()
            }
        }
        .onAppear {
            // 실행 파일 단독 구동 시 전체화면 속성 부여
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
        }
    }

    /// 사이드바 배지 — 처리할 일이 있는 화면만 표시
    private func badgeCount(for screen: Screen) -> Int {
        switch screen {
        case .events: return life.dueEventCount
        case .subscriptions: return life.trialsEndingSoon(within: 3).count
        default: return 0
        }
    }
}

// MARK: - 공용 컴포넌트

struct BankLogoView: View {
    let color: Color
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.3, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient)
            .clipShape(Circle())
    }
}

/// 구독 로고: 번들에 매칭되는 앱 아이콘이 있으면 둥근 사각형으로 표시하고, 없으면 색상 원+이니셜로 대체.
struct SubscriptionLogoView: View {
    let logoAsset: String?
    let fallbackColor: Color
    let fallbackInitials: String
    var size: CGFloat = 44

    var body: some View {
        if let asset = logoAsset, let image = Self.loadImage(asset) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        } else {
            BankLogoView(color: fallbackColor, initials: fallbackInitials, size: size)
        }
    }

    private static var cache: [String: NSImage] = [:]
    private static func loadImage(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Logos"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

struct CategoryDot: View {
    let category: String

    var body: some View {
        Circle()
            .fill(SpendCategory.color(for: category))
            .frame(width: 9, height: 9)
    }
}

struct CategoryBadge: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.caption.weight(.medium))
            .foregroundStyle(SpendCategory.color(for: category))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SpendCategory.color(for: category).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
