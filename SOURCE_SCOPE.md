# Source bundle scope

This archive is a runnable OmniRoute migration release plus a non-destructive overlay for the upstream repository.

The router-facing stack files, installer, manager, Hermes template, Smart Router default configuration, policies, docs, tests, and persistent-data skeleton are included. Unchanged development-only source trees that are consumed at runtime through already-published images (for example the complete Smart Router and execution-broker build trees) are not duplicated in this generated bundle.

For a full upstream source checkout with every unchanged file preserved, clone `Afsharidevops/hermes-linux-stack`, extract this bundle, and run:

```bash
./scripts/apply-to-upstream.sh /path/to/hermes-linux-stack
```

The overlay backs up replaced files and preserves unrelated upstream source files. It does not delete legacy runtime data.
