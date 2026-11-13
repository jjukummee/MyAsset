import SwiftUI

// MARK: - 혜택 데이터 모델 (Codable — benefits.json 연동)

struct BenefitInfo: Codable, Identifiable {
    let name: String
    let summary: String          // 한 줄 요약 (지원 내용)
    let eligibility: String      // 대상 조건 설명
    let agency: String
    let urlString: String
    let deadlineNote: String
    let ageMin: Int?             // 만 나이 하한, nil = 제한 없음
    let ageMax: Int?             // 만 나이 상한, nil = 제한 없음
    let regions: [String]        // 빈 배열 = 전국

    var id: String { name }
    var url: URL? { URL(string: urlString) }
    var ageRange: ClosedRange<Int>? {
        guard let lo = ageMin, let hi = ageMax else { return nil }
        return lo...hi
    }

    static let regions = ["서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
                          "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주"]
}

struct BenefitsData: Codable {
    var updatedAt: String
    var benefits: [BenefitInfo]
}

// MARK: - 혜택 스토어

@MainActor
final class BenefitsStore: ObservableObject {
    static let shared = BenefitsStore()

    @Published private(set) var data: BenefitsData?

    static var dataURL: URL {
        MyAssetFiles.directory.appendingPathComponent("benefits.json")
    }

    /// JSON 파일이 없을 때 표시할 기본 데이터
    static let fallbackCatalog: [BenefitInfo] = [
        .init(name: "청년월세 특별지원",
              summary: "월 최대 20만원 × 12개월 월세 지원",
              eligibility: "만 19~34세 무주택 청년 · 보증금 5천만원 이하 등 요건",
              agency: "국토교통부", urlString: "https://www.bokjiro.go.kr",
              deadlineNote: "지자체별 공고 — 복지로에서 확인",
              ageMin: 19, ageMax: 34, regions: []),
        .init(name: "청년도약계좌",
              summary: "5년 만기 시 정부기여금 + 비과세 (최대 5천만원 목돈)",
              eligibility: "만 19~34세 · 개인소득 7,500만원 이하",
              agency: "서민금융진흥원", urlString: "https://www.kinfa.or.kr",
              deadlineNote: "매월 신청 가능",
              ageMin: 19, ageMax: 34, regions: []),
        .init(name: "청년내일저축계좌",
              summary: "본인 10만원 저축 시 정부가 10~30만원 추가 적립 (3년)",
              eligibility: "만 19~34세 근로 중인 저소득 청년",
              agency: "보건복지부", urlString: "https://www.bokjiro.go.kr",
              deadlineNote: "연 1회 모집 — 상반기 공고 확인",
              ageMin: 19, ageMax: 34, regions: []),
        .init(name: "K-패스",
              summary: "대중교통비 20~53% 환급 (월 15회 이상 이용 시)",
              eligibility: "누구나 · 청년(만 19~34세)은 30% 환급",
              agency: "국토교통부", urlString: "https://korea-pass.kr",
              deadlineNote: "상시 발급",
              ageMin: nil, ageMax: nil, regions: []),
        .init(name: "근로장려금",
              summary: "근로 가구에 최대 330만원 지급",
              eligibility: "소득·재산 요건 충족 근로/사업 가구",
              agency: "국세청", urlString: "https://www.hometax.go.kr",
              deadlineNote: "5월 정기신청 (기한 후 신청 시 감액)",
              ageMin: nil, ageMax: nil, regions: []),
        .init(name: "국민내일배움카드",
              summary: "직업훈련비 300~500만원 지원 (5년간)",
              eligibility: "취업 준비생·재직자 대부분 신청 가능",
              agency: "고용노동부", urlString: "https://www.hrd.go.kr",
              deadlineNote: "상시 발급",
              ageMin: nil, ageMax: nil, regions: []),
        .init(name: "청년 국가기술자격시험 응시료 지원",
              summary: "국가기술자격 응시료 50% 할인 (연 3회)",
              eligibility: "만 34세 이하 청년",
              agency: "한국산업인력공단", urlString: "https://www.q-net.or.kr",
              deadlineNote: "상시 적용",
              ageMin: 0, ageMax: 34, regions: []),
        .init(name: "에너지바우처",
              summary: "여름·겨울 냉난방비 지원",
              eligibility: "기초생활수급 등 에너지 취약계층",
              agency: "산업통상자원부", urlString: "https://www.energyv.or.kr",
              deadlineNote: "5~12월 읍면동 주민센터 신청",
              ageMin: nil, ageMax: nil, regions: []),
        .init(name: "서울 청년수당",
              summary: "월 50만원 × 최대 6개월 활동지원금",
              eligibility: "서울 거주 만 19~34세 미취업 청년",
              agency: "서울시", urlString: "https://youth.seoul.go.kr",
              deadlineNote: "연 1~2회 모집 공고",
              ageMin: 19, ageMax: 34, regions: ["서울"]),
        .init(name: "경기도 청년기본소득",
              summary: "분기별 25만원 지역화폐 지급",
              eligibility: "경기도 3년 이상 거주 만 24세",
              agency: "경기도", urlString: "https://apply.jobaba.net",
              deadlineNote: "분기별 신청 기간 확인",
              ageMin: 24, ageMax: 24, regions: ["경기"]),
    ]

