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

import { useRef } from "react";

/**
 * Hook that always returns a ref with the latest value.
 *
 * This is useful for accessing current state in event handlers or callbacks
 * without creating stale closures. The ref is updated synchronously on every
 * render, ensuring callbacks always have access to the most recent value.
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const [count, setCount] = useState(0);
 *   const countRef = useLatest(count);
 *
 *   useEffect(() => {
 *     const handler = () => {
 *       // Always gets the current count, not the value at effect creation time
 *       console.log(countRef.current);
 *     };
 *     window.addEventListener('click', handler);
 *     return () => window.removeEventListener('click', handler);
 *   }, []); // Safe to have empty deps because we use ref
 *
 *   return <button onClick={() => setCount(c => c + 1)}>Count: {count}</button>;
 * }
 * ```
 *
 * @param value - The value to keep current
 * @returns A ref object that always contains the latest value
 */
export function useLatest<T>(value: T): React.RefObject<T> {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}

export default useLatest;
