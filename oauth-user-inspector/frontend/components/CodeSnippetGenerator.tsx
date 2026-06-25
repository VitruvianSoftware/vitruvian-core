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

import React, { useState, useMemo, useEffect } from "react";
import type { AppUser, ApiEndpoint } from "../types";
import { ClipboardIcon, ClipboardCheckIcon } from "./icons";
import { getProviderEndpoints } from "../utils/apiEndpoints";

interface CodeSnippetGeneratorProps {
  user: AppUser;
  selectedEndpoint?: ApiEndpoint | null;
}

type CodeLanguage = "curl" | "nodejs" | "python" | "go";

interface CopyState {
  [key: string]: boolean;
}

const CodeSnippetGenerator: React.FC<CodeSnippetGeneratorProps> = ({
  user,
  selectedEndpoint,
}) => {
  const [selectedLanguage, setSelectedLanguage] =
    useState<CodeLanguage>("curl");
  const [copyStates, setCopyStates] = useState<CopyState>({});
  const [maskToken, setMaskToken] = useState(true);

  const endpoints = useMemo(
    () => getProviderEndpoints(user.provider),
    [user.provider],
  );
  const [selectedEndpointLocal, setSelectedEndpointLocal] =
    useState<ApiEndpoint | null>(
      selectedEndpoint || (endpoints.length > 0 ? endpoints[0] : null),
    );

  // Reset selected endpoint when provider changes
  useEffect(() => {
    if (!selectedEndpoint && endpoints.length > 0) {
      setSelectedEndpointLocal(endpoints[0]);
    }
  }, [user.provider, selectedEndpoint]); // Remove 'endpoints' from dependency array

  // Use the passed selectedEndpoint if available, otherwise use local selection
  const currentEndpoint = selectedEndpoint || selectedEndpointLocal;

  const accessToken = user.accessToken || "your_access_token_here";
  const displayToken = maskToken
    ? accessToken.length > 8
      ? `${accessToken.substring(0, 4)}${"•".repeat(12)}${accessToken.substring(accessToken.length - 4)}`
      : "••••••••"
    : accessToken;

  const generateCurlSnippet = (endpoint: ApiEndpoint): string => {
    const headers = [
      `'Authorization: Bearer ${displayToken}'`,
      `'Accept: application/json'`,
      `'User-Agent: YourAppName/1.0'`,
    ];

    if (endpoint.method !== "GET") {
      headers.push(`'Content-Type: application/json'`);
    }

    let snippet = `curl -X ${endpoint.method} \\\n`;
    snippet += `  '${endpoint.url}' \\\n`;
    headers.forEach((header, index) => {
      snippet += `  -H ${header}`;
      if (index < headers.length - 1) snippet += " \\\n";
    });

    if (
      endpoint.method === "POST" ||
      endpoint.method === "PUT" ||
      endpoint.method === "PATCH"
    ) {
      snippet += ` \\\n  -d '{}'`;
    }

    return snippet;
  };

  const generateNodeJSSnippet = (endpoint: ApiEndpoint): string => {
    const fetchOptions = {
      method: endpoint.method,
      headers: {
        Authorization: `Bearer ${displayToken}`,
        Accept: "application/json",
        "User-Agent": "YourAppName/1.0",
      } as any,
    };

    if (endpoint.method !== "GET") {
      fetchOptions.headers["Content-Type"] = "application/json";
    }

    if (
      endpoint.method === "POST" ||
      endpoint.method === "PUT" ||
      endpoint.method === "PATCH"
    ) {
      (fetchOptions as any).body = "JSON.stringify({})";
    }

    let snippet = `// Using fetch API\n`;
    snippet += `const response = await fetch('${endpoint.url}', {\n`;
    snippet += `  method: '${endpoint.method}',\n`;
    snippet += `  headers: {\n`;
    Object.entries(fetchOptions.headers).forEach(([key, value]) => {
      snippet += `    '${key}': '${value}',\n`;
    });
    snippet += `  }`;

    if (fetchOptions.body) {
      snippet += `,\n  body: JSON.stringify({}) // Add your data here`;
    }

    snippet += `\n});\n\n`;
    snippet += `const data = await response.json();\nconsole.log(data);`;

    return snippet;
  };

  const generatePythonSnippet = (endpoint: ApiEndpoint): string => {
    const headers = {
      Authorization: `Bearer ${displayToken}`,
      Accept: "application/json",
      "User-Agent": "YourAppName/1.0",
    } as any;

    if (endpoint.method !== "GET") {
      headers["Content-Type"] = "application/json";
    }

    let snippet = `import requests\nimport json\n\n`;
    snippet += `# API endpoint and headers\n`;
    snippet += `url = '${endpoint.url}'\n`;
    snippet += `headers = {\n`;
    Object.entries(headers).forEach(([key, value]) => {
      snippet += `    '${key}': '${value}',\n`;
    });
    snippet += `}\n\n`;

    if (endpoint.method === "GET") {
      snippet += `# Make the request\n`;
      snippet += `response = requests.get(url, headers=headers)\n\n`;
    } else {
      snippet += `# Request data (modify as needed)\n`;
      snippet += `data = {}\n\n`;
      snippet += `# Make the request\n`;
      snippet += `response = requests.${endpoint.method.toLowerCase()}(url, headers=headers, json=data)\n\n`;
    }

    snippet += `# Check the response\n`;
    snippet += `if response.status_code == 200:\n`;
    snippet += `    result = response.json()\n`;
    snippet += `    print(json.dumps(result, indent=2))\n`;
    snippet += `else:\n`;
    snippet += `    print(f'Error: {response.status_code} - {response.text}')`;

    return snippet;
  };

  const generateGoSnippet = (endpoint: ApiEndpoint): string => {
    let snippet = `package main\n\n`;
    snippet += `import (\n`;
    snippet += `    "bytes"\n`;
    snippet += `    "encoding/json"\n`;
    snippet += `    "fmt"\n`;
    snippet += `    "io"\n`;
    snippet += `    "net/http"\n`;
    snippet += `)\n\n`;
    snippet += `func main() {\n`;
    snippet += `    url := "${endpoint.url}"\n`;

    if (endpoint.method !== "GET") {
      snippet += `    // Request payload (modify as needed)\n`;
      snippet += `    payload := map[string]interface{}{}\n`;
      snippet += `    jsonPayload, _ := json.Marshal(payload)\n\n`;
      snippet += `    req, err := http.NewRequest("${endpoint.method}", url, bytes.NewBuffer(jsonPayload))\n`;
    } else {
      snippet += `\n    req, err := http.NewRequest("${endpoint.method}", url, nil)\n`;
    }

    snippet += `    if err != nil {\n`;
    snippet += `        fmt.Printf("Error creating request: %v\\n", err)\n`;
    snippet += `        return\n`;
    snippet += `    }\n\n`;
    snippet += `    // Set headers\n`;
    snippet += `    req.Header.Set("Authorization", "Bearer ${displayToken}")\n`;
    snippet += `    req.Header.Set("Accept", "application/json")\n`;
    snippet += `    req.Header.Set("User-Agent", "YourAppName/1.0")\n`;

    if (endpoint.method !== "GET") {
      snippet += `    req.Header.Set("Content-Type", "application/json")\n`;
    }

    snippet += `\n    client := &http.Client{}\n`;
    snippet += `    resp, err := client.Do(req)\n`;
    snippet += `    if err != nil {\n`;
    snippet += `        fmt.Printf("Error making request: %v\\n", err)\n`;
    snippet += `        return\n`;
    snippet += `    }\n`;
    snippet += `    defer resp.Body.Close()\n\n`;
    snippet += `    body, err := io.ReadAll(resp.Body)\n`;
    snippet += `    if err != nil {\n`;
    snippet += `        fmt.Printf("Error reading response: %v\\n", err)\n`;
    snippet += `        return\n`;
    snippet += `    }\n\n`;
    snippet += `    if resp.StatusCode == 200 {\n`;
    snippet += `        var result map[string]interface{}\n`;
    snippet += `        json.Unmarshal(body, &result)\n`;
    snippet += `        prettyJSON, _ := json.MarshalIndent(result, "", "  ")\n`;
    snippet += `        fmt.Println(string(prettyJSON))\n`;
    snippet += `    } else {\n`;
    snippet += `        fmt.Printf("Error: %d - %s\\n", resp.StatusCode, string(body))\n`;
    snippet += `    }\n`;
    snippet += `}`;

    return snippet;
  };

  const generateSnippet = (
    endpoint: ApiEndpoint,
    language: CodeLanguage,
  ): string => {
    switch (language) {
      case "curl":
        return generateCurlSnippet(endpoint);
      case "nodejs":
        return generateNodeJSSnippet(endpoint);
      case "python":
        return generatePythonSnippet(endpoint);
      case "go":
        return generateGoSnippet(endpoint);
      default:
        return "";
    }
  };

  const handleCopy = async (snippetId: string, content: string) => {
    try {
      await navigator.clipboard.writeText(content);
      setCopyStates((prev) => ({ ...prev, [snippetId]: true }));
      setTimeout(() => {
        setCopyStates((prev) => ({ ...prev, [snippetId]: false }));
      }, 2000);
    } catch (err) {
      console.error("Failed to copy text:", err);
    }
  };

  const getLanguageExtension = (language: CodeLanguage): string => {
    switch (language) {
      case "curl":
        return "bash";
      case "nodejs":
        return "javascript";
      case "python":
        return "python";
      case "go":
        return "go";
      default:
        return "";
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-slate-200 mb-2">
          Code Snippet Generator
        </h3>
        <p className="text-sm text-slate-400 mb-4">
          Generate ready-to-use code examples for integrating your OAuth token
          with {user.provider} APIs.
        </p>
      </div>

      {/* Controls */}
      <div className="flex flex-wrap gap-4 items-center">
        {/* Endpoint Selection (if not provided externally) */}
        {!selectedEndpoint && endpoints.length > 0 && (
          <div className="flex-1 min-w-0">
            <label className="block text-xs text-slate-400 mb-1">
              API Endpoint
            </label>
            <select
              value={selectedEndpointLocal?.id || ""}
              onChange={(e) =>
                setSelectedEndpointLocal(
                  endpoints.find((ep) => ep.id === e.target.value) || null,
                )
              }
              className="w-full text-sm px-3 py-2 bg-slate-800 border border-slate-600 rounded-md focus:outline-none focus:ring-2 focus:ring-slate-500 text-slate-200"
            >
              {endpoints.map((endpoint) => (
                <option key={endpoint.id} value={endpoint.id}>
                  {endpoint.name} ({endpoint.method})
                </option>
              ))}
            </select>
          </div>
        )}

        {/* Language Selection */}
        <div>
          <label className="block text-xs text-slate-400 mb-1">Language</label>
          <div className="flex bg-slate-800 border border-slate-600 rounded-md overflow-hidden">
            {(["curl", "nodejs", "python", "go"] as const).map((lang) => (
              <button
                key={lang}
                onClick={() => setSelectedLanguage(lang)}
                className={`px-3 py-2 text-xs font-medium transition-colors ${
                  selectedLanguage === lang
                    ? "bg-slate-600 text-white"
                    : "text-slate-300 hover:bg-slate-700"
                }`}
              >
                {lang === "nodejs" ? "Node.js" : lang.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        {/* Token Masking Toggle */}
        <div>
          <label className="block text-xs text-slate-400 mb-1">Security</label>
          <button
            onClick={() => setMaskToken(!maskToken)}
            className={`px-3 py-2 text-xs font-medium rounded-md border transition-colors ${
              maskToken
                ? "bg-green-500/20 border-green-500/40 text-green-300"
                : "bg-yellow-500/20 border-yellow-500/40 text-yellow-300"
            }`}
          >
            {maskToken ? "🔒 Token Masked" : "👁️ Token Visible"}
          </button>
        </div>
      </div>

      {/* Code Snippet Display */}
      {currentEndpoint && (
        <div className="space-y-4">
          {/* Endpoint Info */}
          <div className="p-3 bg-slate-800/50 border border-slate-600 rounded-md">
            <div className="flex items-center gap-2 mb-2">
              <h4 className="text-sm font-medium text-slate-200">
                {currentEndpoint.name}
              </h4>
              <span className="text-xs bg-slate-700 text-slate-300 px-2 py-0.5 rounded">
                {currentEndpoint.method}
              </span>
            </div>
            <p className="text-xs text-slate-400 mb-2">
              {currentEndpoint.description}
            </p>
            <div className="text-xs text-slate-500">
              <span className="font-medium">URL:</span> {currentEndpoint.url}
            </div>
            {currentEndpoint.requiredScopes && (
              <div className="text-xs text-slate-500">
                <span className="font-medium">Required scopes:</span>{" "}
                {currentEndpoint.requiredScopes.join(", ")}
              </div>
            )}
          </div>

          {/* Generated Code */}
          <div className="relative">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium text-slate-200">
                  {selectedLanguage === "nodejs"
                    ? "Node.js"
                    : selectedLanguage === "go"
                      ? "Go"
                      : selectedLanguage.toUpperCase()}{" "}
                  Example
                </span>
                <span className="text-xs text-slate-500">
                  ({getLanguageExtension(selectedLanguage)})
                </span>
              </div>
              <button
                onClick={() =>
                  handleCopy(
                    `${currentEndpoint.id}-${selectedLanguage}`,
                    generateSnippet(currentEndpoint, selectedLanguage),
                  )
                }
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-slate-700/50 border border-slate-600 rounded-md text-slate-300 hover:bg-slate-700 transition-colors"
              >
                {copyStates[`${currentEndpoint.id}-${selectedLanguage}`] ? (
                  <>
                    <ClipboardCheckIcon className="w-3 h-3 text-green-400" />
                    Copied!
                  </>
                ) : (
                  <>
                    <ClipboardIcon className="w-3 h-3" />
                    Copy
                  </>
                )}
              </button>
            </div>

            <div className="bg-slate-900 border border-slate-700 rounded-md overflow-hidden">
              <pre className="p-4 text-xs text-slate-200 overflow-x-auto">
                <code
                  className={`language-${getLanguageExtension(selectedLanguage)}`}
                >
                  {generateSnippet(currentEndpoint, selectedLanguage)}
                </code>
              </pre>
            </div>
          </div>

          {/* Usage Notes */}
          <div className="p-3 bg-blue-900/20 border border-blue-500/30 rounded-md">
            <h5 className="text-xs font-medium text-blue-300 mb-2">
              💡 Usage Notes
            </h5>
            <ul className="text-xs text-blue-200 space-y-1">
              <li>
                • Replace the access token with your actual token when using
              </li>
              <li>
                • Modify request data as needed for POST/PUT/PATCH requests
              </li>
              <li>• Add proper error handling for production use</li>
              {selectedLanguage === "python" && (
                <li>
                  • Install requests library:{" "}
                  <code className="bg-slate-800 px-1 rounded">
                    pip install requests
                  </code>
                </li>
              )}
              {selectedLanguage === "go" && (
                <>
                  <li>
                    • Run with:{" "}
                    <code className="bg-slate-800 px-1 rounded">
                      go run main.go
                    </code>
                  </li>
                  <li>
                    • No external dependencies required (uses standard library)
                  </li>
                </>
              )}
              {currentEndpoint.requiredScopes && (
                <li>
                  • Ensure your token has the required scopes:{" "}
                  {currentEndpoint.requiredScopes.join(", ")}
                </li>
              )}
            </ul>
          </div>
        </div>
      )}

      {(!currentEndpoint || endpoints.length === 0) && (
        <div className="p-8 border border-slate-700 rounded-md bg-slate-800/30 text-center">
          <p className="text-slate-500">
            No API endpoints available for code generation
          </p>
        </div>
      )}
    </div>
  );
};

export default CodeSnippetGenerator;
