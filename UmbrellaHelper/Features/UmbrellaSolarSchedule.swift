import CoreLocation
import SwiftUI

enum UmbrellaSolarPhase: String {
    case night = "Night"
    case morning = "Morning"
    case midday = "Midday"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var detail: String {
        switch self {
        case .night: return "Holding night brightness"
        case .morning: return "Brightening toward midday"
        case .midday: return "Peak daytime brightness"
        case .afternoon: return "Easing down from midday"
        case .evening: return "Dimming toward night"
        }
    }
}

enum UmbrellaSolarSchedule {
    static let minutesPerDay = 1440

    /// 0 = night floor, 1 = midday peak. Uses a sine curve between twilight bounds.
    static func daylightProgress(
        at minutes: Int,
        sunrise: Int,
        sunset: Int,
        transition: Int
    ) -> Float {
        let now = wrap(minutes)
        let padding = max(0, transition)
        let start = wrap(sunrise - padding)
        let end = wrap(sunset + padding)
        let duration = forwardDistance(from: start, to: end)
        guard duration > 0 else { return 0 }

        let elapsed = forwardDistance(from: start, to: now)
        if elapsed >= duration { return 0 }

        let t = Float(elapsed) / Float(duration)
        return sin(t * .pi)
    }

    static func middayMinutes(sunrise: Int, sunset: Int) -> Int {
        let halfDay = forwardDistance(from: wrap(sunrise), to: wrap(sunset)) / 2
        return wrap(sunrise + halfDay)
    }

    static func phase(
        at minutes: Int,
        sunrise: Int,
        sunset: Int,
        transition: Int
    ) -> UmbrellaSolarPhase {
        let progress = daylightProgress(
            at: minutes,
            sunrise: sunrise,
            sunset: sunset,
            transition: transition
        )
        if progress <= 0.02 { return .night }

        let now = wrap(minutes)
        let start = wrap(sunrise - max(0, transition))
        let midday = middayMinutes(sunrise: sunrise, sunset: sunset)
        let elapsedNow = forwardDistance(from: start, to: now)
        let elapsedMidday = forwardDistance(from: start, to: midday)
        let elapsedSunset = forwardDistance(from: start, to: wrap(sunset))

        if elapsedNow < elapsedMidday {
            return progress >= 0.92 ? .midday : .morning
        }
        if progress >= 0.92 { return .midday }
        if elapsedNow < elapsedSunset { return .afternoon }
        return .evening
    }

    static func statusText(
        at minutes: Int,
        sunrise: Int,
        sunset: Int,
        transition: Int
    ) -> String {
        let phase = phase(at: minutes, sunrise: sunrise, sunset: sunset, transition: transition)
        return "\(phase.rawValue) · \(phase.detail)"
    }

    static func minutesOfDay(from date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        let ns = coordinate.latitude >= 0 ? "N" : "S"
        let ew = coordinate.longitude >= 0 ? "E" : "W"
        return String(
            format: "Location: %.1f°%@, %.1f°%@",
            abs(coordinate.latitude),
            ns,
            abs(coordinate.longitude),
            ew
        )
    }

    /// NOAA solar-calculator approximation. Returns local civil sunrise/sunset, or nil in polar day/night.
    static func sunTimes(
        date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone = .current
    ) -> (sunrise: Int, sunset: Int)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let tzHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

        let gamma = 2 * Double.pi / 365 * Double(dayOfYear - 1)
        let eqTime = 229.18 * (
            0.000075
                + 0.001868 * cos(gamma)
                - 0.032077 * sin(gamma)
                - 0.014615 * cos(2 * gamma)
                - 0.040849 * sin(2 * gamma)
        )
        let decl =
            0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let latRad = latitude * Double.pi / 180
        let zenith = 90.833 * Double.pi / 180
        let haArg = cos(zenith) / (cos(latRad) * cos(decl)) - tan(latRad) * tan(decl)
        guard haArg >= -1, haArg <= 1 else { return nil }

        let hourAngle = acos(haArg) * 180 / Double.pi
        let sunriseUTC = 720 - 4 * (longitude + hourAngle) - eqTime
        let sunsetUTC = 720 - 4 * (longitude - hourAngle) - eqTime

        return (
            wrap(Int((sunriseUTC + tzHours * 60).rounded())),
            wrap(Int((sunsetUTC + tzHours * 60).rounded()))
        )
    }

    static func wrap(_ minutes: Int) -> Int {
        let period = minutesPerDay
        return ((minutes % period) + period) % period
    }

    static func forwardDistance(from start: Int, to end: Int) -> Int {
        let delta = wrap(end) - wrap(start)
        return delta >= 0 ? delta : delta + minutesPerDay
    }
}

struct UmbrellaDayCurveView: View {
    var sunriseMinutes: Int
    var sunsetMinutes: Int
    var transitionMinutes: Int
    var nowMinutes: Int
    var height: CGFloat = 72

