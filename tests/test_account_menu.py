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
            let menu = accountsDropdown(profiles: profiles, activeProfile: "personal")
            let selector = AccountDropdownMenuView(activeProfile: "personal", accountsMenu: menu)
            let choices = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }
            assert(choices.map(\.title) == profiles.filter { $0 != "personal" } + ["Add account"])
            assert(choices.last?.view?.frame.width == 248)
            assert(choices.last?.action == #selector(captureCurrent))
            for item in choices.dropLast() {
                assert(item.representedObject as? String == item.title)
                assert(item.action == #selector(switchProfile(_:)))
                assert(item.view?.accessibilityValue() as? String == accountUsageDetails(item.title).joined(separator: ", "))
            }
            let cell = selector.button.cell as! AccountDropdownCell
            assert(cell.activeProfile == "personal")
            assert(selector.subviews.count == 1, "Active usage belongs below the selector")
        }
        let empty = accountsDropdown(profiles: [], activeProfile: "")
        let selector = AccountDropdownMenuView(activeProfile: "", accountsMenu: empty)
        assert(selector.button.accessibilityValue() as? String == "No active account")
        assert(empty.items.filter { !$0.isHidden }.map(\.title) == ["Add account"])
        let orphan = accountsDropdown(profiles: ["work"], activeProfile: "unsaved")
        assert(orphan.items.filter { !$0.isSeparatorItem }.map(\.title) == ["work", "Add account"])

        let contentMenu = NSMenu()
        let accountItem = NSMenuItem()
        accountItem.view = AccountDropdownMenuView(activeProfile: "personal", accountsMenu: empty)
        contentMenu.addItem(accountItem)
        let usageItem = NSMenuItem()
        usageItem.view = UsageBarsMenuView(rows: [UsageBarRow(title: "Session", usedPercent: 28,
            resetPercent: 43, resetText: "2h 51m to reset")], updatedText: "Updated just now",
            target: nil, refreshAction: #selector(refreshNow))
        contentMenu.addItem(usageItem)
        let controller = MenuPopoverController(menu: contentMenu)
        contentMenu.update()
        let views = controller.view.subviews
        assert(views[1].frame.minY >= views[0].frame.maxY, "Usage must stay below the account selector")
        assert(accountItem.view == nil && usageItem.view == nil, "Native menus must release the transferred views")
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
