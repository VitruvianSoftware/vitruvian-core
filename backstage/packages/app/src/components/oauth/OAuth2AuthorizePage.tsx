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
import { useParams } from "react-router-dom";
import useAsync from "react-use/lib/useAsync";
import {
  Content,
  Header,
  InfoCard,
  Page,
  Progress,
  ResponseErrorPanel,
} from "@backstage/core-components";
import {
  discoveryApiRef,
  fetchApiRef,
  useApi,
} from "@backstage/core-plugin-api";
import Box from "@material-ui/core/Box";
import Button from "@material-ui/core/Button";
import Chip from "@material-ui/core/Chip";
import Divider from "@material-ui/core/Divider";
import Typography from "@material-ui/core/Typography";

export interface SessionDetails {
  id: string;
  clientId: string;
  clientName?: string;
  scope?: string;
  redirectUri: string;
}

export const OAuth2AuthorizePage = () => {
  const { sessionId } = useParams<{ sessionId: string }>();
  const discoveryApi = useApi(discoveryApiRef);
  const fetchApi = useApi(fetchApiRef);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<Error | undefined>();

  const {
    value: session,
    loading,
    error,
  } = useAsync(async (): Promise<SessionDetails> => {
    if (!sessionId) {
      throw new Error("Missing sessionId parameter");
    }
    const baseUrl = await discoveryApi.getBaseUrl("auth");
    const res = await fetchApi.fetch(
      `${baseUrl}/v1/sessions/${encodeURIComponent(sessionId)}`,
    );
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(
        body.error_description ||
          body.error ||
          `Failed to fetch session: ${res.statusText}`,
      );
    }
    return res.json();
  }, [sessionId, discoveryApi, fetchApi]);

  const handleApprove = async () => {
    if (!sessionId) return;
    setSubmitting(true);
    setActionError(undefined);
    try {
      const baseUrl = await discoveryApi.getBaseUrl("auth");
      const res = await fetchApi.fetch(
        `${baseUrl}/v1/sessions/${encodeURIComponent(sessionId)}/approve`,
        { method: "POST" },
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          body.error_description ||
            body.error ||
            `Approval failed: ${res.statusText}`,
        );
      }
      const { redirectUrl } = await res.json();
      window.location.href = redirectUrl;
    } catch (err) {
      setSubmitting(false);
      setActionError(err instanceof Error ? err : new Error(String(err)));
    }
  };

  const handleReject = async () => {
    if (!sessionId) return;
    setSubmitting(true);
    setActionError(undefined);
    try {
      const baseUrl = await discoveryApi.getBaseUrl("auth");
      const res = await fetchApi.fetch(
        `${baseUrl}/v1/sessions/${encodeURIComponent(sessionId)}/reject`,
        { method: "POST" },
      );
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(
          body.error_description ||
            body.error ||
            `Rejection failed: ${res.statusText}`,
        );
      }
      const { redirectUrl } = await res.json();
      window.location.href = redirectUrl;
    } catch (err) {
      setSubmitting(false);
      setActionError(err instanceof Error ? err : new Error(String(err)));
    }
  };

  if (loading) {
    return (
      <Page themeId="home">
        <Header title="Authorize Application" />
        <Content>
          <Progress />
        </Content>
      </Page>
    );
  }

  if (error || !session) {
    return (
      <Page themeId="home">
        <Header title="Authorize Application" />
        <Content>
          <ResponseErrorPanel error={error || new Error("Session not found")} />
        </Content>
      </Page>
    );
  }

  const clientDisplayName = session.clientName || session.clientId;
  const scopes = session.scope
    ? session.scope.split(/\s+/).filter(Boolean)
    : [];

  return (
    <Page themeId="home">
      <Header title="Authorize Application" />
      <Content>
        <Box display="flex" justifyContent="center" alignItems="center" mt={4}>
          <Box maxWidth={600} width="100%">
            <InfoCard title="Application Authorization Request">
              {actionError && <ResponseErrorPanel error={actionError} />}
              <Box my={2}>
                <Typography variant="body1">
                  <strong>{clientDisplayName}</strong> is requesting permission
                  to access the Vitruvian Developer Portal on your behalf.
                </Typography>
              </Box>

              <Divider />

              <Box my={2}>
                <Typography variant="subtitle2" gutterBottom>
                  Requested Scopes:
                </Typography>
                {scopes.length > 0 ? (
                  <Box display="flex" flexWrap="wrap" my={1}>
                    {scopes.map((s) => (
                      <Box key={s} mr={1} mb={1}>
                        <Chip
                          label={s}
                          color="primary"
                          variant="outlined"
                          size="small"
                        />
                      </Box>
                    ))}
                  </Box>
                ) : (
                  <Typography variant="body2" color="textSecondary">
                    Default access
                  </Typography>
                )}
              </Box>

              <Box my={2}>
                <Typography
                  variant="caption"
                  color="textSecondary"
                  display="block"
                >
                  Redirect URI: {session.redirectUri}
                </Typography>
              </Box>

              <Divider />

              <Box mt={3} display="flex" justifyContent="flex-end">
                <Box mr={2}>
                  <Button
                    variant="outlined"
                    color="secondary"
                    disabled={submitting}
                    onClick={handleReject}
                  >
                    Deny
                  </Button>
                </Box>
                <Button
                  variant="contained"
                  color="primary"
                  disabled={submitting}
                  onClick={handleApprove}
                >
                  {submitting ? "Authorizing..." : "Authorize"}
                </Button>
              </Box>
            </InfoCard>
          </Box>
        </Box>
      </Content>
    </Page>
  );
};
