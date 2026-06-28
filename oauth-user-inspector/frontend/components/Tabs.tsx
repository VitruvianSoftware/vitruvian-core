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

import React, { useState, ReactNode, useEffect } from "react";

interface TabProps {
  label: string;
  children: ReactNode;
  icon?: React.JSX.Element;
}

export const Tab: React.FC<TabProps> = ({ children }) => {
  return <>{children}</>;
};

interface TabsProps {
  children: React.ReactElement<TabProps>[];
}

const Tabs: React.FC<TabsProps> = ({ children }) => {
  const [activeTab, setActiveTab] = useState(() => {
    const saved = localStorage.getItem("active_provider_tab");
    return saved ? Number(saved) : 0;
  });

  useEffect(() => {
    localStorage.setItem("active_provider_tab", String(activeTab));
  }, [activeTab]);

  return (
    <div>
      <div className="flex border-b border-slate-700 -mx-8 px-8">
        {children.map((child, index) => (
          <button
            key={index}
            onClick={() => setActiveTab(index)}
            className={`flex items-center px-4 py-3 text-sm font-medium transition-colors duration-200 ease-in-out focus:outline-none -mb-px ${
              activeTab === index
                ? "border-b-2 border-blue-400 text-white"
                : "text-slate-400 hover:text-white border-b-2 border-transparent"
            }`}
          >
            {child.props.icon && (
              <span className="mr-2 h-5 w-5">{child.props.icon}</span>
            )}
            {child.props.label}
          </button>
        ))}
      </div>
      <div className="pt-8">{children[activeTab]}</div>
    </div>
  );
};

export default Tabs;
