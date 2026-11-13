import SwiftUI
import CoreLocation

// MARK: - 위치 모드

enum LocationMode: String, CaseIterable {
    case home    = "집"
    case current = "현재 위치"

    var icon: String {
        switch self {
        case .home:    return "house.fill"
        case .current: return "location.fill"
        }
    }
}

// MARK: - WeatherView

struct WeatherView: View {
    @ObservedObject private var store           = WeatherStore.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var locationMode: LocationMode = .home

    private var activeWeather: WeatherData? {
        locationMode == .home ? store.homeWeather : store.currentWeather
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // 위치 전환 피커
                locationPicker

                // 집에 있을 때 현재 위치 모드 배너
                if locationMode == .current {
                    currentLocationStatus
                }

                if let error = store.loadError {
                    errorBanner(error)
                }

                if let weather = activeWeather {
                    todayCard(weather)
                    if !weather.hourly.isEmpty {
                        hourlyCard(weather.hourly)
                    }
                    weeklyCard(weather.weekly)
                    footerNote
                } else if store.loadError == nil {
                    emptyState
                }
            }
            .padding(28)
        }
        .onAppear {
            store.refresh()
            if locationMode == .current {
                locationManager.requestUpdate()
            }
        }
        .onChange(of: locationMode) { _, mode in
            // 모드 전환 시에는 이미 로드된 날씨를 표시만 전환. 현재 위치 모드일 때만 위치 갱신 요청.
            if mode == .current {
                locationManager.requestUpdate()
            }
        }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("날씨").font(.largeTitle.bold())
                Text("오늘과 이번 주 날씨를 확인하세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let updatedAt = activeWeather?.updatedAt {
                    updatedBadge(updatedAt)
                }
            }
            Spacer()
        }
    }

    private func updatedBadge(_ iso: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.caption2)
            Text("마지막 업데이트  \(formattedDate(iso))")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - 위치 피커

    private var locationPicker: some View {
        HStack(spacing: 0) {
            ForEach(LocationMode.allCases, id: \.self) { mode in
                Button {
                    // 상태 변경은 즉시 반영(탭 드롭 방지). 시각 전환은 아래 .animation(value:)이 처리.
                    locationMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon).font(.caption)
                        Text(mode.rawValue).font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(locationMode == mode ? Theme.accent.opacity(0.12) : Color.clear)
                    .foregroundStyle(locationMode == mode ? Theme.accent : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if mode == .home {
                    Divider().frame(height: 20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: 300)
        .animation(.easeInOut(duration: 0.18), value: locationMode)
    }

    // MARK: - 현재 위치 상태 배너

    @ViewBuilder
    private var currentLocationStatus: some View {
        let isDenied = locationManager.authStatus == .denied || locationManager.authStatus == .restricted
        if isDenied {
            // 권한 거부
            HStack(spacing: 10) {
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("위치 접근 권한이 없습니다")
                        .font(.subheadline.weight(.semibold))
                    Text("시스템 환경설정 → 개인 정보 보호 → 위치 서비스에서 허용해 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        } else if locationManager.isLoading {
            // 위치 확인 중
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.8)
                Text("현재 위치를 확인하는 중…")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        } else if locationManager.isAtHome, locationManager.currentLocation != nil {
            // 집에 있음
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("지금 집에 계시는군요")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("현재 위치가 집(\(locationManager.currentAddress))과 일치합니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
            )

        } else if let loc = locationManager.currentLocation {
            // 외부 위치
            let distance = locationManager.distanceFromHome.map { "집에서 약 \(Int($0 / 1000))km · " } ?? ""
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationManager.currentAddress.isEmpty ? "현재 위치" : locationManager.currentAddress)
                        .font(.subheadline.weight(.semibold))
                    Text("\(distance)\(String(format: "%.4f", loc.coordinate.latitude)), \(String(format: "%.4f", loc.coordinate.longitude))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.teal.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 오류 배너

    private func errorBanner(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(Theme.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 오늘 날씨 카드

    private func todayCard(_ weather: WeatherData) -> some View {
        let today = weather.today
        return VStack(alignment: .leading, spacing: 16) {

            // 기온 + 아이콘
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: locationMode == .home ? "house.fill" : "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(weather.location)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(today.condition)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(today.color)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(today.displayTemp)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                        Text("°C")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                            .offset(y: -16)
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.high").foregroundStyle(Theme.red)
                            Text("최고 \(today.tempHigh)°")
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.low").foregroundStyle(Theme.accent)
                            Text("최저 \(today.tempLow)°")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: today.sfSymbol)
                    .font(.system(size: 76))
                    .foregroundStyle(today.color)
                    .symbolRenderingMode(.multicolor)
                    .padding(.top, 4)
            }

            // 설명
            if let desc = today.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 세부 지표
            if today.humidity != nil || today.windSpeed != nil || today.uvIndex != nil {
                Divider()
                HStack(spacing: 12) {
                    if let h = today.humidity {
                        detailChip(icon: "humidity", label: "습도", value: "\(h)%", color: Theme.accent)
                    }
                    if let w = today.windSpeed {
                        detailChip(icon: "wind", label: "바람", value: String(format: "%.1fm/s", w), color: Theme.teal)
                    }
                    if let uv = today.uvIndex {
                        detailChip(icon: "sun.max.fill", label: "자외선", value: uvLabel(uv), color: uvColor(uv))
                    }
                    Spacer()
                }
            }
        }
        .padding(22)
        .card()
    }

    private func detailChip(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 시간별 날씨 카드

    private func hourlyCard(_ hours: [WeatherHour]) -> some View {
        let currentHour = Calendar.current.component(.hour, from: Date())

        return VStack(alignment: .leading, spacing: 14) {
            Text("시간별 날씨").font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(hours) { hour in
                        let h = Int(hour.time.prefix(2)) ?? -1
                        hourCell(hour, isCurrent: h == currentHour)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .card()
    }

    private func hourCell(_ hour: WeatherHour, isCurrent: Bool) -> some View {
        let timeLabel = (Int(hour.time.prefix(2)) ?? 0).description + "시"

        return VStack(spacing: 7) {
            Text(timeLabel)
                .font(.caption2.weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Theme.accent : .secondary)

            Image(systemName: hour.sfSymbol)
                .font(.system(size: 20))
                .foregroundStyle(hour.color)
                .symbolRenderingMode(.multicolor)
                .frame(height: 26)

            Text("\(hour.temp)°")
                .font(.subheadline.weight(isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? Theme.accent : .primary)

            // 강수확률이 있으면 강수확률, 없으면 습도 표시
            if hour.precipProbability > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.accent)
                    Text("\(hour.precipProbability)%")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                }
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "humidity")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text("\(hour.humidity)%")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 56)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(isCurrent ? Theme.accent.opacity(0.08) : Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Theme.accent.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - 이번 주 날씨 카드

    private func weeklyCard(_ days: [WeatherDay]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이번 주 날씨").font(.headline)

            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { idx, day in
                    VStack(spacing: 7) {
                        Text(day.dayLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(idx == 0 ? Theme.accent : .secondary)

                        Image(systemName: day.sfSymbol)
                            .font(.system(size: 22))
                            .foregroundStyle(day.color)
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 30)

                        Text(day.condition)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("\(day.tempHigh)°")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(idx == 0 ? Theme.accent : .primary)

                        Text("\(day.tempLow)°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .background(idx == 0 ? Theme.accent.opacity(0.07) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if idx < days.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .card()
    }

    // MARK: - 푸터

    private var footerNote: some View {
        Text("Claude 자율화 에이전트가 자동 업데이트합니다. 현재 위치 날씨는 앱 실행 중 위치를 감지하여 예약 작업 시 함께 업데이트됩니다.")
            .font(.caption2).foregroundStyle(.quaternary)
    }

    // MARK: - UV 헬퍼

    private func uvLabel(_ idx: Int) -> String {
        switch idx {
        case 0...2:  return "낮음 (\(idx))"
        case 3...5:  return "보통 (\(idx))"
        case 6...7:  return "높음 (\(idx))"
        case 8...10: return "매우 높음 (\(idx))"
        default:     return "위험 (\(idx))"
        }
    }

    private func uvColor(_ idx: Int) -> Color {
        switch idx {
        case 0...2:  return Theme.green
        case 3...5:  return Theme.yellow
        case 6...7:  return Theme.orange
        case 8...10: return Theme.red
        default:     return Theme.purple
        }
    }

    // MARK: - 날짜 포맷

    private func formattedDate(_ iso: String) -> String {
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: iso) { return koDateString(d) }
        let p2 = ISO8601DateFormatter()
        p2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p2.date(from: iso) { return koDateString(d) }
        return iso
    }

    private func koDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 a h:mm"
        return f.string(from: date)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.teal)
                .symbolRenderingMode(.multicolor)

            VStack(spacing: 8) {
                Text("날씨 정보가 없습니다").font(.title3.bold())
                Text("Claude 자율화 에이전트가 자동으로 날씨를 가져옵니다.\n파일이 생성되면 새로고침 버튼을 눌러주세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("데이터 파일 경로").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(WeatherStore.dataURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(WeatherStore.dataURL.path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.caption)
                    }
                    .controlSize(.small)
                    .help("경로 복사")
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
