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

const path = require("path");
const webpack = require("webpack");
const CopyPlugin = require("copy-webpack-plugin");
const HtmlWebpackPlugin = require("html-webpack-plugin");

const isProduction =
  process.env.NODE_ENV === "production" || process.env.NODE_ENV === "staging";

const API_URL = process.env.API_URL || "http://localhost:8080/api/v1";

// Scope host_permissions to the API origin only (the sole cross-origin target).
// Avoids the "read all your data on all websites" install warning and shrinks
// the blast radius. The Google s2 favicon <img> needs no host permission.
function apiHostPermission() {
  try {
    return [`${new URL(API_URL).origin}/*`];
  } catch {
    return ["http://localhost:8080/*"];
  }
}

module.exports = {
  mode: isProduction ? "production" : "development",
  entry: {
    popup: "./src/popup/index.tsx",
    background: "./src/background/index.ts",
    dashboard: "./src/dashboard/index.tsx",
  },
  output: {
    // WEBPACK_OUT_DIR lets Bazel build variant bundles (e.g. the E2E
    // bundle with a test API_URL) at distinct output paths.
    path: path.resolve(__dirname, process.env.WEBPACK_OUT_DIR || "dist"),
    filename: "[name].js",
    clean: true,
  },
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: "ts-loader",
        exclude: /node_modules/,
      },
      {
        test: /\.css$/,
        use: ["style-loader", "css-loader"],
      },
    ],
  },
  resolve: {
    extensions: [".tsx", ".ts", ".js"],
  },
  plugins: [
    new HtmlWebpackPlugin({
      template: "./src/popup/popup.html",
      filename: "popup.html",
      chunks: ["popup"],
    }),
    new HtmlWebpackPlugin({
      template: "./src/dashboard/dashboard.html",
      filename: "dashboard.html",
      chunks: ["dashboard"],
    }),
    new CopyPlugin({
      patterns: [
        {
          from: "src/manifest.json",
          to: "manifest.json",
          transform(content) {
            const manifest = JSON.parse(content.toString());
            manifest.host_permissions = apiHostPermission();
            return JSON.stringify(manifest, null, 2);
          },
        },
        { from: "src/icons", to: "icons", noErrorOnMissing: true },
      ],
    }),
    new webpack.DefinePlugin({
      "process.env.API_URL": JSON.stringify(API_URL),
      "process.env.NODE_ENV": JSON.stringify(
        process.env.NODE_ENV || "development",
      ),
    }),
  ],
  devtool: "cheap-module-source-map",
};
