import Foundation
import Testing
@testable import chross

struct BillingCalculatorTests {

    @Test func noRateProducesZeroTotal() {
        let settings = BillingSettings(
            hourlyRate: 0,
            currencyCode: "EUR",
            rounding: .none,
            vatEnabled: false,
            vatRatePercent: 20,
            billingBase: .totalDuration
        )
        let result = BillingCalculator.calculate(activeSeconds: 3600, usage: [], settings: settings)
        #expect(result.subtotal == 0)
        #expect(result.total == 0)
    }

    @Test func oneHourAtFlatRateWithoutRounding() {
        let settings = BillingSettings(
            hourlyRate: 60,
            currencyCode: "EUR",
            rounding: .none,
            vatEnabled: false,
            vatRatePercent: 20,
            billingBase: .totalDuration
        )
        let result = BillingCalculator.calculate(activeSeconds: 3600, usage: [], settings: settings)
        #expect(result.subtotal == 60)
        #expect(result.total == 60)
    }

    @Test func roundsUpToNearestIncrement() {
        let settings = BillingSettings(
            hourlyRate: 60,
            currencyCode: "EUR",
            rounding: .fifteenMinutes,
            vatEnabled: false,
            vatRatePercent: 20,
            billingBase: .totalDuration
        )
        // 61 minutes should round up to 75 minutes (1.25h) at 60/h = 75
        let result = BillingCalculator.calculate(activeSeconds: 61 * 60, usage: [], settings: settings)
        #expect(result.roundedSeconds == 75 * 60)
        #expect(result.subtotal == 75)
    }

    @Test func appliesVATOnTopOfSubtotal() {
        let settings = BillingSettings(
            hourlyRate: 100,
            currencyCode: "EUR",
            rounding: .none,
            vatEnabled: true,
            vatRatePercent: 20,
            billingBase: .totalDuration
        )
        let result = BillingCalculator.calculate(activeSeconds: 3600, usage: [], settings: settings)
        #expect(result.subtotal == 100)
        #expect(result.vatAmount == 20)
        #expect(result.total == 120)
    }

    @Test func declaredItemsOnlyBaseIgnoresUndeclaredUsage() {
        let settings = BillingSettings(
            hourlyRate: 60,
            currencyCode: "EUR",
            rounding: .none,
            vatEnabled: false,
            vatRatePercent: 20,
            billingBase: .declaredItemsOnly
        )
        let usage = [
            UsageRecord(kind: .app, key: "com.apple.dt.Xcode", displayName: "Xcode", seconds: 1800, isDeclared: true),
            UsageRecord(kind: .app, key: "com.apple.mail", displayName: "Mail", seconds: 1800, isDeclared: false),
        ]
        let result = BillingCalculator.calculate(activeSeconds: 3600, usage: usage, settings: settings)
        // Only the declared 30 minutes (0.5h) should count, at 60/h = 30
        #expect(result.billableSeconds == 1800)
        #expect(result.subtotal == 30)
    }

    @Test func zeroSecondsStaysZeroEvenWithRounding() {
        let settings = BillingSettings(
            hourlyRate: 60,
            currencyCode: "EUR",
            rounding: .fifteenMinutes,
            vatEnabled: false,
            vatRatePercent: 20,
            billingBase: .totalDuration
        )
        let result = BillingCalculator.calculate(activeSeconds: 0, usage: [], settings: settings)
        #expect(result.roundedSeconds == 0)
        #expect(result.subtotal == 0)
    }
}

struct DomainNormalizerTests {

    @Test func bareDomainStaysAsIs() {
        #expect(DomainNormalizer.normalize("github.com") == "github.com")
    }

    @Test func stripsWwwPrefix() {
        #expect(DomainNormalizer.normalize("www.github.com") == "github.com")
    }

    @Test func extractsHostFromFullURLWithPathAndQuery() {
        #expect(DomainNormalizer.normalize("https://www.youtube.com/watch?v=abc123") == "youtube.com")
    }

    @Test func extractsHostFromBareDomainWithPath() {
        #expect(DomainNormalizer.normalize("google.com/search?q=chross") == "google.com")
    }

    @Test func isCaseInsensitive() {
        #expect(DomainNormalizer.normalize("GitHub.COM") == "github.com")
    }

    @Test func emptyInputReturnsNil() {
        #expect(DomainNormalizer.normalize("   ") == nil)
    }
}

struct HTTPRequestParserTests {

    @Test func parsesSimpleGetRequest() {
        let raw = "GET /status HTTP/1.1\r\nHost: 127.0.0.1:52847\r\n\r\n"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        #expect(req != nil)
        #expect(req?.method == "GET")
        #expect(req?.path == "/status")
        #expect(req?.body.isEmpty == true)
    }

    @Test func parsesPostWithJsonBody() {
        let json = "{\"url\":\"https://github.com\"}"
        let raw = "POST /session/sites HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        #expect(req != nil)
        #expect(req?.method == "POST")
        #expect(req?.path == "/session/sites")
        #expect(req?.body == Data(json.utf8))
    }

    @Test func parsesOptionsPreflight() {
        let raw = "OPTIONS /session/start HTTP/1.1\r\nAccess-Control-Request-Method: POST\r\n\r\n"
        let req = HTTPRequestParser.parse(Data(raw.utf8))
        #expect(req != nil)
        #expect(req?.method == "OPTIONS")
        #expect(req?.path == "/session/start")
    }

    @Test func incompleteBodyReturnsNilUntilAllBytesReceived() {
        let json = "{\"url\":\"https://github.com\"}"
        let partialRaw = "POST /session/sites HTTP/1.1\r\nContent-Length: \(json.utf8.count)\r\n\r\n{\"url\":\""
        let req = HTTPRequestParser.parse(Data(partialRaw.utf8))
        #expect(req == nil)
    }
}

struct ItemDisplayHelperTests {

    @Test func cleansWebsiteURLsToDomain() {
        let clean = ItemDisplayHelper.cleanDisplayName(
            key: "github.com",
            kind: .website,
            rawName: "https://www.github.com/pulls"
        )
        #expect(clean == "github.com")
    }

    @Test func preservesCleanAppNames() {
        let clean = ItemDisplayHelper.cleanDisplayName(
            key: "com.figma.Desktop",
            kind: .app,
            rawName: "Figma"
        )
        #expect(clean == "Figma")
    }

    @Test func cleansBundleIDsForKnownApps() {
        let clean = ItemDisplayHelper.cleanDisplayName(
            key: "com.apple.dt.Xcode",
            kind: .app,
            rawName: "com.apple.dt.Xcode"
        )
        #expect(clean == "Xcode")
    }
}
