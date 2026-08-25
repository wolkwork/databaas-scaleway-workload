import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.tf").read_text(encoding="utf-8")
VARIABLES = (ROOT / "variables.tf").read_text(encoding="utf-8")
OUTPUTS = (ROOT / "outputs.tf").read_text(encoding="utf-8")
ALL_TERRAFORM = "\n".join(
    path.read_text(encoding="utf-8") for path in ROOT.glob("*.tf")
)


class ModuleContractTest(unittest.TestCase):
    def test_module_creates_no_iam_or_secret_resources(self):
        forbidden = (
            "scaleway_iam_",
            "scaleway_secret",
            "github_actions_",
            "kubernetes_secret",
        )
        for resource_prefix in forbidden:
            self.assertNotIn(f'resource "{resource_prefix}', ALL_TERRAFORM)

    def test_storage_roles_are_fixed(self):
        self.assertIn(
            'buckets = toset(["lakehouse", "metadata", "logs", "backups"])',
            MAIN,
        )

    def test_customer_data_cannot_be_force_destroyed_by_default(self):
        block = self._variable_block("bucket_force_destroy")
        self.assertRegex(block, r"default\s*=\s*false")

    def test_cluster_created_resources_are_not_cascade_deleted_by_default(self):
        block = self._variable_block("delete_additional_resources")
        self.assertRegex(block, r"default\s*=\s*false")

    def test_api_server_allowlist_is_required(self):
        block = self._variable_block("api_server_allowed_ips")
        self.assertNotRegex(block, r"default\s*=")
        self.assertIn("length(var.api_server_allowed_ips) > 0", block)

    def test_module_does_not_embed_customer_or_operator_addresses(self):
        self.assertNotRegex(MAIN, r'(?m)^\s*ip\s*=\s*"[0-9]')

    def test_outputs_contain_no_credentials_or_kubeconfig(self):
        output_names = re.findall(r'output\s+"([^"]+)"', OUTPUTS.lower())
        for forbidden in ("secret", "credential", "kubeconfig", "access_key"):
            self.assertTrue(
                all(forbidden not in output_name for output_name in output_names),
                f"output name contains forbidden term: {forbidden}",
            )

    def test_internal_repository_paths_are_absent(self):
        for forbidden in (
            "deployments/scaleway-iam",
            "databaas-infrastructure",
            "docs/iam-architecture.md",
        ):
            self.assertNotIn(forbidden, ALL_TERRAFORM)

    def _variable_block(self, name: str) -> str:
        marker = f'variable "{name}" {{'
        start = VARIABLES.index(marker)
        next_start = VARIABLES.find('\nvariable "', start + len(marker))
        return VARIABLES[start:] if next_start == -1 else VARIABLES[start:next_start]


if __name__ == "__main__":
    unittest.main()
