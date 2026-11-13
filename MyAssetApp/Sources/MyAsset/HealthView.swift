import SwiftUI
import AppKit

// MARK: - 증상 가이드 데이터

struct SymptomGuide: Identifiable {
    let symptom: String
    let icon: String
    let departments: [String]
    let selfCare: String
    let redFlags: String

    var id: String { symptom }

    static let all: [SymptomGuide] = [
        .init(symptom: "발열·몸살", icon: "thermometer.medium",
              departments: ["내과", "가정의학과"],
              selfCare: "해열제 복용, 수분 충분히 섭취, 휴식. 38도 이상이 2일 넘게 지속되면 진료를 받으세요.",
              redFlags: "39도 이상 지속, 의식이 흐려짐, 심한 두통과 목 경직 동반 → 즉시 응급실"),
        .init(symptom: "기침·목 아픔", icon: "lungs",
              departments: ["이비인후과", "내과"],
              selfCare: "따뜻한 물 자주 마시기, 가습. 2주 이상 지속되는 기침은 진료가 필요합니다.",
              redFlags: "숨쉬기 힘듦, 피 섞인 가래, 입술이 파래짐 → 즉시 응급실"),
        .init(symptom: "복통·소화불량", icon: "fork.knife",
              departments: ["내과", "소화기내과"],
              selfCare: "자극적인 음식 피하기, 소화제 복용. 반복되면 내시경 검사를 고려하세요.",
              redFlags: "오른쪽 아랫배 심한 통증(충수염 의심), 구토와 고열 동반, 혈변 → 즉시 응급실"),
        .init(symptom: "두통·어지럼", icon: "brain.head.profile",
              departments: ["신경과"],
              selfCare: "수면·카페인 점검, 진통제. 잦은 두통은 패턴을 기록해 진료 시 보여주세요.",
              redFlags: "갑자기 시작된 극심한 두통, 한쪽 팔다리 마비, 발음 어눌함 → 즉시 119 (뇌졸중 의심)"),
        .init(symptom: "허리·관절 통증", icon: "figure.walk",
              departments: ["정형외과", "재활의학과"],
              selfCare: "무리한 운동 중단, 온찜질. 2주 이상 지속되면 영상 검사를 받아보세요.",
              redFlags: "다리 마비·감각 이상, 대소변 조절 안 됨 → 즉시 응급실"),
        .init(symptom: "피부 발진·두드러기", icon: "allergens",
              departments: ["피부과", "알레르기내과"],
              selfCare: "긁지 않기, 항히스타민제 복용, 원인 음식·약물 기록.",
              redFlags: "두드러기와 함께 호흡곤란·입술 부음 → 즉시 119 (아나필락시스 의심)"),
        .init(symptom: "눈 통증·충혈", icon: "eye",
              departments: ["안과"],
              selfCare: "렌즈 착용 중단, 눈 비비지 않기, 인공눈물.",
              redFlags: "갑작스러운 시력 저하, 빛 번쩍임과 날파리 증상 급증 → 당일 안과 진료"),
        .init(symptom: "귀·코 증상", icon: "ear",
              departments: ["이비인후과"],
              selfCare: "코 세척, 귀 후비지 않기.",
              redFlags: "갑자기 한쪽 귀가 안 들림 → 72시간 내 치료가 중요 (돌발성 난청)"),
        .init(symptom: "치아 통증", icon: "mouth",
              departments: ["치과"],
              selfCare: "진통제 복용, 차거나 뜨거운 음식 피하기. 미루면 치료 비용이 커집니다.",
              redFlags: "얼굴이 붓고 열이 남 → 당일 치과 또는 응급실"),
        .init(symptom: "배뇨 이상", icon: "drop",
              departments: ["비뇨의학과"],
              selfCare: "물 많이 마시기, 참지 않기.",
              redFlags: "소변에 피가 섞임, 옆구리 심한 통증과 고열 → 즉시 진료"),
        .init(symptom: "불면·불안·우울", icon: "moon.zzz",
              departments: ["정신건강의학과"],
              selfCare: "수면 패턴 기록, 카페인·음주 줄이기. 2주 이상 지속되면 전문 상담을 받아보세요. 진료 기록은 불이익 없이 보호됩니다.",
              redFlags: "자해·자살 생각이 들 때 → 자살예방상담 109 (24시간, 무료)"),
        .init(symptom: "생리통·부정출혈", icon: "heart.text.square",
              departments: ["산부인과"],
              selfCare: "진통제는 통증 시작 전 복용이 효과적. 주기 변화를 기록하세요.",
              redFlags: "실신할 정도의 통증, 임신 가능성 있는 상태의 출혈 → 즉시 진료"),
    ]
}

// MARK: - 건강·응급 화면

struct HealthView: View {
    @ObservedObject private var life = LifeStore.shared

    @State private var selectedSymptom: SymptomGuide? = SymptomGuide.all.first
    @State private var showContactForm = false
    @State private var editingContact: EmergencyContact?
    @State private var copiedPhone: String?
    @State private var checklistAdded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("건강·응급").font(.largeTitle.bold())
                    Text("혼자 아플 때 어디로 가야 할지, 빠르게 확인하세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                emergencyStrip

                HStack(alignment: .top, spacing: 20) {
                    symptomSection.frame(maxWidth: .infinity)
                    VStack(spacing: 20) {
                        contactsSection
                        medicineCard
                    }
                    .frame(width: 340)
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showContactForm) {
            ContactForm(editing: nil)
        }
        .sheet(item: $editingContact) { contact in
            ContactForm(editing: contact)
        }
    }

