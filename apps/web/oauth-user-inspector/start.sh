#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

echo "🚀 Starting OAuth User Inspector"
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"
echo "Working directory: $(pwd)"
echo "Environment: ${NODE_ENV:-development}"
echo "Port: ${PORT:-8080}"

# Check if frontend dist directory exists
if [ ! -d "dist" ]; then
	echo "❌ Error: dist directory (frontend) not found. Frontend build may have failed."
	ls -la
	exit 1
fi

# Check if server dist directory exists
if [ ! -d "dist-server" ]; then
	echo "❌ Error: dist-server directory not found. Server build may have failed."
	ls -la
	exit 1
fi

# Check if server.js exists
if [ ! -f "dist-server/server.js" ]; then
	echo "❌ Error: dist-server/server.js not found. Server build may have failed."
	ls -la dist-server/
	exit 1
fi

echo "✅ Build files found, starting server..."
echo "Contents of dist/ (frontend):"
ls -la dist/
echo "Contents of dist-server/ (backend):"
ls -la dist-server/

# Start the server
exec node dist-server/server.js
