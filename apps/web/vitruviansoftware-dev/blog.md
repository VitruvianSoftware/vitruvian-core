---
layout: page
title: Blog
permalink: /blog/
---

<!-- Split Hero Section -->
<div class="split-hero">
  <div class="hero-content">
    <span class="tag">Engineering Log</span>
    <h1>Our Blog</h1>
    <p>Insights, tutorials, and updates from the Vitruvian Software team on agentic tooling, Platform architecture, and open-source development.</p>
  </div>
  <div class="hero-visual">
    <img src="/images/blog_hero.png" alt="Code Ledger Data Stream Graphic">
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    {%- if site.posts.size > 0 -%}
      <div class="post-list">
        {%- for post in site.posts -%}
        <article class="card" style="margin-bottom: 2rem;">
          <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 1rem;">
            <div>
              {%- assign date_format = site.minima.date_format | default: "%b %-d, %Y" -%}
              <span class="post-meta" style="color: var(--secondary-text); font-size: 0.9rem;">{{ post.date | date: date_format }}</span>
              <div style="margin-top: 0.5rem;">
                {%- if post.categories.size > 0 -%}
                  {%- for category in post.categories -%}
                    <span style="background: var(--card-hover-bg); border: 1px solid var(--border-color); color: var(--primary-text); padding: 0.2rem 0.6rem; border-radius: var(--border-radius-sm); font-size: 0.8rem; margin-right: 0.5rem;">{{ category }}</span>
                  {%- endfor -%}
                {%- endif -%}
              </div>
            </div>
          </div>
          
          <h2 style="margin-bottom: 1rem;">
            <a href="{{ post.url | relative_url }}" style="text-decoration: none; color: var(--primary-text); border-bottom: none;">
              {{ post.title | escape }}
            </a>
          </h2>
          
          {%- if post.excerpt -%}
            <p style="color: var(--secondary-text); margin-bottom: 1.5rem;">{{ post.excerpt | markdownify | strip_html | truncate: 200 }}</p>
          {%- endif -%}
          
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <a href="{{ post.url | relative_url }}" class="button">Read More</a>
            {%- if post.author -%}
              <span style="color: var(--secondary-text); font-size: 0.9rem;">by {{ post.author }}</span>
            {%- endif -%}
          </div>
        </article>
        {%- endfor -%}
      </div>
    {%- else -%}
      <div class="text-center" style="padding: 4rem 0;">
        <div style="max-width: 600px; margin: 0 auto;">
          <div style="background: var(--card-bg); padding: 3rem 2rem; border-radius: var(--border-radius-md); border: 1px solid var(--border-color); backdrop-filter: blur(8px);">
            <h2 style="color: var(--primary-accent); margin-bottom: 1.5rem;">📝 No Posts Yet</h2>
            <p style="font-size: 1.1rem; margin-bottom: 2rem;">We're preparing exciting content about our latest projects and development insights.</p>
          </div>
        </div>
      </div>
    {%- endif -%}
  </div>
</div>

<div class="content-section">
  <div class="wrapper">
    <h2 class="text-center">What to Expect from Our Blog</h2>
    
    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem; margin: 2rem 0;">
      <div class="card">
        <h3>🤖 Agentic Development</h3>
        <p>Deep dives into AI agent development and our operational NexusAgent macOS integration.</p>
      </div>
      
      <div class="card">
        <h3>⚙️ Platform Insights</h3>
        <p>Practical Platform tutorials, automation strategies with DevX, and reproducible build pipelines.</p>
      </div>
      
      <div class="card">
        <h3>📊 Version Updates</h3>
        <p>Behind-the-scenes looks at our tools, release notes via GoReleaser, and architecture decisions.</p>
      </div>
    </div>
  </div>
</div>

<div class="content-section text-center">
  <div class="wrapper">
    <h2>Stay Updated</h2>
    <p class="mb-2">Get notified when we publish new insights:</p>
    
    <div style="background: var(--card-bg); padding: 2rem; border-radius: var(--border-radius-md); border: 1px solid var(--border-color); max-width: 500px; margin: 2rem auto; backdrop-filter: blur(8px);">
      <h4 style="margin-bottom: 1rem; color: var(--primary-text);">📢 Subscribe for Updates</h4>
      <p style="margin-bottom: 1.5rem; font-size: 0.95rem; color: var(--secondary-text);">Follow us on GitHub to catch automated release announcements.</p>
      <div style="display: flex; gap: 1rem; justify-content: center; flex-wrap: wrap;">
        <a href="https://github.com/VitruvianSoftware" class="button btn-accent">Watch on GitHub</a>
      </div>
    </div>
  </div>
</div>
