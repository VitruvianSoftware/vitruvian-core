---
layout: page
title: Tech Stack
permalink: /tech-stack/
---

<!-- Split Hero Section -->
<div class="split-hero">
  <div class="hero-content">
    <span class="tag">Architecture</span>
    <h1>Our Technology Stack</h1>
    <p>The cutting-edge technologies, languages, and frameworks that power our open-source solutions and drive innovation in AI, Platform engineering, and cloud computing.</p>
  </div>
  <div class="hero-visual">
    <img src="/images/tech_stack_hero.png" alt="Server Hardware Logic Schematic">
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    <h2>🖥️ Programming Languages</h2>
    <p class="mb-2">Core languages we use to build robust and scalable solutions:</p>
    
    <div class="cards-grid">
      <div class="card">
        <h3>🚀 Go</h3>
        <p><strong>Primary Use:</strong> Cloud Services, Microservices, CLI Tools</p>
        <p>For high-performance cloud-native applications and our DevX and Homelab CLI tooling. Excellent for reproducible, statically-compiled binary distribution.</p>
        <div style="margin-top: 1rem; display: flex; gap: 0.5rem; flex-wrap: wrap;">
          <span style="background: var(--primary-accent); color: white; padding: 0.2rem 0.5rem; border-radius: var(--border-radius-sm); font-size: 0.8rem;">Cobra</span>
          <span style="background: var(--primary-accent); color: white; padding: 0.2rem 0.5rem; border-radius: var(--border-radius-sm); font-size: 0.8rem;">GoReleaser</span>
        </div>
      </div>

      <div class="card">
        <h3>⚡ TypeScript / JavaScript</h3>
        <p><strong>Primary Use:</strong> Frontend, Electron, Web</p>
        <p>For building modern web interfaces, agentic bridge integrations (like the NexusAgent Node components), and our ecosystem documentation sites.</p>
        <div style="margin-top: 1rem; display: flex; gap: 0.5rem; flex-wrap: wrap;">
          <span style="background: var(--primary-accent); color: white; padding: 0.2rem 0.5rem; border-radius: var(--border-radius-sm); font-size: 0.8rem;">Node.js</span>
          <span style="background: var(--primary-accent); color: white; padding: 0.2rem 0.5rem; border-radius: var(--border-radius-sm); font-size: 0.8rem;">React</span>
        </div>
      </div>

      <div class="card">
        <h3>🏗️ SCSS & Jekyll</h3>
        <p><strong>Primary Use:</strong> Documentation & Marketing Sites</p>
        <p>Static site generation for documentation and project websites, built with custom premium dark-theme SCSS architectures.</p>
      </div>

      <div class="card">
        <h3>🐚 Shell & Bash</h3>
        <p><strong>Primary Use:</strong> Automation, Platform workflows</p>
        <p>Stringent shell scripting for initialization workflows and system-level configuration.</p>
      </div>
    </div>
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    <h2>☁️ Cloud & Infrastructure</h2>
    <p class="mb-2">Cloud platforms and infrastructure tools we leverage:</p>
    
    <div class="cards-grid">
      <div class="card">
        <h3>☸️ Kubernetes (K3s)</h3>
        <p><strong>Use Cases:</strong> Local Deployments & Orchestration</p>
        <p>Through our Homelab CLI, we provision deterministic K3s clusters on macOS via Lima VZ.</p>
      </div>

      <div class="card">
        <h3>🐳 Docker</h3>
        <p><strong>Use Cases:</strong> Application Packaging, Testing</p>
        <p>Extensively used by DevX to enforce pure container-based compilation and local test environments.</p>
      </div>
    </div>
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    <h2>🤖 AI Integration Layers</h2>
    <p class="mb-2">Tools bridging human commands to AI workflows:</p>
    
    <div class="cards-grid">
      <div class="card">
        <h3>🦾 Agentic Interfaces</h3>
        <p><strong>Use Cases:</strong> Telegram bots, macOS Menu Bar</p>
        <p>NexusAgent powers robust interactions by connecting directly with local CLI tools, passing commands through WebSocket gates.</p>
      </div>
    </div>
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    <h2>🎯 Development Philosophy</h2>
    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem;">
      <div style="padding: 2rem; background: var(--card-bg); border-radius: var(--border-radius-md); border-left: 4px solid var(--primary-accent); backdrop-filter: blur(8px);">
        <h4 style="color: var(--primary-accent); margin-bottom: 1rem;">🚀 Performance First</h4>
        <p>We prioritize performance and efficiency in all our tools and applications, ensuring they scale from development to production.</p>
      </div>
      
      <div style="padding: 2rem; background: var(--card-bg); border-radius: var(--border-radius-md); border-left: 4px solid var(--primary-text); backdrop-filter: blur(8px);">
        <h4 style="color: var(--primary-text); margin-bottom: 1rem;">🔧 Developer Experience</h4>
        <p>Tools should be intuitive and powerful. We focus on creating excellent developer experiences with comprehensive documentation.</p>
      </div>
      
      <div style="padding: 2rem; background: var(--card-bg); border-radius: var(--border-radius-md); border-left: 4px solid var(--border-hover); backdrop-filter: blur(8px);">
        <h4 style="color: var(--border-hover); margin-bottom: 1rem;">🌍 Open Source</h4>
        <p>Everything we build is open source, fostering collaboration and transparency in the development community.</p>
      </div>
    </div>
  </div>
</div>

<div class="content-section text-center">
  <div class="wrapper">
    <h2>🔮 Future Technologies</h2>
    <p class="mb-2">Technologies we're exploring for future projects:</p>
    
    <div style="display: flex; gap: 1rem; justify-content: center; flex-wrap: wrap; margin: 2rem 0;">
      <span style="background: var(--card-bg); border: 1px solid var(--border-color); color: var(--primary-text); padding: 0.5rem 1rem; border-radius: var(--border-radius-md); font-weight: 500;">WebAssembly</span>
      <span style="background: var(--card-bg); border: 1px solid var(--border-color); color: var(--primary-text); padding: 0.5rem 1rem; border-radius: var(--border-radius-md); font-weight: 500;">Rust</span>
      <span style="background: var(--card-bg); border: 1px solid var(--border-color); color: var(--primary-text); padding: 0.5rem 1rem; border-radius: var(--border-radius-md); font-weight: 500;">Local LLMs</span>
    </div>
    
    <p style="margin-top: 2rem;">
      <a href="/projects/" class="button btn-accent">See Our Projects</a>
    </p>
  </div>
</div>
