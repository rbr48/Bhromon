// ==========================================================================
// BHROMON LANDING PAGE JAVASCRIPT
// ==========================================================================

// 1. Particle Canvas (Subtle Floating Stars/Dust)
(function initParticles() {
  const canvas = document.getElementById('particles-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let particles = [];
  
  function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  // Generate particles
  const count = Math.min(Math.floor(window.innerWidth / 25), 60);
  for (let i = 0; i < count; i++) {
    particles.push({
      x: Math.random() * window.innerWidth,
      y: Math.random() * window.innerHeight,
      r: Math.random() * 1.5 + 0.4,
      dx: (Math.random() - 0.5) * 0.15,
      dy: (Math.random() - 0.5) * 0.15,
      alpha: Math.random() * 0.3 + 0.05,
    });
  }

  function animate() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    particles.forEach(p => {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(16, 185, 129, ${p.alpha})`; // Emerald Green Dust
      ctx.fill();
      
      // Move
      p.x += p.dx;
      p.y += p.dy;
      
      // Boundary check
      if (p.x < 0) p.x = canvas.width;
      if (p.x > canvas.width) p.x = 0;
      if (p.y < 0) p.y = canvas.height;
      if (p.y > canvas.height) p.y = 0;
    });
    requestAnimationFrame(animate);
  }
  animate();
})();

document.addEventListener('DOMContentLoaded', () => {
  // Global State
  let currentLang = 'en';

  // 2. Navbar Scroll Style
  const nav = document.querySelector('nav');
  window.addEventListener('scroll', () => {
    if (nav) {
      if (window.scrollY > 40) {
        nav.classList.add('scrolled');
      } else {
        nav.classList.remove('scrolled');
      }
    }
  });

  // 3. Scroll Fade-in Animations
  const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.08
  };

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        obs.unobserve(entry.target);
      }
    });
  }, observerOptions);

  document.querySelectorAll('.fade-in-up').forEach(el => observer.observe(el));

  // 4. Language Toggle Logic
  const langToggleBtn = document.getElementById('lang-toggle');
  if (langToggleBtn) {
    langToggleBtn.addEventListener('click', () => {
      currentLang = currentLang === 'en' ? 'bn' : 'en';
      langToggleBtn.innerText = currentLang === 'en' ? 'বাং' : 'EN';
      
      // Update all elements with static translations
      document.querySelectorAll('.lang-text').forEach(el => {
        const text = el.getAttribute(`data-${currentLang}`);
        if (text) {
          el.innerHTML = text;
        }
      });
    });
  }

  // 5. FAQ Accordion Click Handler
  const faqQuestions = document.querySelectorAll('.faq-question');
  faqQuestions.forEach(question => {
    question.addEventListener('click', () => {
      const parent = question.parentElement;
      const isActive = parent.classList.contains('active');
      
      document.querySelectorAll('.faq-item').forEach(item => {
        item.classList.remove('active');
      });

      if (!isActive) {
        parent.classList.add('active');
      }
    });
  });

  // 6. Cookie Consent Banner
  const cookieBanner = document.getElementById('cookie-banner');
  const acceptCookiesBtn = document.getElementById('accept-cookies-btn');
  
  if (cookieBanner && acceptCookiesBtn) {
    if (!localStorage.getItem('bhromon_cookies_accepted')) {
      setTimeout(() => {
        cookieBanner.classList.add('visible');
      }, 1500);
    }
    
    acceptCookiesBtn.addEventListener('click', () => {
      localStorage.setItem('bhromon_cookies_accepted', 'true');
      cookieBanner.classList.remove('visible');
    });
  }
});