    // MARK: 응급 스트립

    private var emergencyStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "cross.circle.fill").foregroundStyle(Theme.red)
                    Text("응급상황이라면 119").font(.headline)
                }
                Text("생명이 위급하면 고민하지 말고 바로 전화하세요. 응급실 안내·구급상담도 119에서 합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            emergencyLink("응급의료포털 E-Gen", subtitle: "지금 문 연 병원·약국", url: "https://www.e-gen.or.kr")
            emergencyLink("자살예방상담 109", subtitle: "24시간 마음 상담", url: "https://www.129.go.kr")
            emergencyLink("보건복지상담 129", subtitle: "복지·의료비 상담", url: "https://www.129.go.kr")
        }
        .padding(18)
        .background(Theme.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.red.opacity(0.2), lineWidth: 1))
    }

    private func emergencyLink(_ title: String, subtitle: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.caption.weight(.semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                }
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: 증상 가이드

    private var symptomSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("증상별 진료과 찾기").font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                ForEach(SymptomGuide.all) { guide in
                    Button {
                        selectedSymptom = guide
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: guide.icon).font(.system(size: 16))
                            Text(guide.symptom).font(.caption.weight(.medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedSymptom?.id == guide.id ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.03))
                        .foregroundStyle(selectedSymptom?.id == guide.id ? Theme.accent : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(selectedSymptom?.id == guide.id ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let guide = selectedSymptom {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: guide.icon).font(.system(size: 20)).foregroundStyle(Theme.accent)
                        Text(guide.symptom).font(.title3.bold())
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Text("추천 진료과").font(.caption).foregroundStyle(.secondary)
                        ForEach(guide.departments, id: \.self) { dept in
                            Text(dept)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.12))
                                .foregroundStyle(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Label("이렇게 해보세요", systemImage: "lightbulb")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
                        Text(guide.selfCare).font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Label("이럴 땐 바로 병원·119", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                        Text(guide.redFlags).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.red.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("야간·휴일에 문 연 병원과 약국은 응급의료포털(E-Gen)에서 실시간으로 검색할 수 있어요.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(18)
                .card()
            }
        }
    }

    // MARK: 응급 연락처

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("응급 연락처").font(.headline)
                Spacer()
                Button {
                    editingContact = nil
                    showContactForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .controlSize(.small)
            }

            if life.contacts.isEmpty {
                Text("아플 때 연락할 가족·친구를 등록해두세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(life.contacts.enumerated()), id: \.element.id) { idx, contact in
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 26)).foregroundStyle(Theme.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(contact.name).font(.subheadline.weight(.medium))
                                    if !contact.relation.isEmpty {
                                        Text(contact.relation).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(contact.phone, forType: .string)
                                copiedPhone = contact.phone
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPhone = nil }
                            } label: {
                                Image(systemName: copiedPhone == contact.phone ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(copiedPhone == contact.phone ? Theme.green : .secondary)
                            .help("전화번호 복사")
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingContact = contact
                        }
                        .contextMenu {
                            Button("수정") {
                                editingContact = contact
                            }
                            Button("삭제", role: .destructive) { life.deleteContact(contact) }
                        }
                        if idx != life.contacts.count - 1 { Divider() }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: 상비약

    private var medicineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pills.fill").foregroundStyle(Theme.orange)
                Text("상비약 챙기기").font(.headline)
            }
            Text("해열제, 소화제, 밴드 — 아프기 전에 미리 준비해두세요.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                life.addChecklist(ChecklistTemplate.all.first { $0.name == "상비약 점검" }!.instantiate())
                checklistAdded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { checklistAdded = false }
            } label: {
                Label(checklistAdded ? "체크리스트에 추가됨" : "상비약 점검 체크리스트 만들기",
                      systemImage: checklistAdded ? "checkmark" : "checklist")
            }
            .disabled(checklistAdded)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - 연락처 폼

struct ContactForm: View {
    var editing: EmergencyContact?

    @ObservedObject private var life = LifeStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relation = ""
    @State private var phone = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "연락처 추가" : "연락처 수정").font(.title3.bold())
                Spacer()
            }
            .padding(20)

            Form {
                TextField("이름", text: $name, prompt: Text("예: 어머니"))
                TextField("관계", text: $relation, prompt: Text("예: 가족"))
                TextField("전화번호", text: $phone, prompt: Text("010-0000-0000"))
            }
            .formStyle(.grouped)

            HStack {
                if let editing {
                    Button("삭제", role: .destructive) {
                        life.deleteContact(editing)
                        dismiss()
                    }
                }
                Spacer()
                Button("취소") { dismiss() }
                Button(editing == nil ? "추가" : "저장") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(name.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 400, height: 300)
        .onAppear {
            guard let editing else { return }
            name = editing.name
            relation = editing.relation
            phone = editing.phone
        }
    }

    private func save() {
        var contact = editing ?? EmergencyContact(name: name)
        contact.name = name
        contact.relation = relation
        contact.phone = phone
        if editing == nil {
            life.addContact(contact)
        } else {
            life.updateContact(contact)
        }
        dismiss()
    }
}
