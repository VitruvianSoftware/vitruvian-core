---
layout: default
---

<!-- Split Hero Section -->
<div class="split-hero">
  <div class="hero-content">
    <span class="tag">Engineering Frameworks</span>
    <h1>Architecting Platform Infrastructure</h1>
    <p>High-performance local cloud tooling, reproducible environments, and deterministic agentic systems mapped straight to macOS. No vibe-coding. Just operations.</p>
    
    <div style="display: flex; gap: 1rem; margin-top: 2rem;">
      <a href="/projects/" class="button btn-accent">Explore Ecosystem</a>
      <a href="https://github.com/VitruvianSoftware" class="button">GitHub Source</a>
    </div>
  </div>
  
  <div class="hero-visual">
    <img src="/images/brutalist-terminal.png" alt="Abstract brutalist terminal UI">
  </div>
</div>

<!-- Bento Grid Frameworks Section -->
<div class="wrapper">
  <div class="bento-section">
    <div style="display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 3rem;">
      <div>
        <span class="tag">CORE PROJECTS</span>
        <h2 style="margin-bottom: 0; border: none;">Operation Matrix</h2>
      </div>
      <a href="/projects/" class="button">View All Projects</a>
    </div>

    <div class="bento-grid">
      
      <!-- NexusAgent (Massive Focus Block) -->
      <div class="bento-cell bento-large dark">
        <div class="bento-image-wrapper">
          <img src="/images/architectural-network.png" alt="Network Grid Diagram">
        </div>
        <div class="bento-content">
          <span class="tag">Flagship</span>
          <h3 class="text-accent">NexusAgent</h3>
          <p style="color: #e0e0e0 !important; max-width: 80%;">
            A highly-integrated, local-first macOS assistant running natively in your menu bar. 
            Connects securely via remote WebSocket gateways to execute infrastructure deployments and terminal commands without hallucinations.
          </p>
          <div class="mt-2">
            <a href="https://github.com/VitruvianSoftware/nexus-agent" class="button btn-accent">Explore Project</a>
          </div>
        </div>
        <div class="bento-number">01</div>
      </div>

      <!-- DevX CLI -->
      <div class="bento-cell bento-square">
        <div class="bento-content">
          <span class="tag">CLI Tooling</span>
          <h3>DevX Protocol</h3>
          <p>
            Standardize your repository initialization. Eradicate configuration drift across teams through docker-tethered sandboxes and rigorous git-flow hooks.
          </p>
          <div class="mt-2">
            <a href="https://github.com/VitruvianSoftware/devx" class="button">Explore Project</a>
          </div>
        </div>
        <div class="bento-number">02</div>
      </div>

      <!-- Homelab K3s -->
      <div class="bento-cell bento-square dark">
        <div class="bento-content">
          <span class="tag">Infrastructure</span>
          <h3>Homelab</h3>
          <p>
            Automated provisioning protocol for multi-node Kubernetes (K3s) edge clusters over bare metal via Lima VZ. Deterministic container orchestration locally.
          </p>
          <div style="margin-top: clamp(2rem, 10vh, 5rem);">
            <a href="https://github.com/VitruvianSoftware/homelab" class="button">Explore Project</a>
          </div>
        </div>
      </div>

      <!-- Open Source Metrics -->
      <div class="bento-cell bento-square">
        <div class="bento-content" style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem;">
          <div>
            <h4 class="text-accent" style="font-size: 2.5rem !important;">100%</h4>
            <p>Open Source Pipelines</p>
          </div>
          <div>
            <h4 class="text-accent" style="font-size: 2.5rem !important;">macOS</h4>
            <p>Primary Compilation Target</p>
          </div>
        </div>
      </div>

      <!-- Homebrew Tap -->
      <div class="bento-cell bento-square dark" style="display: flex; flex-direction: column; justify-content: flex-start; gap: 1rem;">
        <div>
          <span class="tag">Distribution</span>
          <h3>Homebrew Central Tap</h3>
          <p>We maintain a stringent release automation protocol using GoReleaser to ship verified binaries instantly. Zero manual releases. Zero unauthorized patches.</p>
        </div>
        <div style="margin-top: auto;">
          <pre style="margin: 0;"><code>$ brew tap vi.../tap
$ brew install devx
$ brew install homelab</code></pre>
        </div>
      </div>

    </div>
  </div>
</div>
