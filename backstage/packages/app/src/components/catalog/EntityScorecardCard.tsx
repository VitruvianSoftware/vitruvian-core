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
  makeStyles,
} from "@material-ui/core";
import CheckCircleIcon from "@material-ui/icons/CheckCircle";
import CancelIcon from "@material-ui/icons/Cancel";
import ExpandMoreIcon from "@material-ui/icons/ExpandMore";
import ExpandLessIcon from "@material-ui/icons/ExpandLess";
import { InfoCard } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import { evaluateScorecard, type MaturityTier } from "./scorecard";

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
  progressContainer: {
    width: "100%",
    marginTop: theme.spacing(1),
    marginBottom: theme.spacing(1.5),
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
  nextStepText: {
    color: theme.palette.info.main,
    fontWeight: 600,
  },
}));

export const EntityScorecardCard = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const [expanded, setExpanded] = useState(false);

  const scorecard = evaluateScorecard(entity);

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

  return (
    <InfoCard
      title="Service Operational Maturity"
      subheader="Soundcheck Governance & Production Readiness"
    >
      <Grid container spacing={2}>
        <Grid item xs={12}>
          <Box
            display="flex"
            justifyContent="space-between"
            alignItems="center"
          >
            <Typography variant="subtitle1" style={{ fontWeight: 600 }}>
              Maturity Level
            </Typography>
            <Chip
              label={getTierEmoji(scorecard.tier)}
              className={getTierClass(scorecard.tier)}
            />
          </Box>

          <Box className={classes.progressContainer}>
            <Box display="flex" justifyContent="space-between" mb={0.5}>
              <Typography variant="caption" color="textSecondary">
                Compliance Score
              </Typography>
              <Typography variant="caption" style={{ fontWeight: 700 }}>
                {scorecard.scorePercent}%
              </Typography>
            </Box>
            <LinearProgress
              variant="determinate"
              value={scorecard.scorePercent}
              color={scorecard.tier === "Gold" ? "primary" : "secondary"}
            />
          </Box>

          {scorecard.nextSteps.length > 0 && (
            <Box
              mt={1}
              mb={1}
              p={1.5}
              bgcolor="background.default"
              borderRadius={4}
            >
              <Typography
                variant="caption"
                style={{ fontWeight: 700, display: "block" }}
              >
                Next Milestones to Level Up:
              </Typography>
              <ul style={{ margin: "4px 0 0 0", paddingLeft: 20 }}>
                {scorecard.nextSteps.map((step) => (
                  <li key={step}>
                    <Typography
                      variant="caption"
                      className={classes.nextStepText}
                    >
                      {step}
                    </Typography>
                  </li>
                ))}
              </ul>
            </Box>
          )}

          <Box display="flex" justifyContent="flex-end" mt={1}>
            <Button
              size="small"
              onClick={() => setExpanded(!expanded)}
              endIcon={expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
            >
              {expanded ? "Hide Audit Checklist" : "Show Audit Checklist"}
            </Button>
          </Box>

          <Collapse in={expanded}>
            <List dense disablePadding>
              {scorecard.checks.map((check) => (
                <ListItem
                  key={check.id}
                  className={classes.checkItem}
                  disableGutters
                >
                  <ListItemIcon style={{ minWidth: 32 }}>
                    {check.passed ? (
                      <CheckCircleIcon
                        fontSize="small"
                        className={classes.checkPassed}
                      />
                    ) : (
                      <CancelIcon
                        fontSize="small"
                        className={classes.checkFailed}
                      />
                    )}
                  </ListItemIcon>
                  <ListItemText
                    primary={
                      <Typography variant="body2" style={{ fontWeight: 600 }}>
                        [{check.tier}] {check.title}
                      </Typography>
                    }
                    secondary={check.message}
                  />
                </ListItem>
              ))}
            </List>
          </Collapse>
        </Grid>
      </Grid>
    </InfoCard>
  );
};
