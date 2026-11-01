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
  let activeLocKey = 'sajek';
  let activeDays = 3;

  // 2. Navbar Scroll Style & Sticky CTA
  const nav = document.querySelector('nav');
  const stickyCta = document.getElementById('sticky-cta');
  
  window.addEventListener('scroll', () => {
    if (nav) {
      if (window.scrollY > 40) {
        nav.classList.add('scrolled');
      } else {
        nav.classList.remove('scrolled');
      }
    }
    
    if (stickyCta) {
      if (window.scrollY > window.innerHeight * 0.7) {
        stickyCta.classList.add('visible');
      } else {
        stickyCta.classList.remove('visible');
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

  // Helper: Convert English numbers to Bengali numerals
  function toBengaliNumbers(numStr) {
    const enDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    let result = numStr.toString();
    for (let i = 0; i < 10; i++) {
      result = result.replaceAll(enDigits[i], bnDigits[i]);
    }
    return result;
  }

  // 4. Interactive Map & Budget Data
  const mapData = {
    sajek: {
      en: {
        name: "Sajek Valley",
        div: "Rangamati, Chattogram",
        insights: [
          "<strong>Offline Vault:</strong> Offline-first vector maps are 100% available without internet coverage.",
          "<strong>Best Stay:</strong> Chander Gari transport combined with local cottages offers best value.",
          "<strong>Network:</strong> Teletalk and Robi provide limited 3G signal; GPS is active."
        ],
        sos: "<i class=\"fa-solid fa-circle-check\"></i> High Coverage (Army Help Desk)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> Offline Verified",
        budgetRateMin: 1500,
        budgetRateMax: 2000,
        reliability: "96%",
        budgetLabel: "Estimated Budget",
        reliabilityLabel: "Reliability Index",
        insightsHeader: "Key Insights",
        sosLabel: "SOS Rescue Hub Coverage:"
      },
      bn: {
        name: "সাজেক ভ্যালি",
        div: "রাঙ্গামাটি, চট্টগ্রাম",
        insights: [
          "<strong>অফলাইন ভল্ট:</strong> ইন্টারনেট সংযোগ ছাড়াও ১০০% অফলাইন ভেক্টর ম্যাপ উপলব্ধ থাকবে।",
          "<strong>থাকার সুবিধা:</strong> চাঁদের গাড়ি এবং স্থানীয় কটেজের প্যাকেজে সেরা ডিল পাওয়া যায়।",
          "<strong>নেটওয়ার্ক:</strong> টেলিটক এবং রবিতে সীমিত ৩জি সিগন্যাল; জিপিএস সম্পূর্ণ সচল।"
        ],
        sos: "<i class=\"fa-solid fa-circle-check\"></i> হাই কভারেজ (সেনাবাহিনী হেল্প ডেস্ক)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> অফলাইন ভেরিফাইড",
        budgetRateMin: 1500,
        budgetRateMax: 2000,
        reliability: "৯৬%",
        budgetLabel: "আনুমানিক বাজেট",
        reliabilityLabel: "নির্ভরযোগ্যতা সূচক",
        insightsHeader: "মূল তথ্যসমূহ",
        sosLabel: "SOS উদ্ধার কেন্দ্র কভারেজ:"
      }
    },
    sundarbans: {
      en: {
        name: "Sundarbans Eco Tour",
        div: "Bagerhat/Khulna, Khulna",
        insights: [
          "<strong>Offline Vault:</strong> Offline vector maps cover all waterways and forest paths.",
          "<strong>Permission:</strong> Ship/boat operators handle the forest department entry permits.",
          "<strong>Network:</strong> Signal is completely dead deep in the forest; GPS tracking is active."
        ],
        sos: "<i class=\"fa-solid fa-circle-exclamation\" style=\"color:#f59e0b;\"></i> Medium Coverage (Forest Guard SOS)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> Offline Verified",
        budgetRateMin: 2500,
        budgetRateMax: 4000,
        reliability: "92%",
        budgetLabel: "Estimated Budget",
        reliabilityLabel: "Reliability Index",
        insightsHeader: "Key Insights",
        sosLabel: "SOS Rescue Hub Coverage:"
      },
      bn: {
        name: "সুন্দরবন ইকো ট্যুর",
        div: "বাগেরহাট/খুলনা, খুলনা",
        insights: [
          "<strong>অফলাইন ভল্ট:</strong> অফলাইন ভেক্টর ম্যাপে নদীপথ ও বনের গভীরের পথ অন্তর্ভুক্ত আছে।",
          "<strong>অনুমতি:</strong> লঞ্চ/বোট অপারেটররাই বন বিভাগের প্রবেশের অনুমতি ও ফি ম্যানেজ করে।",
          "<strong>নেটওয়ার্ক:</strong> বনের গভীরে নেটওয়ার্ক সম্পূর্ণ অনুপস্থিত; অফলাইন জিপিএস চালু থাকবে।"
        ],
        sos: "<i class=\"fa-solid fa-circle-exclamation\" style=\"color:#f59e0b;\"></i> মিডিয়াম কাভারেজ (বনরক্ষী উদ্ধার কেন্দ্র)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> অফলাইন ভেরিফাইড",
        budgetRateMin: 2500,
        budgetRateMax: 4000,
        reliability: "৯২%",
        budgetLabel: "আনুমানিক বাজেট",
        reliabilityLabel: "নির্ভরযোগ্যতা সূচক",
        insightsHeader: "মূল তথ্যসমূহ",
        sosLabel: "SOS উদ্ধার কেন্দ্র কভারেজ:"
      }
    },
    sreemangal: {
      en: {
        name: "Sreemangal",
        div: "Moulvibazar, Sylhet",
        insights: [
          "<strong>Offline Vault:</strong> Tea estate trails and Lawachara reserve paths are fully offline cached.",
          "<strong>Transport:</strong> Renting a local CNG driver for the day is highly recommended.",
          "<strong>Network:</strong> Grameenphone and Banglalink have strong 4G coverage everywhere."
        ],
        sos: "<i class=\"fa-solid fa-circle-check\"></i> High Coverage (Local Tourist Police)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> Offline Verified",
        budgetRateMin: 1000,
        budgetRateMax: 1500,
        reliability: "98%",
        budgetLabel: "Estimated Budget",
        reliabilityLabel: "Reliability Index",
        insightsHeader: "Key Insights",
        sosLabel: "SOS Rescue Hub Coverage:"
      },
      bn: {
        name: "শ্রীমঙ্গল",
        div: "মৌলভীবাজার, সিলেট",
        insights: [
          "<strong>অফলাইন ভল্ট:</strong> চা বাগান ও লাউয়াছড়া জাতীয় উদ্যানের অফলাইন ট্রেইল ডাউনলোডযোগ্য।",
          "<strong>যাতায়াত:</strong> সারাদিনের জন্য স্থানীয় সিএনজি ভাড়া করাই সবচেয়ে সাশ্রয়ী মাধ্যম।",
          "<strong>নেটওয়ার্ক:</strong> গ্রামীণফোন ও বাংলালিংকের শক্তিশালী ৪জি কভারেজ প্রায় সর্বত্র রয়েছে।"
        ],
        sos: "<i class=\"fa-solid fa-circle-check\"></i> হাই কভারেজ (ট্যুরিস্ট পুলিশ টিম)",
        badge: "<i class=\"fa-solid fa-shield-halved\"></i> অফলাইন ভেরিফাইড",
        budgetRateMin: 1000,
        budgetRateMax: 1500,
        reliability: "৯৮%",
        budgetLabel: "আনুমানিক বাজেট",
        reliabilityLabel: "নির্ভরযোগ্যতা সূচক",
        insightsHeader: "মূল তথ্যসমূহ",
        sosLabel: "SOS উদ্ধার কেন্দ্র কভারেজ:"
      }
    }
  };

  function updateDetailsCard() {
    const detailsWrap = document.getElementById('demo-details-content');
    if (!detailsWrap) return;
    
    // Smooth transition fade-out
    detailsWrap.classList.add('details-fade-out');
    
    setTimeout(() => {
      const data = mapData[activeLocKey][currentLang];
      
      // Calculate dynamic budget based on day slider
      const minBudget = data.budgetRateMin * activeDays;
      const maxBudget = data.budgetRateMax * activeDays;
      let budgetText = '';
      
      const sliderDaysEl = document.getElementById('slider-days');
      const sliderLabelEl = document.getElementById('slider-label');
      
      if (currentLang === 'en') {
        budgetText = `৳${minBudget.toLocaleString()} - ৳${maxBudget.toLocaleString()}`;
        if (sliderDaysEl) sliderDaysEl.innerText = `${activeDays} Day${activeDays > 1 ? 's' : ''}`;
        if (sliderLabelEl) sliderLabelEl.innerText = 'Trip Duration';
      } else {
        budgetText = `৳${toBengaliNumbers(minBudget.toLocaleString())} - ৳${toBengaliNumbers(maxBudget.toLocaleString())}`;
        if (sliderDaysEl) sliderDaysEl.innerText = `${toBengaliNumbers(activeDays)} দিন`;
        if (sliderLabelEl) sliderLabelEl.innerText = 'ভ্রমণকাল';
      }
      
      const locNameEl = document.getElementById('loc-name');
      const locDivEl = document.getElementById('loc-div');
      const locBudgetEl = document.getElementById('loc-budget');
      const locRelEl = document.getElementById('loc-reliability');
      const locSosEl = document.getElementById('loc-sos');
      const locBadgeEl = document.getElementById('loc-badge');
      
      if (locNameEl) locNameEl.innerText = data.name;
      if (locDivEl) locDivEl.innerText = data.div;
      if (locBudgetEl) locBudgetEl.innerText = budgetText;
      if (locRelEl) locRelEl.innerText = data.reliability;
      if (locSosEl) locSosEl.innerHTML = data.sos;
      if (locBadgeEl) locBadgeEl.innerHTML = data.badge;
      
      // Labels translations
      const budgetLbl = document.getElementById('loc-budget-label');
      const relLbl = document.getElementById('loc-reliability-label');
      const insightsHdr = document.getElementById('loc-insights-header');
      const sosLbl = document.getElementById('loc-sos-label');
      
      if (budgetLbl) budgetLbl.innerText = data.budgetLabel;
      if (relLbl) relLbl.innerText = data.reliabilityLabel;
      if (insightsHdr) insightsHdr.innerText = data.insightsHeader;
      if (sosLbl) sosLbl.innerText = data.sosLabel;
      
      // Insights list
      const list = document.getElementById('loc-insights');
      if (list) {
        list.innerHTML = '';
        data.insights.forEach(ins => {
          const li = document.createElement('li');
          li.innerHTML = ins;
          list.appendChild(li);
        });
      }
      
      detailsWrap.classList.remove('details-fade-out');
    }, 120);
  }

  // Hotspots Click Handlers
  const hotspots = document.querySelectorAll('.map-hotspot');
  hotspots.forEach(btn => {
    btn.addEventListener('click', () => {
      hotspots.forEach(h => h.classList.remove('active'));
      btn.classList.add('active');
      activeLocKey = btn.getAttribute('data-loc');
      updateDetailsCard();
    });
  });

  // Slider Input Handler
  const daySlider = document.getElementById('day-slider');
  if (daySlider) {
    daySlider.addEventListener('input', (e) => {
      activeDays = parseInt(e.target.value);
      updateDetailsCard();
    });
  }

  // 5. Language Toggle Logic
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

      // Refresh dynamic components
      updateDetailsCard();
    });
  }

  // 6. FAQ Accordion Click Handler
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

  // 7. Image Lightbox Overlay
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightbox-img');
  const lightboxClose = document.querySelector('.lightbox-close');
  const lightboxPrev = document.querySelector('.lightbox-prev');
  const lightboxNext = document.querySelector('.lightbox-next');

  const lightboxTriggers = document.querySelectorAll('.lightbox-trigger');
  const lightboxSources = Array.from(lightboxTriggers).map(el => el.getAttribute('data-src'));
  let currentLightboxIndex = 0;

  function openLightbox(index) {
    if (lightboxSources.length === 0 || !lightboxImg || !lightbox) return;
    currentLightboxIndex = index;
    lightboxImg.src = lightboxSources[index];
    lightbox.classList.add('active');
    document.body.style.overflow = 'hidden';
    
    if (lightboxPrev) lightboxPrev.style.display = lightboxSources.length > 1 ? 'flex' : 'none';
    if (lightboxNext) lightboxNext.style.display = lightboxSources.length > 1 ? 'flex' : 'none';
  }

  function closeLightbox() {
    if (!lightbox) return;
    lightbox.classList.remove('active');
    document.body.style.overflow = '';
    if (lightboxImg) setTimeout(() => { lightboxImg.src = ''; }, 300);
  }

  function swapLightboxImage(index) {
    if (!lightboxImg || lightboxSources.length === 0) return;
    lightboxImg.style.opacity = '0';
    lightboxImg.style.transform = 'scale(0.95)';
    setTimeout(() => {
      currentLightboxIndex = (index + lightboxSources.length) % lightboxSources.length;
      lightboxImg.src = lightboxSources[currentLightboxIndex];
      lightboxImg.style.opacity = '1';
      lightboxImg.style.transform = 'scale(1)';
    }, 150);
  }

  if (lightboxImg) {
    lightboxImg.style.transition = 'opacity 0.15s ease, transform 0.3s cubic-bezier(0.16, 1, 0.3, 1)';
  }

  lightboxTriggers.forEach((el, i) => {
    el.addEventListener('click', () => openLightbox(i));
  });

  if (lightboxClose) lightboxClose.addEventListener('click', closeLightbox);
  if (lightboxPrev) lightboxPrev.addEventListener('click', () => swapLightboxImage(currentLightboxIndex - 1));
  if (lightboxNext) lightboxNext.addEventListener('click', () => swapLightboxImage(currentLightboxIndex + 1));

  if (lightbox) {
    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox || e.target.classList.contains('lightbox-img-wrap')) {
        closeLightbox();
      }
    });
  }

  document.addEventListener('keydown', (e) => {
    if (!lightbox || !lightbox.classList.contains('active')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') swapLightboxImage(currentLightboxIndex - 1);
    if (e.key === 'ArrowRight') swapLightboxImage(currentLightboxIndex + 1);
  });

  // 8. Cookie Consent Banner
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

  // Initialize display details
  updateDetailsCard();
});
