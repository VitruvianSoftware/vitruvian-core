// Modern JavaScript for Vitruvian Software site
document.addEventListener('DOMContentLoaded', function() {
  
  // Add smooth scrolling to all anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });

  // Intersection Observer for fade-in animations
  const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.style.opacity = '1';
        entry.target.style.transform = 'translateY(0)';
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  // Apply fade-in animation to cards and sections
  document.querySelectorAll('.card, .fade-in-up').forEach(el => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(30px)';
    el.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
    observer.observe(el);
  });

  // Add parallax effect to hero background
  const hero = document.querySelector('.hero');
  if (hero) {
    window.addEventListener('scroll', () => {
      const scrolled = window.pageYOffset;
      const rate = scrolled * -0.5;
      hero.style.transform = `translateY(${rate}px)`;
    });
  }

  // Enhanced button hover effects
  document.querySelectorAll('.button').forEach(button => {
    button.addEventListener('mouseenter', function() {
      this.style.transform = 'translateY(-2px) scale(1.02)';
    });
    
    button.addEventListener('mouseleave', function() {
      this.style.transform = 'translateY(0) scale(1)';
    });
  });

  // Add typing effect to hero title (if present)
  const heroTitle = document.querySelector('.hero h1');
  if (heroTitle && heroTitle.textContent.includes('Vitruvian Software')) {
    const text = heroTitle.textContent;
    heroTitle.textContent = '';
    let i = 0;
    
    const typeWriter = () => {
      if (i < text.length) {
        heroTitle.textContent += text.charAt(i);
        i++;
        setTimeout(typeWriter, 50);
      }
    };
    
    // Start typing effect after a short delay
    setTimeout(typeWriter, 500);
  }

  // Add ripple effect to buttons
  document.querySelectorAll('.button').forEach(button => {
    button.addEventListener('click', function(e) {
      const ripple = document.createElement('span');
      const rect = this.getBoundingClientRect();
      const size = Math.max(rect.width, rect.height);
      const x = e.clientX - rect.left - size / 2;
      const y = e.clientY - rect.top - size / 2;
      
      ripple.style.cssText = `
        position: absolute;
        width: ${size}px;
        height: ${size}px;
        left: ${x}px;
        top: ${y}px;
        background: rgba(255, 255, 255, 0.3);
        border-radius: 50%;
        transform: scale(0);
        animation: ripple 0.6s linear;
        pointer-events: none;
      `;
      
      this.appendChild(ripple);
      
      setTimeout(() => {
        ripple.remove();
      }, 600);
    });
  });

  // Add CSS for ripple animation
  const style = document.createElement('style');
  style.textContent = `
    @keyframes ripple {
      to {
        transform: scale(4);
        opacity: 0;
      }
    }
    
    .button {
      position: relative;
      overflow: hidden;
    }
    
    /* Progressive enhancement for reduced motion preference */
    @media (prefers-reduced-motion: reduce) {
      * {
        transition: none !important;
        animation: none !important;
      }
    }
  `;
  document.head.appendChild(style);

  // Add scroll indicator for long pages
  const scrollIndicator = document.createElement('div');
  scrollIndicator.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    width: 0%;
    height: 3px;
    background: var(--primary-accent);
    z-index: 999;
    transition: width 0.1s ease;
  `;
  document.body.appendChild(scrollIndicator);

  window.addEventListener('scroll', () => {
    const scrollPercent = (window.scrollY / (document.body.scrollHeight - window.innerHeight)) * 100;
    scrollIndicator.style.width = `${scrollPercent}%`;
  });

  // Add back to top button
  const backToTop = document.createElement('button');
  backToTop.innerHTML = '↑';
  backToTop.setAttribute('aria-label', 'Back to top');
  backToTop.style.cssText = `
    position: fixed;
    bottom: 20px;
    right: 20px;
    width: 50px;
    height: 50px;
    border-radius: 50%;
    border: none;
    background: var(--primary-accent);
    color: white;
    font-size: 20px;
    cursor: pointer;
    transition: all 0.3s ease;
    opacity: 0;
    transform: translateY(20px);
    z-index: 100;
  `;
  
  backToTop.addEventListener('click', () => {
    window.scrollTo({
      top: 0,
      behavior: 'smooth'
    });
  });

  window.addEventListener('scroll', () => {
    if (window.scrollY > 300) {
      backToTop.style.opacity = '1';
      backToTop.style.transform = 'translateY(0)';
    } else {
      backToTop.style.opacity = '0';
      backToTop.style.transform = 'translateY(20px)';
    }
  });

  document.body.appendChild(backToTop);

  // Add loading animation for images
  document.querySelectorAll('img').forEach(img => {
    if (!img.complete) {
      img.style.opacity = '0';
      img.style.transition = 'opacity 0.3s ease';
      
      img.addEventListener('load', () => {
        img.style.opacity = '1';
      });
    }
  });

  // Console easter egg
  console.log(`
    🚀 Vitruvian Software Open Source
    ================================
    
    Welcome to our website! 
    
    Built with:
    • Jekyll & GitHub Pages
    • Modern CSS Grid & Flexbox
    • Vanilla JavaScript
    • Love for open source ❤️
    
    Check out our projects: https://github.com/VitruvianSoftware
    
    Interested in contributing? We'd love to have you!
  `);
}); 