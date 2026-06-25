/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import React, { useState } from "react";
import type { AppUser, ApiEndpoint, ApiExploreResponse } from "../types";
import { Spinner } from "./icons";
import JsonTree from "./JsonTree";
import { getProviderEndpoints } from "../utils/apiEndpoints";

interface ApiExplorerProps {
  user: AppUser;
}

const ApiExplorer: React.FC<ApiExplorerProps> = ({ user }) => {
  const [selectedEndpoint, setSelectedEndpoint] = useState<ApiEndpoint | null>(
    null,
  );
  const [isLoading, setIsLoading] = useState(false);
  const [response, setResponse] = useState<ApiExploreResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const endpoints = getProviderEndpoints(user.provider);

  const handleEndpointCall = async (endpoint: ApiEndpoint) => {
    setIsLoading(true);
    setError(null);
    setResponse(null);
    setSelectedEndpoint(endpoint);

    try {
      const requestBody = {
        provider: user.provider,
        accessToken: user.accessToken,
        endpoint,
      };

      const apiResponse = await fetch("/api/explore", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestBody),
      });

      const responseData = await apiResponse.json();

      if (!apiResponse.ok) {
        throw new Error(responseData.error || "API call failed");
      }

      setResponse(responseData);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const getUserScopes = (): string[] => {
    return user.scopes || [];
  };

  const hasRequiredScopes = (endpoint: ApiEndpoint): boolean => {
    if (!endpoint.requiredScopes) return true;
    const userScopes = getUserScopes();
    return endpoint.requiredScopes.some((scope) => userScopes.includes(scope));
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-slate-200 mb-2">
          API Explorer
        </h3>
        <p className="text-sm text-slate-400 mb-4">
          Test your access token against common {user.provider} API endpoints.
          {user.scopes && user.scopes.length > 0 && (
            <span className="block mt-1">
              Available scopes: {user.scopes.join(", ")}
            </span>
          )}
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Endpoints List */}
        <div>
          <h4 className="text-md font-medium text-slate-300 mb-3">
            Available Endpoints
          </h4>
          <div className="space-y-2">
            {endpoints.map((endpoint) => {
              const hasScopes = hasRequiredScopes(endpoint);
              const isSelected = selectedEndpoint?.id === endpoint.id;

              return (
                <button
                  key={endpoint.id}
                  onClick={() => handleEndpointCall(endpoint)}
                  disabled={isLoading || !hasScopes}
                  className={`w-full text-left p-3 rounded-md border transition-colors ${
                    isSelected
                      ? "border-blue-500 bg-blue-500/10"
                      : hasScopes
                        ? "border-slate-600 bg-slate-800/50 hover:bg-slate-700/50 hover:border-slate-500"
                        : "border-slate-700 bg-slate-800/30 opacity-50 cursor-not-allowed"
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-medium text-slate-200">
                          {endpoint.name}
                        </span>
                        <span className="text-xs bg-slate-700 text-slate-300 px-2 py-0.5 rounded">
                          {endpoint.method}
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 mb-2">
                        {endpoint.description}
                      </p>
                      {endpoint.requiredScopes && (
                        <div className="text-xs">
                          <span className="text-slate-500">
                            Required scopes:{" "}
                          </span>
                          <span
                            className={
                              hasScopes ? "text-green-400" : "text-red-400"
                            }
                          >
                            {endpoint.requiredScopes.join(", ")}
                          </span>
                        </div>
                      )}
                    </div>
                    {isLoading && isSelected && (
                      <Spinner className="w-4 h-4 text-blue-400" />
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* Response Display */}
        <div>
          <h4 className="text-md font-medium text-slate-300 mb-3">Response</h4>

          {!selectedEndpoint && !response && !error && (
            <div className="h-64 border border-slate-700 rounded-md bg-slate-800/30 flex items-center justify-center">
              <p className="text-slate-500 text-center">
                Select an endpoint to see the API response
              </p>
            </div>
          )}

          {error && (
            <div className="p-4 border border-red-500/40 bg-red-900/40 rounded-md">
              <h5 className="font-medium text-red-300 mb-2">Error</h5>
              <p className="text-red-200 text-sm">{error}</p>
            </div>
          )}

          {response && !error && (
            <div className="space-y-4">
              {/* Response metadata */}
              <div className="p-3 border border-slate-600 bg-slate-800/50 rounded-md">
                <div className="flex items-center justify-between mb-2">
                  <h5 className="font-medium text-slate-200">
                    Response Details
                  </h5>
                  <span
                    className={`px-2 py-1 text-xs rounded ${
                      response.status && response.status < 300
                        ? "bg-green-500/20 text-green-300"
                        : "bg-red-500/20 text-red-300"
                    }`}
                  >
                    {response.status || "200"}
                  </span>
                </div>
                {selectedEndpoint && (
                  <div className="text-xs text-slate-400 space-y-1">
                    <div>
                      <span className="font-medium">URL:</span>{" "}
                      {selectedEndpoint.url}
                    </div>
                    <div>
                      <span className="font-medium">Method:</span>{" "}
                      {selectedEndpoint.method}
                    </div>
                  </div>
                )}
              </div>

              {/* Response data */}
              {response.data && (
                <div className="border border-slate-600 bg-slate-800/50 rounded-md">
                  <div className="p-3 border-b border-slate-600">
                    <h5 className="font-medium text-slate-200">
                      Response Data
                    </h5>
                  </div>
                  <div className="p-3">
                    <JsonTree
                      data={response.data}
                      maxDepth={3}
                      showCopyButtons={true}
                    />
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default ApiExplorer;
