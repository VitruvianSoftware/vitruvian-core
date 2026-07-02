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

import React, { useState, useRef, useEffect } from "react";
import ReactDOM from "react-dom";
import { AnimatePresence, motion } from "framer-motion";

interface TooltipProps {
  content: React.ReactNode;
  children: React.ReactNode;
  delay?: number; // ms
  placement?: "top" | "bottom" | "left" | "right";
  shortcut?: string; // Optional keyboard shortcut to display
}

export const Tooltip: React.FC<TooltipProps> = ({
  content,
  children,
  delay = 500,
  placement = "top",
  shortcut,
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const [coords, setCoords] = useState({ left: 0, top: 0 });
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const triggerRef = useRef<HTMLDivElement>(null);

  const handleMouseEnter = () => {
    timeoutRef.current = setTimeout(() => {
      if (triggerRef.current) {
        const rect = triggerRef.current.getBoundingClientRect();
        let top = 0;
        let left = 0;
        const gap = 8;

        // Simple positioning logic
        // This calculates the CENTER of the tooltip relative to the trigger
        // We need to know user tooltip size, but we can center it via CSS transform

        switch (placement) {
          case "top":
            top = rect.top - gap;
            left = rect.left + rect.width / 2;
            break;
          case "bottom":
            top = rect.bottom + gap;
            left = rect.left + rect.width / 2;
            break;
          case "left":
            top = rect.top + rect.height / 2;
            left = rect.left - gap;
            break;
          case "right":
            top = rect.top + rect.height / 2;
            left = rect.right + gap;
            break;
          default:
            break;
        }

        setCoords({ left, top });
        setIsVisible(true);
      }
    }, delay);
  };

  const handleMouseLeave = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    setIsVisible(false);
  };

  useEffect(() => {
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  const getTransform = () => {
    switch (placement) {
      case "bottom":
        return "translate(-50%, 0)";
      case "left":
        return "translate(-100%, -50%)";
      case "right":
        return "translate(0, -50%)";
      case "top":
      default:
        return "translate(-50%, -100%)";
    }
  };

  return (
    <>
      <div
        ref={triggerRef}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        style={{ display: "contents" }} // Preserve layout
      >
        {children}
      </div>

      {ReactDOM.createPortal(
        <AnimatePresence>
          {isVisible && (
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              transition={{ duration: 0.1 }}
              style={{
                position: "fixed",
                top: coords.top,
                left: coords.left,
                transform: getTransform(),
                zIndex: 1000,
                pointerEvents: "none",
                backgroundColor: "#1F2937", // Dark gray (Tailwind gray-800 usually)
                color: "white",
                padding: "4px 8px",
                borderRadius: "4px",
                fontSize: "12px",
                whiteSpace: "nowrap",
                boxShadow:
                  "0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)",
                display: "flex",
                alignItems: "center",
                gap: "8px",
              }}
            >
              {content}
              {shortcut && (
                <span style={{ opacity: 0.6, fontSize: "10px" }}>
                  {shortcut}
                </span>
              )}
            </motion.div>
          )}
        </AnimatePresence>,
        document.body,
      )}
    </>
  );
};
