# Vitruvian Tabs Helm chart

Co-located deploy chart for Vitruvian Tabs. Published as an OCI artifact to
`oci://ghcr.io/vitruviansoftware/charts/vitruvian-tabs` by
`.github/workflows/charts-publish.yml`, and deployed by ArgoCD via
`gitops/argocd/applications/vitruvian-tabs.yaml`.

Bump `version` in `Chart.yaml` to publish a new chart revision.
Container images come from GCP Artifact Registry — set `image.repository`/`image.tag`
per environment via the Application's helm values.
