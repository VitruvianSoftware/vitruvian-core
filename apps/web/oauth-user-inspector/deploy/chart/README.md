# OAuth User Inspector Helm chart

Co-located deploy chart for OAuth User Inspector. Published as an OCI artifact to
`oci://ghcr.io/vitruviansoftware/charts/oauth-user-inspector` by
`.github/workflows/charts-publish.yml`, and deployed by ArgoCD.

Bump `version` in `Chart.yaml` to publish a new chart revision.
Container images come from GCP Artifact Registry — set `image.repository`/`image.tag`
per environment via the Application's helm values.
