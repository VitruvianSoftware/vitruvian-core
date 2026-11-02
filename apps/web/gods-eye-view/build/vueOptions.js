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

/**
 * Template options shared by the browser build, the boundary check and the
 * unit-test loader. Whitespace between nodes is kept (as a single space) so
 * an application view renders as its static markup did; Prettier formats
 * single-file components with strict whitespace sensitivity to match. Asset
 * URLs such as `/pin.svg` stay literal instead of becoming module imports.
 */
export const VUE_TEMPLATE_OPTIONS = Object.freeze({
  compilerOptions: Object.freeze({ whitespace: 'preserve' }),
  transformAssetUrls: false,
});

/** `@vitejs/plugin-vue` options for application builds. */
export const VUE_PLUGIN_OPTIONS = Object.freeze({
  template: VUE_TEMPLATE_OPTIONS,
});
