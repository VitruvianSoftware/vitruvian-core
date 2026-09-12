// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import React from "react";
import useAsync from "react-use/lib/useAsync";
import { Box, Chip, Grid, Typography, makeStyles } from "@material-ui/core";
import {
  InfoCard,
  Link,
  Progress,
  StatusOK,
  StatusPending,
} from "@backstage/core-components";
import { useApi, githubAuthApiRef } from "@backstage/core-plugin-api";
import { useEntity } from "@backstage/plugin-catalog-react";
import { readReleaseTarget, type ReleaseInfo } from "./release";

const useStyles = makeStyles((theme) => ({
  versionBadge: {
    fontWeight: 700,
    fontSize: "1.1rem",
    padding: theme.spacing(1, 1.5),
    backgroundColor: theme.palette.primary.main,
    color: theme.palette.primary.contrastText,
    borderRadius: theme.shape.borderRadius,
    display: "inline-block",
  },
  sectionTitle: {
    fontSize: "0.825rem",
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: "0.05em",
    color: theme.palette.text.secondary,
    marginBottom: theme.spacing(0.5),
  },
  detailsBox: {
    padding: theme.spacing(1.5),
    backgroundColor: theme.palette.background.default,
    borderRadius: 4,
    marginTop: theme.spacing(1),
  },
}));

export const EntityReleaseCard = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const auth = useApi(githubAuthApiRef);
  const target = readReleaseTarget(entity);

  const { value, loading, error } = useAsync(async (): Promise<
    ReleaseInfo | undefined
  > => {
    if (!target) return undefined;

    if (target.type === "npm") {
      try {
        const res = await fetch(
          `https://registry.npmjs.org/${encodeURIComponent(target.packageName)}/latest`,
        );
        if (res.ok) {
          const data = await res.json();
          return {
            type: "npm",
            version: data.version ?? "latest",
            releaseTitle: data.description,
            url: target.packageUrl,
            details: `Package: ${target.packageName}`,
          };
        }
      } catch {
        // Fallback to static link
      }
      return {
        type: "npm",
        version: "npm package",
        url: target.packageUrl,
        details: target.packageName,
      };
    }

    if (target.type === "github") {
      try {
        let headers: Record<string, string> = {
          Accept: "application/vnd.github+json",
        };
        try {
          const token = await auth.getAccessToken(["repo"]);
          if (token) {
            headers.Authorization = `Bearer ${token}`;
          }
        } catch {
          // Continue unauthenticated if token not granted
        }

        const res = await fetch(
          `https://api.github.com/repos/${target.repoSlug}/releases/latest`,
          {
            headers,
          },
        );
        if (res.ok) {
          const data = await res.json();
          return {
            type: "github",
            version: data.tag_name ?? "latest",
            releaseTitle: data.name ?? data.tag_name,
            publishedAt: data.published_at,
            url: data.html_url ?? target.releasesUrl,
            details: `Repository: ${target.repoSlug}`,
          };
        }
      } catch {
        // Fallback to static link
      }
      return {
        type: "github",
        version: "GitHub Release",
        url: target.releasesUrl,
        details: target.repoSlug,
      };
    }

    return undefined;
  }, [target]);

  if (!target) return null;

  return (
    <InfoCard
      title="Published Version & Release Insights"
      subheader={
        target.type === "npm"
          ? `npm registry: ${target.packageName}`
          : `GitHub Releases: ${target.repoSlug}`
      }
    >
      {loading && <Progress />}
      {!loading && (
        <Grid container spacing={2} alignItems="center">
          <Grid item xs={12} sm={6}>
            <Typography className={classes.sectionTitle}>
              Latest Release Vintage
            </Typography>
            <div className={classes.versionBadge}>
              {value?.version ?? "Latest"}
            </div>
            {value?.publishedAt && (
              <Typography
                variant="caption"
                color="textSecondary"
                style={{ display: "block", marginTop: 4 }}
              >
                Published: {new Date(value.publishedAt).toLocaleDateString()}
              </Typography>
            )}
          </Grid>

          <Grid item xs={12} sm={6}>
            <Typography className={classes.sectionTitle}>
              Distribution Channel
            </Typography>
            <Box display="flex" alignItems="center" mb={1}>
              <StatusOK>
                {target.type === "npm"
                  ? "npm Public Registry"
                  : "GitHub Release Assets"}
              </StatusOK>
            </Box>
            <Link
              to={
                value?.url ??
                (target.type === "npm" ? target.packageUrl : target.releasesUrl)
              }
            >
              View Release Assets & Changelog ➔
            </Link>
          </Grid>

          {value?.releaseTitle && (
            <Grid item xs={12}>
              <div className={classes.detailsBox}>
                <Typography
                  variant="caption"
                  color="textSecondary"
                  style={{ fontWeight: 700, display: "block" }}
                >
                  Release Summary
                </Typography>
                <Typography variant="body2">{value.releaseTitle}</Typography>
              </div>
            </Grid>
          )}
        </Grid>
      )}
    </InfoCard>
  );
};
