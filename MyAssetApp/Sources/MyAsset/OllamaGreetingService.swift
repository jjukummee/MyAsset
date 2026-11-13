import Foundation

@MainActor
final class OllamaGreetingStore: ObservableObject {
    static let shared = OllamaGreetingStore()

    @Published private(set) var aiGreeting: String?
    @Published private(set) var isGenerating = false

    private var lastGenerated: Date?
    private var lastContextSignature: String?
    private let cacheDuration: TimeInterval = 1800  // 30분
    private let baseURL = URL(string: "http://localhost:11434")!
    private let preferredModels = ["qwen2.5:14b", "qwen2.5:7b", "qwen2.5:3b"]

    private init() {}

    // MARK: - 컨텍스트

    struct Context {
        let hour: Int
        let weekday: String
        // 오늘 일정
        let todayEventTitles: [String]
        // 내일 일정
        let tomorrowEventTitles: [String]
        // 2~7일 내 다가오는 일정
        let upcomingEvents: [(title: String, daysLeft: Int)]
        // 오늘 결제 구독
        let subscriptionsDueToday: [(name: String, amount: Int)]
        // 3일 내 결제 예정 구독
        let subscriptionsDueSoon: [(name: String, daysLeft: Int)]
        // 예산 초과 카테고리
        let overBudgetCategories: [String]
        // 진행 중 체크리스트 이름
        let activeChecklists: [String]
        // 미완료 할 일 항목
        let pendingChecklistItems: [String]
        // 날씨 — nil이면 데이터 없음
        let weatherToday: String?
        let weatherTomorrow: String?
        let rainExpectedHours: [String]  // 비 예보 시간대 (미래만)
    }

    // MARK: - 시간대 이모지

    static func emoji(for hour: Int) -> String {
        switch hour {
        case 5..<11: return "☀️"
        case 11..<14: return "🌤️"
        case 14..<18: return "✨"
        case 18..<22: return "🌟"
        default:      return "🌙"
        }
    }

    // MARK: - 생성 트리거

    func refresh(context: Context) async {
        let sig = signature(of: context)
        let cacheExpired = lastGenerated.map { Date().timeIntervalSince($0) >= cacheDuration } ?? true
        guard cacheExpired || sig != lastContextSignature else { return }
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }

