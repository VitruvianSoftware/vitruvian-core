# Tabula Helm chart

Co-located deploy chart for Tabula. Published as an OCI artifact to
`oci://ghcr.io/vitruviansoftware/charts/tabula` by
`.github/workflows/charts-publish.yml`, and deployed by ArgoCD via
`gitops/argocd/applications/tabula.yaml`.

Bump `version` in `Chart.yaml` to publish a new chart revision.
Container images come from GCP Artifact Registry — set `image.repository`/`image.tag`
per environment via the Application's helm values.
