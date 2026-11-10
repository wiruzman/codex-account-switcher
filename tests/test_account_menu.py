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
extension AppDelegate {
    func checkAccountMenu() {
        let now = Date().timeIntervalSince1970
        let session = UsageWindowSnapshot(label: nil, usedPercent: 6, remainingPercent: 94,
            resetAt: now + 15150, windowSeconds: 18000)
        let week = UsageWindowSnapshot(label: nil, usedPercent: 18, remainingPercent: 82,
            resetAt: now + 444600, windowSeconds: 604800)
        let extra = UsageWindowSnapshot(label: "Review", usedPercent: 10, remainingPercent: 90,
            resetAt: nil, windowSeconds: 604800)
        usageByProfile["work"] = UsageSnapshot(fetchedAt: Date(), primary: session,
            secondary: week, additional: [extra], error: nil)
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
            let accountItem = main.items[0]
            assert(accountItem.title == "personal")
            assert(accountItem.hasSubmenu, "Accounts must use native submenu tracking")
            let menu = accountItem.submenu!
            assert(menu.supermenu === main)
            let selector = accountItem.view as! AccountSubmenuView
            let choices = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }
            assert(choices.map(\.title) == profiles.filter { $0 != "personal" } + ["Add account"])
            assert(choices.last?.view?.frame.width == 248)
            assert(choices.last?.action == #selector(captureCurrent))
            for item in choices {
                let row = item.view!
                let labels = row.subviews.compactMap { $0 as? NSTextField }
                let top = labels.map { $0.frame.minY }.min()!
                let bottom = row.bounds.height - labels.map { $0.frame.maxY }.max()!
                assert(abs(top - bottom) < 0.01, "Account rows must have equal top and bottom padding")
                assert(labels.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= row.bounds.height })
            }
            let nativeCell = NSMenuItemCell(textCell: "Open Profiles Folder")
            nativeCell.menuItem = main.item(withTitle: "Open Profiles Folder")
            nativeCell.font = main.font
            assert(choices.last?.view?.frame.height == nativeCell.cellSize.height,
                   "Add account must have the same row height as a native menu action")
            for item in choices.dropLast() {
                assert(item.representedObject as? String == item.title)
                assert(item.action == #selector(switchProfile(_:)))
                assert(item.view?.accessibilityValue() as? String == accountUsageDetails(item.title).joined(separator: ", "))
                assert(item.view?.acceptsFirstResponder == false, "Native menus must own arrow-key navigation")
            }
            assert(selector.accessibilityValue() as? String == "personal")
            assert(selector.subviews.isEmpty, "The account row must not contain an interactive nested control")
            let folder = main.item(withTitle: "Open Profiles Folder")!
            assert(folder.view == nil && folder.keyEquivalent == "o")
            let quit = main.item(withTitle: "Quit")!
            assert(quit.view == nil && quit.keyEquivalent == "q")
            assert(quit.keyEquivalentModifierMask == [.command])
        }
        let emptyMain = makeMenu(profiles: [], activeProfile: "")
        let empty = emptyMain.items[0].submenu!
        let selector = emptyMain.items[0].view as! AccountSubmenuView
        assert(selector.accessibilityValue() as? String == "No active account")
        assert(empty.items.filter { !$0.isHidden }.map(\.title) == ["Add account"])
        let orphan = accountsSubmenu(profiles: ["work"], activeProfile: "unsaved")
        assert(orphan.items.filter { !$0.isSeparatorItem }.map(\.title) == ["work", "Add account"])

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
