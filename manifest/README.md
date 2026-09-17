# Versioned destructive manifests

`destructiveChangesPre.xml` and `destructiveChangesPost.xml` here are **live** —
when either has `<types>` entries, `salesforce-delivery.mjs` passes it straight to
`sf project deploy start --pre-destructive-changes` / `--post-destructive-changes`
on every validate (dry-run) and deploy, in every environment the file reaches as it
flows through the normal `develop` → `uat` → `main` promotion. This is different
from the auto-generated `destructiveChanges.xml` in the evidence artifact, which is
evidence only and never applied.

Committing a non-empty manifest here **is** the explicitly approved destructive
release: review the PR that adds it like any other production-affecting change
(impact analysis, who/what depends on these components, recovery plan).

**After it has been applied successfully where intended** (typically once it
reaches `main`/PROD), empty it back out in a follow-up commit — an empty
`<Package>` with no `<types>` is a no-op, but a manifest left non-empty keeps
re-submitting the same destructive request on every future deploy to every
environment it's present in.

Managed package components (e.g. a `namespace__`-prefixed class) cannot be
deleted this way — Salesforce rejects it. Don't add them here.
