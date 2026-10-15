//
//  CommandFailureTests.swift
//  Ant FarmTests
//

import Testing
@testable import Ant_Farm

struct CommandFailureTests {
    @Test func recognizesOnePasswordNotSignedIn() {
        let error = """
        ansible-playbook --list-tags exited with status 1.

        [ERROR] 2026/10/15 11:54:39 could not read secret 'op://Developers/Ansible Vault Password/password': error initializing client: You are not currently signed in. Please run `op signin --help` for instructions
        [WARNING]: Error in vault password file loading (default): Vault password script /Users/someone/Projects/Orchestration/vault-pass.sh returned non-zero (1): None
        ERROR! Vault password script /Users/someone/Projects/Orchestration/vault-pass.sh returned non-zero (1): None
        """
        #expect(CommandFailure.recognize(error) == .onePasswordAccess)
    }

    @Test func recognizesOnePasswordNoAccounts() {
        let error = """
        ansible-inventory exited with status 1.

        No accounts configured for use with 1Password CLI.

         - Turn on the 1Password desktop app integration to sign in with the accounts you've added to the app: https://www.1password.dev/cli/app-integration/ for details.
        ERROR! Vault password script /Users/someone/Sites/orchestration/vault-pass.sh returned non-zero (1): None
        """
        #expect(CommandFailure.recognize(error) == .onePasswordAccess)
    }

    @Test func ignoresOtherVaultScriptFailures() {
        let error = "ERROR! Vault password script /tmp/vault-pass.sh returned non-zero (2): None"
        #expect(CommandFailure.recognize(error) == nil)
    }

    @Test func ignoresUnrelatedFailures() {
        #expect(CommandFailure.recognize("ERROR! the playbook: site.yml could not be found") == nil)
    }
}
