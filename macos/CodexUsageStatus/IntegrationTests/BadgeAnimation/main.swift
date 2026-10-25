import Foundation

@main
struct BadgeAnimationAudit {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("BADGE ANIMATION FAIL: \(message)\n", stderr)
                exit(1)
            }
            assertions += 1
        }
        func close(_ actual: Double, _ expected: Double) -> Bool {
            abs(actual - expected) < 0.000_001
        }

        let refresh = UsageBadgeTransition(
            fromFiveHour: 62,
            fromWeekly: 81,
            toFiveHour: 54,
            toWeekly: 84,
            startUptime: 40
        )
        check(refresh.duration == 0.36, "ordinary refresh uses the short transition")
        let refreshStart = refresh.frame(at: 40)
        check(refreshStart.fiveHourPercent == 62 && refreshStart.weeklyPercent == 81,
              "ordinary refresh starts at the last displayed values")
        check(refreshStart.resetHighlightAlpha == 0 && refreshStart.resetWindows.isEmpty,
              "ordinary refresh does not show a reset highlight")

        let refreshMiddle = refresh.frame(at: 40.18)
        check(close(refreshMiddle.fiveHourPercent, 55) && close(refreshMiddle.weeklyPercent, 83.625),
              "the eased midpoint interpolates both readings")
        check(refreshMiddle.fiveHourPercent < 62 && refreshMiddle.weeklyPercent > 81,
              "decreases and increases move continuously toward their targets")
        let refreshEnd = refresh.frame(at: 40 + refresh.duration)
        check(refreshEnd.isComplete, "ordinary refresh reaches its completed state")
        check(refreshEnd.fiveHourPercent == 54 && refreshEnd.weeklyPercent == 84,
              "ordinary refresh ends at the fresh readings")
        check(refresh.frame(at: 39).fiveHourPercent == 62,
              "a clock value before the start does not jump ahead")

        let reset = UsageBadgeTransition(
            fromFiveHour: 8,
            fromWeekly: 82,
            toFiveHour: 100,
            toWeekly: 78,
            startUptime: 100,
            resetWindows: [.fiveHour]
        )
        check(reset.duration == 0.92, "confirmed reset uses the longer recovery transition")
        let resetStart = reset.frame(at: 100)
        check(resetStart.fiveHourPercent == 8 && resetStart.resetHighlightAlpha == 1,
              "the green reset recovery begins at the previous reading")
        check(resetStart.resetWindows == [.fiveHour], "only the confirmed reset window is highlighted")

        let resetMiddle = reset.frame(at: 100 + reset.duration / 2)
        check(close(resetMiddle.fiveHourPercent, 88.5) && close(resetMiddle.weeklyPercent, 78.5),
              "reset and ordinary readings share one continuous frame")
        check(resetMiddle.resetHighlightAlpha == 1,
              "the reset highlight remains visible through the main recovery")
        let resetFade = reset.frame(at: 100 + reset.duration * 0.9)
        check(resetFade.resetHighlightAlpha > 0 && resetFade.resetHighlightAlpha < 1,
              "the reset highlight fades before the final neutral state")
        let resetEnd = reset.frame(at: 100 + reset.duration)
        check(resetEnd.isComplete && resetEnd.fiveHourPercent == 100 && resetEnd.weeklyPercent == 78,
              "the reset reaches its confirmed target without changing the other target")
        check(resetEnd.resetHighlightAlpha == 0,
              "the green highlight is gone when the reset transition completes")

        let bounded = UsageBadgeTransition(
            fromFiveHour: .infinity,
            fromWeekly: -12,
            toFiveHour: 145,
            toWeekly: .nan,
            startUptime: 0
        )
        check(bounded.fromFiveHour == 0 && bounded.fromWeekly == 0,
              "invalid starting values are safely bounded")
        check(bounded.toFiveHour == 100 && bounded.toWeekly == 0,
              "invalid target values are safely bounded")

        print("BADGE ANIMATION PASS: \(assertions) assertions; refresh interpolation and reset highlight timing")
    }
}
