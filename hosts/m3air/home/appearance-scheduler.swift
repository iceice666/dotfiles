import CoreLocation
import Foundation

final class AppearanceScheduler: NSObject, CLLocationManagerDelegate {
  private let sunriseOffset: TimeInterval = 30 * 60
  private let sunsetOffset: TimeInterval = -30 * 60
  private let zenith = 90.833

  private let locationManager = CLLocationManager()
  private var didFinish = false

  func run() {
    locationManager.delegate = self

    guard CLLocationManager.locationServicesEnabled() else {
      log("Location Services are disabled.")
      finish(exitCode: 1)
      return
    }

    let status = locationManager.authorizationStatus
    log("Authorization status: \(status.rawValue)")

    switch status {
    case .authorizedAlways:
      locationManager.requestLocation()
    case .notDetermined:
      log("Requesting location permission.")
      locationManager.requestAlwaysAuthorization()
    case .restricted, .denied:
      log("Location permission denied. Open the app once to grant access in System Settings.")
      finish(exitCode: 1)
    @unknown default:
      log("Unknown location authorization status: \(status.rawValue)")
      finish(exitCode: 1)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    log("Authorization changed: \(status.rawValue)")

    switch status {
    case .authorizedAlways:
      manager.requestLocation()
    case .restricted, .denied:
      log("Location permission denied. Open the app once to grant access in System Settings.")
      finish(exitCode: 1)
    default:
      break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      log("Location Services returned no coordinates.")
      finish(exitCode: 1)
      return
    }

    let now = Date()
    let timeZone = TimeZone.current

    guard
      let sunrise = solarEvent(
        for: now,
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        timeZone: timeZone,
        isSunrise: true
      ),
      let sunset = solarEvent(
        for: now,
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        timeZone: timeZone,
        isSunrise: false
      )
    else {
      log("Could not calculate sunrise or sunset for the current location.")
      finish(exitCode: 1)
      return
    }

    let lightStart = sunrise.addingTimeInterval(sunriseOffset)
    let darkStart = sunset.addingTimeInterval(sunsetOffset)
    let shouldUseDarkMode = now < lightStart || now >= darkStart

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    log("Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    log("Sunrise+30m: \(formatter.string(from: lightStart))")
    log("Sunset-30m: \(formatter.string(from: darkStart))")

    if currentDarkMode() == shouldUseDarkMode {
      log("Appearance already matches target mode.")
      finish(exitCode: 0)
      return
    }

    setDarkMode(enabled: shouldUseDarkMode)
    finish(exitCode: 0)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    log("Failed to get location: \(error.localizedDescription)")
    finish(exitCode: 1)
  }

  private func currentDarkMode() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", "-g", "AppleInterfaceStyle"]

    let output = Pipe()
    let stderr = Pipe()
    process.standardOutput = output
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      log("Failed to read current appearance: \(error.localizedDescription)")
      return false
    }

    if process.terminationStatus != 0 {
      return false
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.caseInsensitiveCompare("Dark") == .orderedSame
  }

  private func setDarkMode(enabled: Bool) {
    let darkModeValue = enabled ? "true" : "false"
    let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(darkModeValue)"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let stderr = Pipe()
    process.standardError = stderr

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      log("Failed to switch appearance: \(error.localizedDescription)")
      return
    }

    if process.terminationStatus == 0 {
      let modeName = enabled ? "dark" : "light"
      log("Switched appearance to \(modeName) mode.")
    } else {
      let data = stderr.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
      log("Failed to switch appearance: \(message)")
    }
  }

  private func solarEvent(
    for date: Date,
    latitude: Double,
    longitude: Double,
    timeZone: TimeZone,
    isSunrise: Bool
  ) -> Date? {
    let calendar = Calendar(identifier: .gregorian)
    let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    let lngHour = longitude / 15.0
    let baseHour = isSunrise ? 6.0 : 18.0
    let t = Double(dayOfYear) + ((baseHour - lngHour) / 24.0)
    let meanAnomaly = (0.9856 * t) - 3.289

    var trueLongitude = meanAnomaly
    trueLongitude += 1.916 * sin(degreesToRadians(meanAnomaly))
    trueLongitude += 0.020 * sin(2.0 * degreesToRadians(meanAnomaly))
    trueLongitude += 282.634
    trueLongitude = normalizedDegrees(trueLongitude)

    var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
    rightAscension = normalizedDegrees(rightAscension)

    let trueLongitudeQuadrant = floor(trueLongitude / 90.0) * 90.0
    let rightAscensionQuadrant = floor(rightAscension / 90.0) * 90.0
    rightAscension += trueLongitudeQuadrant - rightAscensionQuadrant
    rightAscension /= 15.0

    let sinDeclination = 0.39782 * sin(degreesToRadians(trueLongitude))
    let cosDeclination = cos(asin(sinDeclination))
    let cosLocalHour = (
      cos(degreesToRadians(zenith))
      - (sinDeclination * sin(degreesToRadians(latitude)))
    ) / (cosDeclination * cos(degreesToRadians(latitude)))

    if cosLocalHour < -1.0 || cosLocalHour > 1.0 {
      return nil
    }

    var localHour = radiansToDegrees(acos(cosLocalHour))
    localHour = isSunrise ? (360.0 - localHour) : localHour
    localHour /= 15.0

    let localMeanTime = localHour + rightAscension - (0.06571 * t) - 6.622
    let universalTime = normalizedHours(localMeanTime - lngHour)
    let localTime = universalTime + (Double(timeZone.secondsFromGMT(for: date)) / 3600.0)
    let normalizedLocalTime = normalizedHours(localTime)

    let startOfDay = calendar.startOfDay(for: date)
    return startOfDay.addingTimeInterval(normalizedLocalTime * 3600.0)
  }

  private func normalizedDegrees(_ value: Double) -> Double {
    value.truncatingRemainder(dividingBy: 360.0).mod(360.0)
  }

  private func normalizedHours(_ value: Double) -> Double {
    value.truncatingRemainder(dividingBy: 24.0).mod(24.0)
  }

  private func degreesToRadians(_ value: Double) -> Double {
    value * .pi / 180.0
  }

  private func radiansToDegrees(_ value: Double) -> Double {
    value * 180.0 / .pi
  }

  private func log(_ message: String) {
    print("[appearance-scheduler] \(message)")
  }

  private func finish(exitCode: Int32) {
    guard !didFinish else {
      return
    }

    didFinish = true
    CFRunLoopStop(CFRunLoopGetMain())
    exit(exitCode)
  }
}

private extension Double {
  func mod(_ modulus: Double) -> Double {
    let remainder = truncatingRemainder(dividingBy: modulus)
    return remainder >= 0 ? remainder : remainder + modulus
  }
}

let scheduler = AppearanceScheduler()
scheduler.run()

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
  print("[appearance-scheduler] Timed out waiting for location services.")
  CFRunLoopStop(CFRunLoopGetMain())
  exit(1)
}

CFRunLoopRun()
