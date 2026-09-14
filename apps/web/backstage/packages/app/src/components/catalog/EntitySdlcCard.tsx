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
import { Chip, Grid, Typography, Box, makeStyles } from "@material-ui/core";
import { InfoCard, Link } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import { readSdlcInfo } from "./sdlc";

const useStyles = makeStyles((theme) => ({
  sectionTitle: {
    fontSize: "0.825rem",
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: "0.05em",
    color: theme.palette.text.secondary,
    marginBottom: theme.spacing(1),
  },
  chip: {
    marginRight: theme.spacing(1),
    marginBottom: theme.spacing(1),
    fontWeight: 600,
  },
  envLadder: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    marginTop: theme.spacing(0.5),
    marginBottom: theme.spacing(1.5),
  },
  envStep: {
    padding: theme.spacing(0.5, 1.5),
    borderRadius: theme.shape.borderRadius,
    backgroundColor: theme.palette.background.default,
    border: `1px solid ${theme.palette.divider}`,
    fontWeight: 600,
    fontSize: "0.85rem",
  },
  envArrow: {
    margin: theme.spacing(0, 1),
    color: theme.palette.text.hint,
    fontWeight: 700,
  },
  targetCode: {
    fontFamily: "monospace",
    fontSize: "0.825rem",
    backgroundColor: theme.palette.background.default,
    padding: theme.spacing(0.25, 0.75),
    borderRadius: 4,
    marginRight: theme.spacing(0.5),
    marginBottom: theme.spacing(0.5),
    display: "inline-block",
  },
}));

/**
 * SDLC & Delivery Governance Card
 *
 * Visualizes the release model, environment promotion ladder, delivery
 * workflows, Bazel build/push targets, and standalone GitHub mirror bindings.
 */
export const EntitySdlcCard = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const sdlc = readSdlcInfo(entity);

  if (!sdlc) {
    return null;
  }

  const slug = entity.metadata.annotations?.["github.com/project-slug"];

  return (
    <InfoCard
      title="Software Delivery Life Cycle (SDLC)"
      subheader="Promotion, Delivery & Release Governance"
    >
      <Grid container spacing={2}>
        {/* Release Strategies */}
        <Grid item xs={12}>
          <Typography className={classes.sectionTitle}>
            Release Strategy
          </Typography>
          <Box display="flex" flexWrap="wrap">
            {sdlc.releaseModels.length > 0 ? (
              sdlc.releaseModels.map((model) => (
                <Chip
                  key={model.key}
                  label={model.label}
                  color={
                    model.category === "cloud-run" ? "primary" : "secondary"
                  }
                  size="small"
                  className={classes.chip}
                />
              ))
            ) : (
              <Typography variant="body2" color="textSecondary">
                Standard Monorepo Trunk Delivery
              </Typography>
            )}
          </Box>
        </Grid>

        {/* Environment Promotion Ladder */}
        {sdlc.environments.length > 0 && (
          <Grid item xs={12}>
            <Typography className={classes.sectionTitle}>
              Environment Promotion Ladder
            </Typography>
            <div className={classes.envLadder}>
              {sdlc.environments.map((env, idx) => (
                <React.Fragment key={env}>
                  <div className={classes.envStep}>{env.toUpperCase()}</div>
                  {idx < sdlc.environments.length - 1 && (
                    <span className={classes.envArrow}>➔</span>
                  )}
                </React.Fragment>
              ))}
            </div>
          </Grid>
        )}

        {/* CI/CD Workflow */}
        {sdlc.workflow && (
          <Grid item xs={12} sm={6}>
            <Typography className={classes.sectionTitle}>
              {sdlc.workflow.type === "deploy"
                ? "Deployment Pipeline"
                : "Release Pipeline"}
            </Typography>
            <Typography variant="body2">
              {slug ? (
                <Link
                  to={`https://github.com/${slug}/blob/main/.github/workflows/${sdlc.workflow.name}`}
                >
                  <code>.github/workflows/{sdlc.workflow.name}</code>
                </Link>
              ) : (
                <code>{sdlc.workflow.name}</code>
              )}
            </Typography>
          </Grid>
        )}

        {/* Standalone Repository Mirror */}
        {sdlc.mirror && (
          <Grid item xs={12} sm={6}>
            <Typography className={classes.sectionTitle}>
              Export Mirror (Copybara)
            </Typography>
            <Typography variant="body2">
              <Link to={`https://github.com/${sdlc.mirror}`}>
                {sdlc.mirror}
              </Link>
            </Typography>
          </Grid>
        )}

        {/* Build / Deploy Targets */}
        {sdlc.deployTargets.length > 0 && (
          <Grid item xs={12}>
            <Typography className={classes.sectionTitle}>
              Bazel Delivery Targets
            </Typography>
            <Box display="flex" flexWrap="wrap">
              {sdlc.deployTargets.map((target) => (
                <span key={target} className={classes.targetCode}>
                  {target}
                </span>
              ))}
            </Box>
          </Grid>
        )}
      </Grid>
    </InfoCard>
  );
};
