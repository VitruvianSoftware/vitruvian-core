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

import React, { useState } from "react";
import useAsync from "react-use/lib/useAsync";
import {
  Box,
  Chip,
  Grid,
  LinearProgress,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Typography,
  Collapse,
  Button,
  Tabs,
  Tab,
  makeStyles,
} from "@material-ui/core";
import CheckCircleIcon from "@material-ui/icons/CheckCircle";
import CancelIcon from "@material-ui/icons/Cancel";
import RemoveCircleOutlineIcon from "@material-ui/icons/RemoveCircleOutline";
import ExpandMoreIcon from "@material-ui/icons/ExpandMore";
import ExpandLessIcon from "@material-ui/icons/ExpandLess";
import SecurityIcon from "@material-ui/icons/Security";
import SpeedIcon from "@material-ui/icons/Speed";
import VerifiedUserIcon from "@material-ui/icons/VerifiedUser";
import FlightTakeoffIcon from "@material-ui/icons/FlightTakeoff";
import {
  InfoCard,
  Progress,
  StatusOK,
  StatusError,
  StatusPending,
} from "@backstage/core-components";
import {
  useApi,
  discoveryApiRef,
  fetchApiRef,
} from "@backstage/core-plugin-api";
import { useEntity } from "@backstage/plugin-catalog-react";
import {
  evaluateScorecard,
  type EvaluatedScorecard,
  type MaturityTier,
  type ScorecardTrackId,
} from "./scorecard";

const useStyles = makeStyles((theme) => ({
  tierBadgeGold: {
    backgroundColor: "#FFD700",
    color: "#000",
    fontWeight: 700,
    fontSize: "0.9rem",
    padding: theme.spacing(0.5, 1),
  },
  tierBadgeSilver: {
    backgroundColor: "#C0C0C0",
    color: "#000",
    fontWeight: 700,
    fontSize: "0.9rem",
    padding: theme.spacing(0.5, 1),
  },
  tierBadgeBronze: {
    backgroundColor: "#CD7F32",
    color: "#FFF",
    fontWeight: 700,
    fontSize: "0.9rem",
    padding: theme.spacing(0.5, 1),
  },
  tierBadgeIncomplete: {
    backgroundColor: theme.palette.error.main,
    color: theme.palette.error.contrastText,
    fontWeight: 700,
    fontSize: "0.9rem",
    padding: theme.spacing(0.5, 1),
  },
  archetypeChip: {
    fontWeight: 600,
    textTransform: "uppercase",
    fontSize: "0.75rem",
    marginRight: theme.spacing(1),
  },
  progressContainer: {
    width: "100%",
    marginTop: theme.spacing(1),
    marginBottom: theme.spacing(1.5),
  },
  diagnosticsBar: {
    display: "flex",
    flexWrap: "wrap",
    gap: theme.spacing(1),
    padding: theme.spacing(1),
    backgroundColor: theme.palette.background.default,
    borderRadius: theme.shape.borderRadius,
    marginTop: theme.spacing(1),
    marginBottom: theme.spacing(1.5),
  },
  trackCard: {
    padding: theme.spacing(1.5),
    backgroundColor: theme.palette.background.default,
    borderRadius: theme.shape.borderRadius,
    border: `1px solid ${theme.palette.divider}`,
    height: "100%",
  },
  trackTitle: {
    fontWeight: 700,
    fontSize: "0.85rem",
    display: "flex",
    alignItems: "center",
    gap: theme.spacing(0.5),
  },
  checkItem: {
    paddingTop: theme.spacing(0.5),
    paddingBottom: theme.spacing(0.5),
  },
  checkPassed: {
    color: theme.palette.success.main,
  },
  checkFailed: {
    color: theme.palette.error.main,
  },
  checkNa: {
    color: theme.palette.text.disabled,
  },
  nextStepBox: {
    padding: theme.spacing(1.5),
    backgroundColor: theme.palette.background.default,
    borderRadius: theme.shape.borderRadius,
    marginTop: theme.spacing(1),
    marginBottom: theme.spacing(1),
  },
}));

