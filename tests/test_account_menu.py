"""Check the native menu with sample usage; never load or switch real accounts."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

# Compile in one source file so private UI helpers remain private in the app.
CHECKS = r'''
private final class AccountTitlePreview: NSView {
    let drawsFlipped: Bool
    let titleCell = AccountTitleAttachmentCell(textCell: "personal")

    init(flipped: Bool, menuItem: NSMenuItem? = nil) {
        self.drawsFlipped = flipped
        super.init(frame: NSRect(x: 0, y: 0, width: menuItem?.menu?.size.width ?? 280, height: 48))
        appearance = NSAppearance(named: .aqua)
        titleCell.activeProfile = "personal"
        titleCell.planName = "Pro"
        titleCell.menuItem = menuItem
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { drawsFlipped }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        titleCell.draw(withFrame: NSRect(x: 16, y: 4, width: 248, height: 40), in: self)
    }
}

extension AppDelegate {
    func checkAccountMenu() {
        // Render both coordinate systems: the longer account name must occupy
        // the top line, with the shorter plan underneath, including native menus.
        for flipped in [false, true] {
            let preview = AccountTitlePreview(flipped: flipped)
            let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
            preview.cacheDisplay(in: preview.bounds, to: bitmap)
            var upperInk = 0
            var lowerInk = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 16..<(min(100, bitmap.pixelsWide)) {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if color.redComponent < 0.8 {
                        if y < bitmap.pixelsHigh / 2 { upperInk += 1 } else { lowerInk += 1 }
                    }
                }
            }
            assert(upperInk > lowerInk, "The account name must appear above its plan (flipped: \(flipped))")
            if let path = ProcessInfo.processInfo.environment["PLAN_PREVIEW_PATH"], flipped {
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            }
        }

        let now = Date().timeIntervalSince1970
        let session = UsageWindowSnapshot(label: nil, usedPercent: 6, remainingPercent: 94,
            resetAt: now + 15150, windowSeconds: 18000)
        let week = UsageWindowSnapshot(label: nil, usedPercent: 18, remainingPercent: 82,
            resetAt: now + 444600, windowSeconds: 604800)
        let extra = UsageWindowSnapshot(label: "Review", usedPercent: 10, remainingPercent: 90,
            resetAt: nil, windowSeconds: 604800)
        usageByProfile["work"] = UsageSnapshot(fetchedAt: Date(), primary: session,
            secondary: week, additional: [extra], error: nil, planType: "business")
        usageByProfile["personal"] = UsageSnapshot(fetchedAt: Date(), primary: session,
            secondary: week, additional: nil, error: nil, planType: "pro")
        usageByProfile["expired"] = UsageSnapshot(fetchedAt: Date(), primary: nil,
            secondary: nil, additional: nil, error: "Sign in to Codex again")

        let details = accountUsageDetails("work")
        assert(details.count == 3)
        assert(details[0].contains("Session: 94% left") && details[0].contains("4h 12m to reset"))
        assert(details[1].contains("Weekly: 82% left") && details[1].contains("5d 3h to reset"))
        assert(details[2].contains("Review") && details[2].contains("Reset unavailable"))
        assert(accountUsageDetails("unknown") == ["Usage not loaded"])
        assert(accountUsageDetails("expired") == ["Sign in to Codex again"])

        for profiles in [[], ["personal"], ["personal", "work"], ["personal", "work", "team", "extra", "expired"]] {
            let main = makeMenu(profiles: profiles, activeProfile: "personal")
            let accountItem = main.items[1]
            assert(accountItem.title == "personal")
            assert(accountItem.hasSubmenu, "Accounts must use native submenu tracking")
            let menu = accountItem.submenu!
            assert(menu.supermenu === main)
            assert(accountItem.view == nil, "AppKit must draw the native submenu caret")
            let attachment = accountItem.attributedTitle?.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
            assert(attachment?.attachmentCell is AccountTitleAttachmentCell, "The native row must retain the styled account title")
            assert((attachment?.attachmentCell as? AccountTitleAttachmentCell)?.planName == "Pro")
            assert(accountItem.accessibilityValue() as? String == "Pro")
            assert(main.size.width == 280, "The native caret must not widen the menu")
            let choices = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }
            assert(choices.map(\.title) == profiles.filter { $0 != "personal" } + ["Add account"])
            assert(menu.minimumWidth == 248)
            assert(choices.last?.view == nil && choices.last?.image != nil,
                   "Add account must use a native action row with a plus icon")
            assert(choices.last?.action == #selector(captureCurrent))
            for item in choices {
                guard let row = item.view else { continue }
                let labels = row.subviews.compactMap { $0 as? NSTextField }
                let top = labels.map { $0.frame.minY }.min()!
                let bottom = row.bounds.height - labels.map { $0.frame.maxY }.max()!
                assert(abs(top - bottom) < 0.01, "Account rows must have equal top and bottom padding")
                assert(labels.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= row.bounds.height })
            }
            assert(menu.font == main.font, "Native action rows must share the same system menu font")
            for item in choices.dropLast() {
                assert(item.representedObject as? String == item.title)
                assert(item.action == #selector(switchProfile(_:)))
                let plan = usageByProfile[item.title]?.planName.map { [$0] } ?? []
                assert(item.view?.accessibilityValue() as? String == (plan + accountUsageDetails(item.title)).joined(separator: ", "))
                if item.title == "work" {
                    let labels = item.view!.subviews.compactMap { $0 as? NSTextField }
                    assert(labels[0].stringValue == "work" && labels[1].stringValue == "Business")
                    assert(labels[1].frame.minY >= labels[0].frame.maxY)
                }
                assert(item.view?.acceptsFirstResponder == false, "Native menus must own arrow-key navigation")
            }
            let folder = main.item(withTitle: "Open Profiles Folder")!
            assert(folder.view == nil && folder.keyEquivalent == "o")
            let quit = main.item(withTitle: "Quit")!
            assert(quit.view == nil && quit.keyEquivalent == "q")
            assert(quit.keyEquivalentModifierMask == [.command])
        }

        // Error text controls the native menu width. Both the account backdrop
        // and its trailing badge must follow that width, even for long errors.
        for error in ["The Internet connection appears to be offline.",
                      "The request failed: " + String(repeating: "connection unavailable ", count: 3)] {
            usageByProfile["personal"] = UsageSnapshot(fetchedAt: Date(), primary: nil,
                secondary: nil, additional: nil, error: error, planType: "pro")
            let main = makeMenu(profiles: ["personal", "work"], activeProfile: "personal")
            assert(main.size.width > MenuLayout.width, "The fixture must widen the native menu")
            for flipped in [false, true] {
                let preview = AccountTitlePreview(flipped: flipped, menuItem: main.items[1])
                let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsWide) / preview.bounds.width
                let backdrop = bitmap.colorAt(x: bitmap.pixelsWide - Int(8 * scale),
                                              y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
                assert(backdrop.redComponent < 0.98, "The backdrop must reach the expanded menu's trailing inset")
                var badgeInk = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in (bitmap.pixelsWide - Int(100 * scale))..<(bitmap.pixelsWide - Int(24 * scale)) {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.redComponent < 0.8 { badgeInk += 1 }
                    }
                }
                assert(badgeInk > 0, "Active must stay near the expanded menu's trailing edge")
                if let path = ProcessInfo.processInfo.environment["OFFLINE_PREVIEW_PATH"], flipped,
                   error == "The Internet connection appears to be offline." {
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        let emptyMain = makeMenu(profiles: [], activeProfile: "")
        let empty = emptyMain.items[1].submenu!
        assert(emptyMain.items[1].view == nil)
        assert(emptyMain.items[1].title == "Accounts")
        let emptyAttachment = emptyMain.items[1].attributedTitle?.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        assert((emptyAttachment?.attachmentCell as? AccountTitleAttachmentCell)?.planName == nil)
        assert(empty.items.filter { !$0.isHidden }.map(\.title) == ["Add account"])
        let orphan = accountsSubmenu(profiles: ["work"], activeProfile: "unsaved")
        assert(orphan.items.filter { !$0.isSeparatorItem }.map(\.title) == ["work", "Add account"])

        // Plan metadata must not invalidate caches written before this feature.
        let oldCache = Data(#"{"fetchedAt":0,"primary":null,"secondary":null,"error":null}"#.utf8)
        let oldSnapshot = try! JSONDecoder().decode(UsageSnapshot.self, from: oldCache)
        assert(oldSnapshot.planName == nil)
        let usage = try! JSONDecoder().decode(UsageResponse.self, from: Data(#"{"plan_type":"plus"}"#.utf8))
        assert(usage.planType == "plus")
        let restored = try! JSONDecoder().decode(UsageSnapshot.self,
            from: JSONEncoder().encode(usageByProfile["work"]!))
        assert(restored.planName == "Business")
        for (raw, expected) in [("team", "Business"), ("enterprise", "Enterprise"), ("new_plan", "New Plan"), (" ", nil)] as [(String, String?)] {
            var snapshot = oldSnapshot
            snapshot.planType = raw
            assert(snapshot.planName == expected)
        }

        print("Account dropdown checks passed")
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
delegate.checkAccountMenu()
'''


@unittest.skipUnless(sys.platform == 'darwin', 'Native menu requires macOS and AppKit')
class AccountMenuTests(unittest.TestCase):
    def test_dropdown_choices_and_usage_details(self):
        source = (ROOT / 'CodexAccountSwitcher.swift').read_text()
        source = source[:source.rindex('let app = NSApplication.shared')]
        with tempfile.TemporaryDirectory(prefix='account-menu-test-') as temporary:
            directory = Path(temporary)
            swift = directory / 'main.swift'
            swift.write_text(source + CHECKS)
            binary = directory / 'account-menu-tests'
            environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(ROOT / 'build/module-cache'))
            compiled = subprocess.run(
                ['/usr/bin/swiftc', str(swift), '-framework', 'AppKit', '-o', str(binary)],
                env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stdout)
            checked = subprocess.run([str(binary)], text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=15)
            self.assertEqual(checked.returncode, 0, checked.stdout)
            self.assertIn('Account dropdown checks passed', checked.stdout)
