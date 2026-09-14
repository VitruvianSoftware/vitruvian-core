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
  Button,
  Box,
  CircularProgress,
  Typography,
  makeStyles,
} from "@material-ui/core";
import OpenInNewIcon from "@material-ui/icons/OpenInNew";
import { InfoCard, WarningPanel } from "@backstage/core-components";
import { useEntity } from "@backstage/plugin-catalog-react";
import { getStorybookUrl } from "./storybook";

const useStyles = makeStyles((theme) => ({
  container: {
    position: "relative",
    width: "100%",
    minHeight: 380,
    height: 400,
    backgroundColor: theme.palette.background.paper,
    borderRadius: theme.shape.borderRadius,
    overflow: "hidden",
    border: `1px solid ${theme.palette.divider}`,
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
    zIndex: 1,
  },
}));

export const EntityStorybookCard = () => {
  const classes = useStyles();
  const { entity } = useEntity();
  const storybookUrl = getStorybookUrl(entity);
  const [loading, setLoading] = useState(true);

  if (!storybookUrl) {
    return (
      <InfoCard title="Storybook Preview">
        <WarningPanel
          title="Storybook URL Not Configured"
          message="This entity does not declare a valid 'storybook.io/url' annotation."
        />
      </InfoCard>
    );
  }

  return (
    <InfoCard
      title="Storybook Preview"
      action={
        <Button
          color="primary"
          href={storybookUrl}
          target="_blank"
          rel="noopener noreferrer"
          endIcon={<OpenInNewIcon />}
          size="small"
        >
          Open Storybook
        </Button>
      }
    >
      <Box className={classes.container}>
        {loading && (
          <Box className={classes.loadingOverlay}>
            <CircularProgress size={36} />
            <Box mt={2}>
              <Typography variant="body2" color="textSecondary">
                Loading Storybook preview...
              </Typography>
            </Box>
          </Box>
        )}
        <iframe
          src={storybookUrl}
          title={`Storybook preview for ${entity.metadata.name}`}
          className={classes.iframe}
          sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-presentation"
          onLoad={() => setLoading(false)}
        />
      </Box>
    </InfoCard>
  );
};