    var catalog: [BenefitInfo] { data?.benefits ?? Self.fallbackCatalog }
    var updatedAt: String? { data?.updatedAt }

    private init() { load() }

    func refresh() {
        objectWillChange.send()
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.dataURL.path) else { return }
        do {
            let raw = try Data(contentsOf: Self.dataURL)
            data = try JSONDecoder().decode(BenefitsData.self, from: raw)
        } catch {
            print("BenefitsStore load error: \(error)")
        }
    }
}

// MARK: - 혜택 화면

struct BenefitsView: View {
    @ObservedObject private var life = LifeStore.shared
    @ObservedObject private var store = BenefitsStore.shared

    @State private var birthYearText = ""
    @State private var region = ""
    @State private var showAll = false
    @State private var savedMessage = false

    private var birthYear: Int? { Int(birthYearText.trimmingCharacters(in: .whitespaces)) }

    private var age: Int? {
        guard let birthYear, birthYear > 1900 else { return nil }
        return Calendar.current.component(.year, from: Date()) - birthYear
    }

    private var hasProfile: Bool { age != nil || !region.isEmpty }

    private var matched: [BenefitInfo] { store.catalog.filter { matches($0) } }
    private var unmatched: [BenefitInfo] { store.catalog.filter { !matches($0) } }

    private func matches(_ benefit: BenefitInfo) -> Bool {
        if let range = benefit.ageRange, let age, !range.contains(age) { return false }
        if !benefit.regions.isEmpty, !region.isEmpty, !benefit.regions.contains(region) { return false }
        if !benefit.regions.isEmpty, region.isEmpty { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("혜택·지원금").font(.largeTitle.bold())
                    Text("나이와 지역을 입력하면 받을 수 있는 정부·지자체 혜택을 추려드립니다.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let updatedAt = store.updatedAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock").font(.caption2)
                            Text("마지막 업데이트  \(formattedDate(updatedAt))")
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }

                profileCard

                if hasProfile {
                    HStack(spacing: 8) {
                        Text("맞춤 혜택 \(matched.count)건").font(.headline)
                        if let age {
                            Text("약 \(age)세\(region.isEmpty ? "" : " · \(region)") 기준 (추정)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("전체 보기", isOn: $showAll).toggleStyle(.switch).controlSize(.small)
                    }
                    benefitGrid(matched)
                    if showAll && !unmatched.isEmpty {
                        Text("조건이 맞지 않는 혜택").font(.headline).padding(.top, 4)
                        benefitGrid(unmatched).opacity(0.6)
                    }
                } else {
                    Text("전체 혜택 \(store.catalog.count)건").font(.headline)
                    benefitGrid(store.catalog)
                }

                portalLinks

                // 업데이트 푸터
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(.tertiary)
                    if let updatedAt = store.updatedAt {
                        Text("업데이트: \(formattedDate(updatedAt))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { store.refresh() } label: {
                        Label("새로고침", systemImage: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                Text("※ 지원 내용과 조건은 변경될 수 있습니다. 신청 전 반드시 공식 사이트에서 최신 공고를 확인하세요. 나이는 만 나이 기준 추정치입니다.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(28)
        }
        .onAppear {
            if let saved = life.profile.birthYear { birthYearText = String(saved) }
            region = life.profile.region
            store.refresh()
        }
    }

    // MARK: 프로필

    private var profileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 24)).foregroundStyle(Theme.accent)
            TextField("출생연도 (예: 1999)", text: $birthYearText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Picker("지역", selection: $region) {
                Text("지역 선택").tag("")
                ForEach(BenefitInfo.regions, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 150)
            Button("저장") {
                life.saveProfile(birthYear: birthYear, region: region)
                savedMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedMessage = false }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            if savedMessage {
                Label("저장됨", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.green)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    // MARK: 혜택 카드

    private func benefitGrid(_ benefits: [BenefitInfo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
            ForEach(benefits) { benefit in
                benefitCard(benefit)
            }
        }
    }

    private func benefitCard(_ benefit: BenefitInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(benefit.name).font(.headline)
                Spacer()
                Text(benefit.agency)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.1))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Text(benefit.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.green)
            Text(benefit.eligibility)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack {
                Label(benefit.deadlineNote, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(Theme.orange)
                    .lineLimit(1)
                Spacer()
                if let url = benefit.url {
                    Link(destination: url) {
                        HStack(spacing: 3) {
                            Text("신청 안내")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: 날짜 포맷

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "M월 d일 a h:mm"
        return df.string(from: date)
    }

    // MARK: 포털 링크

    private var portalLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("더 많은 혜택 찾아보기").font(.headline)
            HStack(spacing: 12) {
                portalLink("복지로", subtitle: "복지서비스 모음", url: "https://www.bokjiro.go.kr")
                portalLink("보조금24", subtitle: "정부24 맞춤 혜택", url: "https://www.gov.kr")
                portalLink("온통청년", subtitle: "청년정책 통합", url: "https://www.youthcenter.go.kr")
                portalLink("홈택스", subtitle: "장려금·환급", url: "https://www.hometax.go.kr")
            }
        }
    }

    private func portalLink(_ title: String, subtitle: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }
}
