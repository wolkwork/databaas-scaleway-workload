#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repository_root"

tofu fmt -check -recursive
tofu init -backend=false -input=false
tofu validate

tofu -chdir=examples/basic init -backend=false -input=false
tofu -chdir=examples/basic validate

python3 -m unittest discover -s tests -v
