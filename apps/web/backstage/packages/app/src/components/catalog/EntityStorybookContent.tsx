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
  Button,
  CircularProgress,
  IconButton,
  Paper,
  Tooltip,
  Typography,
  makeStyles,
} from "@material-ui/core";
import OpenInNewIcon from "@material-ui/icons/OpenInNew";
import RefreshIcon from "@material-ui/icons/Refresh";
import { WarningPanel } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import { getStorybookUrl } from "./storybook";

const useStyles = makeStyles((theme) => ({
  root: {
    display: "flex",
    flexDirection: "column",
    height: "calc(100vh - 220px)",
    minHeight: 650,
    marginTop: theme.spacing(2),
  },
  toolbar: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    padding: theme.spacing(1, 2),
    marginBottom: theme.spacing(1.5),
    backgroundColor: theme.palette.background.paper,
    borderRadius: theme.shape.borderRadius,
    border: `1px solid ${theme.palette.divider}`,
  },
  iframeContainer: {
    position: "relative",
    flex: 1,
    width: "100%",
    borderRadius: theme.shape.borderRadius,
    overflow: "hidden",
    border: `1px solid ${theme.palette.divider}`,
    backgroundColor: theme.palette.background.paper,
  },
  iframe: {
    width: "100%",
    height: "100%",
    border: "none",
  },
  loadingOverlay: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: theme.palette.background.default,
    zIndex: 2,
  },
}));

export const EntityStorybookContent = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const storybookUrl = getStorybookUrl(entity);
  const [loading, setLoading] = useState(true);
  const [key, setKey] = useState(0);

  if (!storybookUrl) {
    return (
      <Box mt={2}>
        <WarningPanel
          title="Storybook URL Not Configured"
          message={`Component '${entity.metadata.name}' does not declare a Storybook URL annotation ('storybook.io/url').`}
        />
      </Box>
    );
  }

  const handleRefresh = () => {
    setLoading(true);
    setKey((prev) => prev + 1);
  };

  return (
    <Box className={classes.root}>
      <Paper className={classes.toolbar} elevation={0}>
        <Box display="flex" alignItems="center">
          <Typography variant="subtitle1" style={{ fontWeight: 600 }}>
            Storybook Preview — {entity.metadata.title ?? entity.metadata.name}
          </Typography>
          <Box ml={2}>
            <Tooltip title="Reload Preview">
              <IconButton size="small" onClick={handleRefresh}>
                <RefreshIcon fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
        <Button
          color="primary"
          variant="outlined"
          size="small"
          href={storybookUrl}
          target="_blank"
          rel="noopener noreferrer"
          endIcon={<OpenInNewIcon />}
        >
          Open in Storybook
        </Button>
      </Paper>

      <Box className={classes.iframeContainer}>
        {loading && (
          <Box className={classes.loadingOverlay}>
            <CircularProgress size={42} />
            <Box mt={2}>
              <Typography variant="body2" color="textSecondary">
                Loading Storybook components...
              </Typography>
            </Box>
          </Box>
        )}
        <iframe
          key={key}
          src={storybookUrl}
          title={`Storybook tab for ${entity.metadata.name}`}
          className={classes.iframe}
          sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-presentation"
          onLoad={() => setLoading(false)}
        />
      </Box>
    </Box>
  );
};