        guard let model = await resolveModel() else { return }
        if let result = await generate(model: model, context: context) {
            aiGreeting = result
            lastGenerated = Date()
            lastContextSignature = sig
        }
    }

    // 주요 필드가 바뀌면 캐시 무효화
    private func signature(of ctx: Context) -> String {
        [
            ctx.weatherToday ?? "",
            ctx.rainExpectedHours.joined(),
            ctx.todayEventTitles.joined(),
            ctx.tomorrowEventTitles.joined(),
            ctx.subscriptionsDueToday.map(\.name).joined(),
            ctx.pendingChecklistItems.prefix(3).joined()
        ].joined(separator: "|")
    }

    // MARK: - 모델 선택

    private func resolveModel() async -> String? {
        struct TagsResponse: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        let url = baseURL.appendingPathComponent("api/tags")
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else { return nil }
        let available = response.models.map(\.name)
        for preferred in preferredModels {
            if available.contains(preferred) { return preferred }
        }
        return available.first
    }

    // MARK: - Ollama 호출

    private func generate(model: String, context: Context) async -> String? {
        let situationBlock = buildSituationBlock(context)

        let systemPrompt = """
        당신은 한국어로만 대답하는 개인 생활 관리 앱의 AI 어시스턴트입니다.
        사용자에게 실용적이고 행동 가능한 맞춤형 조언을 제공합니다.
        한국어 텍스트만 출력하세요. 이모지, 특수문자, 마크다운, 영어를 절대 사용하지 마세요.
        """

        let userPrompt = """
        \(situationBlock)

        위 정보를 바탕으로 사용자에게 가장 도움이 되는 맞춤형 문구를 작성해주세요.
        우선순위:
        1. 오늘 비 예보 시간대가 있으면 "오후 N시에 비가 온다"고 구체적으로 말하고 우산을 챙기라고 알려주세요
        2. 오늘 일정이 있으면 반드시 "오늘 [제목]"이라고 표현해주세요
        3. 내일 일정이 있으면 반드시 "내일 [제목]"이라고 표현해주세요
        4. 곧 다가오는 일정은 "N일 후 [제목]"이라고 표현해주세요
        5. 오늘 정기결제가 있으면 이름과 금액을 언급해주세요
        6. 미완료 할 일이 있으면 항목 이름을 언급하며 격려해주세요
        7. 위에 해당하는 것이 없으면 날씨·시간대에 맞는 따뜻한 인사를 해주세요

        중요: 일정을 언급할 때는 반드시 '오늘', '내일', 'N일 후' 중 하나를 붙여서 언제인지 명확히 해주세요.
        조건:
        - 존댓말
        - 가장 중요한 정보 1가지를 구체적으로 언급
        - 따뜻하고 실용적인 어조
        - 2문장 이내, 70자 이내
        - 한국어 텍스트만 출력
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userPrompt]
        ]

        let body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        struct ChatResponse: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data) else { return nil }

        let cleaned = sanitize(response.message.content)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - 상황 블록 구성

    private func buildSituationBlock(_ ctx: Context) -> String {
        var lines: [String] = ["[현재: \(ctx.weekday) \(timePeriodLabel(ctx.hour))]"]

        // 날씨 정보 — 가장 먼저 배치해 AI가 우산 조언에 활용하도록
        if let weatherToday = ctx.weatherToday {
            lines.append("오늘 날씨: \(weatherToday)")
        }
        if !ctx.rainExpectedHours.isEmpty {
            lines.append("오늘 비 예보 시간: \(ctx.rainExpectedHours.joined(separator: ", "))")
        }
        if let weatherTomorrow = ctx.weatherTomorrow {
            lines.append("내일 날씨: \(weatherTomorrow)")
        }

        // 일정 — 시간 기준을 명확히 표기
        if !ctx.todayEventTitles.isEmpty {
            lines.append("[오늘 일정] \(ctx.todayEventTitles.joined(separator: ", "))")
        }
        if !ctx.tomorrowEventTitles.isEmpty {
            lines.append("[내일 일정] \(ctx.tomorrowEventTitles.joined(separator: ", "))")
        }
        if !ctx.upcomingEvents.isEmpty {
            let items = ctx.upcomingEvents.prefix(2).map { "[\($0.daysLeft)일 후] \($0.title)" }
            lines.append("다가오는 일정: \(items.joined(separator: ", "))")
        }

        // 결제
        if !ctx.subscriptionsDueToday.isEmpty {
            let items = ctx.subscriptionsDueToday.map { "\($0.name) \(formatWon($0.amount))원" }
            lines.append("오늘 정기결제: \(items.joined(separator: ", "))")
        }
        if !ctx.subscriptionsDueSoon.isEmpty {
            let items = ctx.subscriptionsDueSoon.prefix(2).map { "\($0.name)(\($0.daysLeft)일 후)" }
            lines.append("곧 결제 예정: \(items.joined(separator: ", "))")
        }

        // 예산·할 일
        if !ctx.overBudgetCategories.isEmpty {
            lines.append("예산 초과 카테고리: \(ctx.overBudgetCategories.joined(separator: ", "))")
        }
        if !ctx.pendingChecklistItems.isEmpty {
            lines.append("미완료 할 일: \(ctx.pendingChecklistItems.prefix(3).joined(separator: ", "))")
        } else if !ctx.activeChecklists.isEmpty {
            lines.append("진행 중인 체크리스트: \(ctx.activeChecklists.prefix(2).joined(separator: ", "))")
        }

        if lines.count == 1 {
            lines.append("오늘 특별한 일정 없음")
        }

        return lines.joined(separator: "\n")
    }

    private func formatWon(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    // MARK: - 후처리

    private func sanitize(_ raw: String) -> String {
        var text = raw

        text = text.replacingOccurrences(of: "```[^`]*```", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*{1,2}([^*\n]+)\*{1,2}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\u[0-9a-fA-F]{4}"#, with: "", options: .regularExpression)

        let lines = text.components(separatedBy: .newlines)
        let firstLine = lines.first(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && t.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 })
        }) ?? lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? raw

        let quoteSet = CharacterSet(charactersIn: "\"\'\u{201C}\u{201D}\u{2018}\u{2019}")
        text = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteSet)

        text = text.unicodeScalars
            .filter { s in
                let v = s.value
                return v < 0x2600
                    || (v >= 0xAC00 && v <= 0xD7A3)
                    || (v >= 0x1100 && v <= 0x11FF)
                    || (v >= 0x3130 && v <= 0x318F)
            }
            .reduce("") { $0 + String($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 온점(.) 뒤에는 공백 한 칸을 넣어 다음 문장을 이어준다 (소수점은 제외)
        text = text.replacingOccurrences(of: #"(?<!\d)\.(?=\S)"#, with: ". ", options: .regularExpression)
        // 정규화 과정에서 생길 수 있는 중복 공백 정리
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    // MARK: - 시간대 레이블

    private func timePeriodLabel(_ hour: Int) -> String {
        switch hour {
        case 5..<11: return "오전"
        case 11..<14: return "점심"
        case 14..<18: return "오후"
        case 18..<22: return "저녁"
        default: return "밤"
        }
    }
}
