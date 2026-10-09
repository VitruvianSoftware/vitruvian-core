document.addEventListener("DOMContentLoaded", () => {
    const canvas = document.createElement('canvas');
    canvas.id = 'bg-canvas';
    document.body.prepend(canvas);
    
    const ctx = canvas.getContext('2d');
    let width, height;
    
    const particles = [];
    // Adjust density based on screen size
    const calculateParticleCount = () => Math.min(Math.floor(window.innerWidth * window.innerHeight / 15000), 100);
    let particleCount = 80;
    const connectionDistance = 150;
    
    function resize() {
        width = window.innerWidth;
        height = window.innerHeight;
        canvas.width = width;
        canvas.height = height;
        particleCount = calculateParticleCount();
        
        // Adjust particle array size
        while(particles.length < particleCount) {
            particles.push(new Particle());
        }
        if(particles.length > particleCount) {
            particles.length = particleCount;
        }
    }
    
    window.addEventListener('resize', resize);
    
    class Particle {
        constructor() {
            this.x = Math.random() * (window.innerWidth || 1000);
            this.y = Math.random() * (window.innerHeight || 800);
            this.vx = (Math.random() - 0.5) * 0.25;
            this.vy = (Math.random() - 0.5) * 0.25;
            this.radius = Math.random() * 1.2 + 0.5;
        }
        
        update() {
            this.x += this.vx;
            this.y += this.vy;
            
            if (this.x < 0 || this.x > width) this.vx *= -1;
            if (this.y < 0 || this.y > height) this.vy *= -1;
        }
        
        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
            ctx.fillStyle = 'rgba(255, 255, 255, 0.12)';
            ctx.fill();
        }
    }
    
    resize();
    
    function animate() {
        ctx.clearRect(0, 0, width, height);
        
        particles.forEach(p => p.update());
        
        for (let i = 0; i < particles.length; i++) {
            for (let j = i + 1; j < particles.length; j++) {
                const dx = particles[i].x - particles[j].x;
                const dy = particles[i].y - particles[j].y;
                const distance = Math.sqrt(dx * dx + dy * dy);
                
                if (distance < connectionDistance) {
                    ctx.beginPath();
                    ctx.moveTo(particles[i].x, particles[i].y);
                    ctx.lineTo(particles[j].x, particles[j].y);
                    const alpha = 0.08 * (1 - distance / connectionDistance);
                    ctx.strokeStyle = `rgba(255, 255, 255, ${alpha})`;
                    ctx.lineWidth = 0.6;
                    ctx.stroke();
                }
            }
        }
        
        particles.forEach(p => p.draw());
        requestAnimationFrame(animate);
    }
    
    animate();
});
