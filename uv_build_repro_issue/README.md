## Use of random temp paths by `uv build` adds nondeterminism into build environments

The scripts here describe a minimal example for replicating a problem that `uv
build` poses for reproducible builds. This problem was uncovered while
experimenting with making the `pyca/cryptography` wheel builds reproducible.

For a writeup, see the issue filed with upstream:
https://github.com/astral-sh/uv/issues/13096
