const fs = require("fs");
let content = fs.readFileSync(
  ".github/workflows/foundation-release.yaml",
  "utf8",
);

// Make release-gcp-environments depend on phase 1 deploys
content = content.replace(
  "release-gcp-environments:\n    runs-on: ubuntu-latest",
  "release-gcp-environments:\n    needs: [deploy-gcp-org, deploy-org-folders, deploy-gcp-bootstrap]\n    if: always() && !cancelled()\n    runs-on: ubuntu-latest",
);

// Make release-gcp-networks depend on phase 2 deploys
content = content.replace(
  "release-gcp-networks:\n    runs-on: ubuntu-latest",
  "release-gcp-networks:\n    needs: [deploy-env-production]\n    if: always() && !cancelled()\n    runs-on: ubuntu-latest",
);

fs.writeFileSync(".github/workflows/foundation-release.yaml", content);