export const EntityScorecardCard = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const discovery = useApi(discoveryApiRef);
  const fetchApi = useApi(fetchApiRef);

  const [expanded, setExpanded] = useState(false);
  const [selectedTrack, setSelectedTrack] =
    useState<ScorecardTrackId>("security");

  const { value: scorecard, loading } =
    useAsync(async (): Promise<EvaluatedScorecard> => {
      try {
        const baseUrl = await discovery.getBaseUrl("scorecards");
        const kind = entity.kind.toLowerCase();
        const namespace = entity.metadata.namespace ?? "default";
        const name = entity.metadata.name;
        const res = await fetchApi.fetch(
          `${baseUrl}/entities/${kind}/${namespace}/${name}`,
        );
        if (res.ok) {
          return (await res.json()) as EvaluatedScorecard;
        }
      } catch {
        // Graceful fallback to client evaluation
      }
      return evaluateScorecard(entity);
    }, [entity]);

  if (loading || !scorecard) {
    return <Progress />;
  }

  const getTierClass = (tier: MaturityTier) => {
    switch (tier) {
      case "Gold":
        return classes.tierBadgeGold;
      case "Silver":
        return classes.tierBadgeSilver;
      case "Bronze":
        return classes.tierBadgeBronze;
      default:
        return classes.tierBadgeIncomplete;
    }
  };

  const getTierEmoji = (tier: MaturityTier) => {
    switch (tier) {
      case "Gold":
        return "🥇 Gold Tier";
      case "Silver":
        return "🥈 Silver Tier";
      case "Bronze":
        return "🥉 Bronze Tier";
      default:
        return "⚠️ Incomplete";
    }
  };

  const renderTrackIcon = (id: ScorecardTrackId) => {
    switch (id) {
      case "security":
        return <SecurityIcon fontSize="small" />;
      case "reliability":
        return <SpeedIcon fontSize="small" />;
      case "quality":
        return <VerifiedUserIcon fontSize="small" />;
      case "delivery":
        return <FlightTakeoffIcon fontSize="small" />;
    }
  };

  return (
    <InfoCard
      title="Operational Maturity & Soundcheck Governance"
      subheader={`Level 3 Live Fact Evaluator • Archetype: ${scorecard.archetype.toUpperCase()}`}
    >
      <Grid container spacing={2}>
        {/* Tier and Archetype Header */}
        <Grid item xs={12}>
          <Box
            display="flex"
            justifyContent="space-between"
            alignItems="center"
            flexWrap="wrap"
          >
            <Box display="flex" alignItems="center">
              <Chip
                label={`Archetype: ${scorecard.archetype}`}
                size="small"
                className={classes.archetypeChip}
              />
              <Typography variant="subtitle1" style={{ fontWeight: 700 }}>
                {scorecard.name}
              </Typography>
            </Box>
            <Chip
              label={getTierEmoji(scorecard.overallTier)}
              className={getTierClass(scorecard.overallTier)}
            />
          </Box>

          {/* Compliance Progress Bar */}
          <Box className={classes.progressContainer}>
            <Box display="flex" justifyContent="space-between" mb={0.5}>
              <Typography variant="caption" color="textSecondary">
                Overall Compliance Score
              </Typography>
              <Typography variant="caption" style={{ fontWeight: 700 }}>
                {scorecard.overallScore}%
              </Typography>
            </Box>
            <LinearProgress
              variant="determinate"
              value={scorecard.overallScore}
              color={scorecard.overallTier === "Gold" ? "primary" : "secondary"}
            />
          </Box>

          {/* Live Fact Diagnostics Strip */}
          <div className={classes.diagnosticsBar}>
            <Chip
              size="small"
              icon={<SecurityIcon />}
              label={`Security: ${scorecard.diagnostics.securityHealth.codeownersBound ? "CODEOWNERS Set" : "Unbound"}`}
              color={
                scorecard.diagnostics.securityHealth.codeownersBound
                  ? "default"
                  : "secondary"
              }
            />
            <Chip
              size="small"
              icon={<SpeedIcon />}
              label={`CI Health: ${scorecard.diagnostics.ciHealth.passRatePercent}% Pass`}
              color={
                scorecard.diagnostics.ciHealth.passRatePercent >= 80
                  ? "default"
                  : "secondary"
              }
            />
            {scorecard.diagnostics.uptimeHealth.status !== "na" && (
              <Chip
                size="small"
                label={`Uptime: ${scorecard.diagnostics.uptimeHealth.status === "up" ? "Live UP" : "Unmonitored"}`}
                color={
                  scorecard.diagnostics.uptimeHealth.status === "up"
                    ? "default"
                    : "secondary"
                }
              />
            )}
            {scorecard.diagnostics.runbookHealth.verified && (
              <Chip
                size="small"
                label={`Runbook: ${scorecard.diagnostics.runbookHealth.sectionFound ? "Verified Section" : "Linked"}`}
                color={
                  scorecard.diagnostics.runbookHealth.sectionFound
                    ? "default"
                    : "secondary"
                }
              />
            )}
            <Chip
              size="small"
              label={`Runtime: ${scorecard.diagnostics.runtimeHealth.provider.toUpperCase()}`}
            />
          </div>

          {/* 4 Tracks Summary Grid */}
          <Grid container spacing={1}>
            {(Object.keys(scorecard.tracks) as ScorecardTrackId[]).map(
              (trackId) => {
                const track = scorecard.tracks[trackId];
                return (
                  <Grid item xs={6} sm={3} key={trackId}>
                    <div className={classes.trackCard}>
                      <div className={classes.trackTitle}>
                        {renderTrackIcon(trackId)}
                        <span>{track.title.split(" ")[0]}</span>
                      </div>
                      <Box
                        mt={1}
                        display="flex"
                        justifyContent="space-between"
                        alignItems="center"
                      >
                        <Typography variant="body2" style={{ fontWeight: 700 }}>
                          {track.level}
                        </Typography>
                        <Typography variant="caption" color="textSecondary">
                          {track.scorePercent}%
                        </Typography>
                      </Box>
                    </div>
                  </Grid>
                );
              },
            )}
          </Grid>

          {/* Next Steps Prompt */}
          {scorecard.nextSteps.length > 0 && (
            <div className={classes.nextStepBox}>
              <Typography
                variant="caption"
                style={{ fontWeight: 700, display: "block" }}
              >
                Next Milestones to Reach Next Tier:
              </Typography>
              <ul style={{ margin: "4px 0 0 0", paddingLeft: 20 }}>
                {scorecard.nextSteps.map((step) => (
                  <li key={step}>
                    <Typography variant="caption" color="error">
                      {step}
                    </Typography>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Collapsible Detailed Audit Checklist */}
          <Box display="flex" justifyContent="flex-end" mt={1}>
            <Button
              size="small"
              onClick={() => setExpanded(!expanded)}
              endIcon={expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
            >
              {expanded ? "Hide Audit Checklist" : "Show Full Audit Checklist"}
            </Button>
          </Box>

          <Collapse in={expanded}>
            <Box mt={1}>
              <Tabs
                value={selectedTrack}
                onChange={(_e, val) => setSelectedTrack(val)}
                indicatorColor="primary"
                textColor="primary"
                variant="fullWidth"
              >
                <Tab label="Security" value="security" />
                <Tab label="Reliability" value="reliability" />
                <Tab label="Quality" value="quality" />
                <Tab label="Delivery" value="delivery" />
              </Tabs>

              <List dense disablePadding>
                {scorecard.tracks[selectedTrack].checks.map((check) => (
                  <ListItem
                    key={check.id}
                    className={classes.checkItem}
                    disableGutters
                  >
                    <ListItemIcon style={{ minWidth: 32 }}>
                      {check.status === "passed" && (
                        <CheckCircleIcon
                          fontSize="small"
                          className={classes.checkPassed}
                        />
                      )}
                      {check.status === "failed" && (
                        <CancelIcon
                          fontSize="small"
                          className={classes.checkFailed}
                        />
                      )}
                      {check.status === "not_applicable" && (
                        <RemoveCircleOutlineIcon
                          fontSize="small"
                          className={classes.checkNa}
                        />
                      )}
                    </ListItemIcon>
                    <ListItemText
                      primary={
                        <Typography variant="body2" style={{ fontWeight: 600 }}>
                          [{check.tierRequired}] {check.title}
                        </Typography>
                      }
                      secondary={check.message}
                    />
                  </ListItem>
                ))}
              </List>
            </Box>
          </Collapse>
        </Grid>
      </Grid>
    </InfoCard>
  );
};