    var body: some View {
        Canvas { context, size in
            let samples = 96
            var curve = Path()
            var fill = Path()
            let topPad: CGFloat = 6
            let bottomPad: CGFloat = 10
            let plotHeight = max(1, size.height - topPad - bottomPad)

            func point(for minutes: Int) -> CGPoint {
                let progress = UmbrellaSolarSchedule.daylightProgress(
                    at: minutes,
                    sunrise: sunriseMinutes,
                    sunset: sunsetMinutes,
                    transition: transitionMinutes
                )
                let x = size.width * CGFloat(UmbrellaSolarSchedule.wrap(minutes))
                    / CGFloat(UmbrellaSolarSchedule.minutesPerDay - 1)
                let y = topPad + (1 - CGFloat(progress)) * plotHeight
                return CGPoint(x: x, y: y)
            }

            for index in 0...samples {
                let minutes = Int(round(Double(index) / Double(samples) * Double(UmbrellaSolarSchedule.minutesPerDay - 1)))
                let pt = point(for: minutes)
                if index == 0 {
                    curve.move(to: pt)
                    fill.move(to: CGPoint(x: pt.x, y: topPad + plotHeight))
                    fill.addLine(to: pt)
                } else {
                    curve.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }
            fill.addLine(to: CGPoint(x: size.width, y: topPad + plotHeight))
            fill.closeSubpath()

            context.fill(fill, with: .color(Color.orange.opacity(0.18)))
            context.stroke(curve, with: .color(Color.orange), lineWidth: 2)

            let now = point(for: nowMinutes)
            let marker = Path(ellipseIn: CGRect(x: now.x - 4, y: now.y - 4, width: 8, height: 8))
            context.fill(marker, with: .color(Color.orange))
            context.stroke(marker, with: .color(Color.white.opacity(0.85)), lineWidth: 1)

            let barY = size.height - 5
            let start = UmbrellaSolarSchedule.wrap(sunriseMinutes - transitionMinutes)
            let end = UmbrellaSolarSchedule.wrap(sunsetMinutes + transitionMinutes)
            let startX = size.width * CGFloat(start) / CGFloat(UmbrellaSolarSchedule.minutesPerDay - 1)
            let endX = size.width * CGFloat(end) / CGFloat(UmbrellaSolarSchedule.minutesPerDay - 1)
            var nightBar = Path()
            nightBar.addRoundedRect(
                in: CGRect(x: 0, y: barY, width: size.width, height: 3),
                cornerSize: CGSize(width: 1.5, height: 1.5)
            )
            context.fill(nightBar, with: .color(Color.primary.opacity(0.12)))

            var dayBar = Path()
            if startX <= endX {
                dayBar.addRoundedRect(
                    in: CGRect(x: startX, y: barY, width: max(2, endX - startX), height: 3),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            } else {
                dayBar.addRect(CGRect(x: startX, y: barY, width: size.width - startX, height: 3))
                dayBar.addRect(CGRect(x: 0, y: barY, width: endX, height: 3))
            }
            context.fill(dayBar, with: .color(Color.orange.opacity(0.7)))
        }
        .frame(height: height)
        .accessibilityLabel("Daytime brightness curve")
        .accessibilityValue(
            UmbrellaSolarSchedule.statusText(
                at: nowMinutes,
                sunrise: sunriseMinutes,
                sunset: sunsetMinutes,
                transition: transitionMinutes
            )
        )
    }
}

@MainActor
final class UmbrellaLocationProvider: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onPlaceName: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 2000
    }

    func start() {
        isRunning = true
        handleAuthorization(manager.authorizationStatus)
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
    }

    func refresh() {
        guard isRunning else { return }
        requestFixIfAuthorized()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.onStatus?("Couldn’t read location — \(message)")
        }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard isRunning else { return }
        switch status {
        case .notDetermined:
            onStatus?("Waiting for location permission…")
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onStatus?("Location permission denied — using manual sunrise and sunset.")
        default:
            requestFixIfAuthorized()
        }
    }

    private func requestFixIfAuthorized() {
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            return
        default:
            manager.requestLocation()
        }
    }

    private func handle(_ location: CLLocation) {
        let coordinate = location.coordinate
        onLocation?(coordinate)
        onStatus?(UmbrellaSolarSchedule.coordinateLabel(coordinate))
        reverseGeocode(location)
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                if let mark = marks?.first {
                    let parts = [mark.locality, mark.administrativeArea].compactMap { $0 }
                    if !parts.isEmpty {
                        self.onPlaceName?(parts.joined(separator: ", "))
                        return
                    }
                }
                self.onPlaceName?(UmbrellaSolarSchedule.coordinateLabel(location.coordinate))
            }
        }
    }
}
