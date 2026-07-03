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
  const count = Math.min(Math.floor(window.innerWidth / 20), 80);
  for (let i = 0; i < count; i++) {
    particles.push({
      x: Math.random() * window.innerWidth,
      y: Math.random() * window.innerHeight,
      r: Math.random() * 1.5 + 0.4,
      dx: (Math.random() - 0.5) * 0.15,
      dy: (Math.random() - 0.5) * 0.15,
      alpha: Math.random() * 0.35 + 0.05,
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
  let activeTierKey = 'unverified';

  // 2. Navbar Scroll Style & Sticky CTA
  const nav = document.querySelector('nav');
  const stickyCta = document.getElementById('sticky-cta');
  
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      nav.classList.add('scrolled');
    } else {
      nav.classList.remove('scrolled');
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

  const observer = new IntersectionObserver((entries, observer) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, observerOptions);

  document.querySelectorAll('.fade-in-up').forEach(el => observer.observe(el));

  // 4. Stats Counter Animation
  const statNumbers = document.querySelectorAll('.floating-stat-num');
  const statsObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const target = entry.target;
        if (!target.hasAttribute('data-count')) return;
        const countTo = parseInt(target.getAttribute('data-count'));
        let count = 0;
        const duration = 1800; // 1.8 seconds
        const stepTime = 16;
        const increment = countTo / (duration / stepTime);
        
        const updateCount = () => {
          count += increment;
          if (count < countTo) {
            target.innerText = Math.ceil(count) + (target.getAttribute('data-suffix') || ' +');
            requestAnimationFrame(updateCount);
          } else {
            target.innerText = countTo + (target.getAttribute('data-suffix') || ' +');
          }
        };
        updateCount();
        statsObserver.unobserve(target);
      }
    });
  });

  statNumbers.forEach(stat => statsObserver.observe(stat));

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

  // 5. Interactive Map & Budget Data
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
      
      if (currentLang === 'en') {
        budgetText = `৳${minBudget.toLocaleString()} - ৳${maxBudget.toLocaleString()}`;
        document.getElementById('slider-days').innerText = `${activeDays} Day${activeDays > 1 ? 's' : ''}`;
        document.getElementById('slider-label').innerText = 'Trip Duration';
      } else {
        budgetText = `৳${toBengaliNumbers(minBudget.toLocaleString())} - ৳${toBengaliNumbers(maxBudget.toLocaleString())}`;
        document.getElementById('slider-days').innerText = `${toBengaliNumbers(activeDays)} দিন`;
        document.getElementById('slider-label').innerText = 'ভ্রমণকাল';
      }
      
      document.getElementById('loc-name').innerText = data.name;
      document.getElementById('loc-div').innerText = data.div;
      document.getElementById('loc-budget').innerText = budgetText;
      document.getElementById('loc-reliability').innerText = data.reliability;
      document.getElementById('loc-sos').innerHTML = data.sos;
      document.getElementById('loc-badge').innerHTML = data.badge;
      
      // Labels translations
      document.getElementById('loc-budget-label').innerText = data.budgetLabel;
      document.getElementById('loc-reliability-label').innerText = data.reliabilityLabel;
      document.getElementById('loc-insights-header').innerText = data.insightsHeader;
      document.getElementById('loc-sos-label').innerText = data.sosLabel;
      
      // Insights list
      const list = document.getElementById('loc-insights');
      list.innerHTML = '';
      data.insights.forEach(ins => {
        const li = document.createElement('li');
        li.innerHTML = ins;
        list.appendChild(li);
      });
      
      // Fade back in
      detailsWrap.classList.remove('details-fade-out');
    }, 150);
  }

  // Hotspot Click Handlers
  const hotspots = document.querySelectorAll('.map-hotspot');
  hotspots.forEach(spot => {
    spot.addEventListener('click', () => {
      hotspots.forEach(s => s.classList.remove('active'));
      spot.classList.add('active');
      activeLocKey = spot.getAttribute('data-loc');
      updateDetailsCard();
    });
  });

  // Days Slider Input Handler
  const daySlider = document.getElementById('day-slider');
  if (daySlider) {
    daySlider.addEventListener('input', (e) => {
      activeDays = parseInt(e.target.value);
      updateDetailsCard();
    });
  }

  // 6. Interactive Explorer Tiers Data
  const tierData = {
    unverified: {
      en: {
        badgeName: "Unverified",
        badgeIcon: "fa-user-xmark",
        badgeColor: "#64748b",
        reqXp: "0 XP Required",
        title: "Unverified Explorer",
        desc: "The default tier for all newly registered travelers. Users can read guides, but their contributions require community review before appearing on the directory.",
        benefitsTitle: "Capabilities & Restrictions",
        benefits: [
          "Read community TripLogs",
          "Save maps offline",
          "<span style='color:#ef4444;'>No direct verified posts</span>",
          "<span style='color:#ef4444;'>Decay protection inactive</span>"
        ]
      },
      bn: {
        badgeName: "আনভেরিফাইড",
        badgeIcon: "fa-user-xmark",
        badgeColor: "#64748b",
        reqXp: "০ এক্সপি (XP) প্রয়োজন",
        title: "আনভেরিফাইড এক্সপ্লোরার",
        desc: "সব নতুন নিবন্ধিত ভ্রমণকারীদের জন্য ডিফল্ট স্তর। ব্যবহারকারীরা গাইড পড়তে পারেন, তবে তাদের কন্টেন্ট পাবলিক ডিরেক্টরিতে দেখানোর আগে রিভিউ প্রয়োজন হয়।",
        benefitsTitle: "অনুমতি ও সীমাবদ্ধতা",
        benefits: [
          "কমিউনিটি ট্রিপলগ পড়তে পারবেন",
          "অফলাইন ম্যাপ সেভ করতে পারবেন",
          "<span style='color:#ef4444;'>ভেরিফাইড কন্টেন্ট পোস্ট করতে পারবেন না</span>",
          "<span style='color:#ef4444;'>ডিকে প্রোটেকশন নিষ্ক্রিয়</span>"
        ]
      }
    },
    explorer: {
      en: {
        badgeName: "Explorer",
        badgeIcon: "fa-shoe-prints",
        badgeColor: "#b45309", // Bronze
        reqXp: "50 XP Required",
        title: "Explorer Tier",
        desc: "Granted automatically after publishing 3 accepted posts, check-ins, or correct edits. You can post directly to the community feed.",
        benefitsTitle: "Capabilities",
        benefits: [
          "Write and publish TripLogs directly",
          "Upload vlogs and photo blocks",
          "Access public division group chats",
          "Earn trust scores on helpful votes"
        ]
      },
      bn: {
        badgeName: "এক্সপ্লোরার",
        badgeIcon: "fa-shoe-prints",
        badgeColor: "#b45309",
        reqXp: "৫০ এক্সপি (XP) প্রয়োজন",
        title: "এক্সপ্লোরার লেভেল",
        desc: "৩টি পোস্ট বা এডিট এপ্রুভ হওয়ার পর এই স্তর লাভ হয়। আপনি সরাসরি কমিউনিটি ফিডে পোস্ট করতে পারবেন।",
        benefitsTitle: "ফিচার অ্যাক্সেস",
        benefits: [
          "সরাসরি ট্রিপলগ পোস্ট করার সুবিধা",
          "ইউটিউব ভ্লগ ও ছবির ব্লক যুক্ত করা",
          "বিভাগীয় পাবলিক গ্রুপ চ্যাটে যোগ দেওয়া",
          "হেল্পফুল ভোট পেয়ে রেটিং বাড়ানো"
        ]
      }
    },
    trusted: {
      en: {
        badgeName: "Trusted",
        badgeIcon: "fa-user-check",
        badgeColor: "#475569", // Silver
        reqXp: "100 XP Required",
        title: "Trusted Explorer",
        desc: "Earned by keeping a 90%+ helpful ratio on your logs. Trusted explorers can write 'Pro-Tips' and benefit from longer decay grace periods on their guidelines.",
        benefitsTitle: "Trusted Capabilities",
        benefits: [
          "Publish verified Pro-Tips on map spots",
          "Double weight on helpful votes",
          "48-hour grace period before budget decay",
          "Verify and appeal pending local tags"
        ]
      },
      bn: {
        badgeName: "ট্রাস্টেড",
        badgeIcon: "fa-user-check",
        badgeColor: "#475569",
        reqXp: "১০০ এক্সপি (XP) প্রয়োজন",
        title: "ট্রাস্টেড এক্সপ্লোরার",
        desc: "আপনার কন্টেন্টে ৯০%+ হেল্পফুল ভোট থাকলে এই লেভেল অর্জিত হয়। ট্রাস্টেড ট্রাভেলাররা সরাসরি প্রোপোজালে প্রো-টিপস লিখতে পারেন এবং বাজেটে বড় ডিকে পিরিয়ড পান।",
        benefitsTitle: "বিশেষ সুবিধা সমূহ",
        benefits: [
          "ম্যাপ স্পটে ভেরিফাইড প্রো-টিপস রাইটিং",
          "আপনার ভোটে দ্বিগুণ ভোট কাউন্ট সুবিধা",
          "বাজেট ডিকে হওয়ার আগে ৪৮ ঘণ্টা গ্রেস টাইম",
          "পেন্ডিং লোকাল ট্যাগ ও তথ্য রিভিউ করা"
        ]
      }
    },
    pioneer: {
      en: {
        badgeName: "Pioneer",
        badgeIcon: "fa-award",
        badgeColor: "#d97706", // Gold
        reqXp: "200 XP Required",
        title: "Pioneer Explorer",
        desc: "The elite contributor tier. Pioneers are trusted to publish paid 'Premium Guides' in the marketplace, co-author logs, and access closed beta features.",
        benefitsTitle: "Elite Capabilities",
        benefits: [
          "Publish paid guides in Guide Marketplace",
          "Co-author collaborative TripLogs",
          "Invite up to 3 co-authors per guide",
          "Access offline vector map download packages"
        ]
      },
      bn: {
        badgeName: "পায়োনিয়ার",
        badgeIcon: "fa-award",
        badgeColor: "#d97706",
        reqXp: "২০০ এক্সপি (XP) প্রয়োজন",
        title: "পায়োনিয়ার এক্সপ্লোরার",
        desc: "এলিট কন্ট্রিবিউটর স্তর। পায়োনিয়াররা গাইড মার্কেটপ্লেসে পেইড প্রিমিয়াম গাইড বিক্রি করতে পারেন এবং যৌথভাবে ব্লগ রাইটিং করতে পারেন।",
        benefitsTitle: "এলিট সুবিধাসমূহ",
        benefits: [
          "গাইড মার্কেটপ্লেসে গাইড সেল সুবিধা",
          "কো-অথর হিসেবে ট্রিপলগ এডিট করা",
          "অন্য ট্রাভেলারদের গাইড রাইটিংয়ে ইনভাইট করা",
          "সম্পূর্ণ জেলার অফলাইন ভেক্টর প্যাকেজ ডাউনলোড"
        ]
      }
    },
    expert: {
      en: {
        badgeName: "Expert",
        badgeIcon: "fa-user-shield",
        badgeColor: "#10b981", // Emerald Green
        reqXp: "500 XP Required",
        title: "Regional Expert",
        desc: "The highest moderator status. Selected by regional councils. Experts review flagged content, approve business entries, and verify local tour guides.",
        benefitsTitle: "Moderator Power",
        benefits: [
          "Moderate regional logs and comments",
          "Approve local businesses & cottages",
          "Verify credentials of local tour guides",
          "Direct appeal processing on complaints"
        ]
      },
      bn: {
        badgeName: "রিজিয়ন এক্সপার্ট",
        badgeIcon: "fa-user-shield",
        badgeColor: "#10b981",
        reqXp: "৫০০ এক্সপি (XP) প্রয়োজন",
        title: "আঞ্চলিক এক্সপার্ট",
        desc: "সর্বোচ্চ মডারেটর স্তর। আঞ্চলিক কাউন্সিলের ভোটে মনোনীত হন। এক্সপার্টরা ফ্ল্যাগড কন্টেন্ট রিভিউ করেন এবং স্থানীয় গাইড ও হোটেল ভেরিফাই করেন।",
        benefitsTitle: "মডারেটরের ক্ষমতা",
        benefits: [
          "আঞ্চলিক ট্রিপলগ ও কমেন্ট ফিল্টারিং",
          "হোটেল ও লোকাল বিজনেসের ভেরিফিকেশন",
          "লোকাল ট্যুর গাইড ভেরিফাই করা",
          "সরাসরি অভিযোগের আপিল প্রসেস করা"
        ]
      }
    }
  };

  function updateTiersCard(tierKey) {
    activeTierKey = tierKey;
    const card = document.getElementById('tier-showcase-card');
    if (!card) return;
    
    // Smooth translation transition
    card.style.opacity = '0';
    card.style.transform = 'translateY(8px)';
    
    setTimeout(() => {
      const data = tierData[tierKey][currentLang];
      
      // Update badge
      const badge = document.getElementById('tier-badge');
      badge.style.color = data.badgeColor;
      badge.style.borderColor = data.badgeColor;
      badge.style.boxShadow = `0 10px 30px ${data.badgeColor}15`;
      
      const badgeIcon = document.getElementById('tier-badge-icon');
      badgeIcon.className = `fa-solid ${data.badgeIcon}`;
      
      document.getElementById('tier-badge-name').innerText = data.badgeName;
      document.getElementById('tier-badge-xp').innerText = data.reqXp;
      
      // Update info
      document.getElementById('tier-title').innerText = data.title;
      document.getElementById('tier-xp-label').innerText = data.reqXp;
      
      // Colors for xp badge label
      const xpLabel = document.getElementById('tier-xp-label');
      xpLabel.style.color = data.badgeColor;
      xpLabel.style.background = `${data.badgeColor}15`;
      
      document.getElementById('tier-description').innerText = data.desc;
      document.getElementById('tier-benefits-title').innerText = data.benefitsTitle;
      
      // Benefits list
      const list = document.getElementById('tier-benefits-list');
      list.innerHTML = '';
      data.benefits.forEach(ben => {
        const li = document.createElement('li');
        li.innerHTML = ben;
        // Prefix with check/x icon check if not already containing icon tag
        if (!ben.includes('<i')) {
          li.innerHTML = `<i class="fa-solid fa-circle-check"></i> ${ben}`;
        }
        list.appendChild(li);
      });
      
      card.style.opacity = '1';
      card.style.transform = 'translateY(0)';
    }, 150);
  }

  // Tiers Tabs Click Handlers
  const tabBtns = document.querySelectorAll('.tier-tab-btn');
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const tierKey = btn.getAttribute('data-tier');
      updateTiersCard(tierKey);
    });
  });

  // 7. General Language Toggle Logic
  const langToggleBtn = document.getElementById('lang-toggle');
  const langTexts = document.querySelectorAll('.lang-text');

  if (langToggleBtn) {
    langToggleBtn.addEventListener('click', () => {
      currentLang = currentLang === 'en' ? 'bn' : 'en';
      langToggleBtn.innerText = currentLang === 'en' ? 'বাং' : 'EN';
      
      // Update all elements with static translations
      langTexts.forEach(el => {
        const text = el.getAttribute(`data-${currentLang}`);
        if (text) {
          el.innerHTML = text; // supports bold strong tags
        }
      });

      // Update Tiers Showcase tab button text
      const tierButtons = document.querySelectorAll('.tier-tab-btn');
      tierButtons.forEach(btn => {
        const key = btn.getAttribute('data-tier');
        btn.innerText = tierData[key][currentLang].badgeName;
      });

      // Refresh dynamic components
      updateDetailsCard();
      updateTiersCard(activeTierKey);
    });
  }

  // 8. Modal Overlays
  const modal = document.getElementById('waitlist-modal');
  const openModalBtns = document.querySelectorAll('.open-modal');
  const closeModalBtn = document.querySelector('.close-modal');
  const waitlistForm = document.getElementById('waitlist-form');
  const successMsg = document.getElementById('success-msg');

  if (modal) {
    openModalBtns.forEach(btn => {
      btn.addEventListener('click', () => modal.classList.add('active'));
    });
    
    if (closeModalBtn) {
      closeModalBtn.addEventListener('click', () => modal.classList.remove('active'));
    }
    
    window.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.remove('active');
    });

    if (waitlistForm) {
      waitlistForm.addEventListener('submit', async (e) => {
        e.preventDefault();

        const formData = new FormData(waitlistForm);
        const submitBtn = waitlistForm.querySelector('button[type="submit"]');
        const originalText = submitBtn.textContent;
        submitBtn.disabled = true;
        submitBtn.textContent = '⏳ Sending...';

        function showSuccess() {
          waitlistForm.style.display = 'none';
          successMsg.style.display = 'block';
          setTimeout(() => {
            modal.classList.remove('active');
            setTimeout(() => {
              waitlistForm.style.display = 'block';
              successMsg.style.display = 'none';
              waitlistForm.reset();
              submitBtn.disabled = false;
              submitBtn.textContent = originalText;
            }, 400);
          }, 2500);
        }

        try {
          const response = await fetch('https://formsubmit.co/ajax/mybhromon@gmail.com', {
            method: 'POST',
            headers: { 'Accept': 'application/json' },
            body: formData
          });

          if (response.ok) {
            showSuccess();
          } else {
            console.warn('FormSubmit error:', response.status);
            showSuccess(); // Fallback success UX
          }
        } catch (err) {
          console.error('Submission catch error:', err);
          submitBtn.disabled = false;
          submitBtn.textContent = originalText;
          alert('Could not submit. Please email us at mybhromon@gmail.com');
        }
      });
    }
  }

  // 9. FAQ Accordion Click Handler
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

  // 10. Image Lightbox Overlay
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightbox-img');
  const lightboxClose = document.querySelector('.lightbox-close');
  const lightboxPrev = document.querySelector('.lightbox-prev');
  const lightboxNext = document.querySelector('.lightbox-next');

  const lightboxTriggers = document.querySelectorAll('.lightbox-trigger');
  const lightboxSources = Array.from(lightboxTriggers).map(el => el.getAttribute('data-src'));
  let currentLightboxIndex = 0;

  function openLightbox(index) {
    if (lightboxSources.length === 0) return;
    currentLightboxIndex = index;
    lightboxImg.src = lightboxSources[index];
    lightbox.classList.add('active');
    document.body.style.overflow = 'hidden';
    
    lightboxPrev.style.display = lightboxSources.length > 1 ? 'flex' : 'none';
    lightboxNext.style.display = lightboxSources.length > 1 ? 'flex' : 'none';
  }

  function closeLightbox() {
    lightbox.classList.remove('active');
    document.body.style.overflow = '';
    setTimeout(() => { lightboxImg.src = ''; }, 300);
  }

  function swapLightboxImage(index) {
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

  // 11. Cookie Consent Banner
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
  updateTiersCard('unverified');

  // ===========================================================================
  // 12. AI TRIP PLANNER SIMULATOR
  // ===========================================================================

  // Itinerary database — keyed by destination → budgetTier → groupSize
  // Each entry has en[] and bn[] arrays of day-schedule strings.
  const itineraryData = {
    sajek: {
      budget: {
        en: {
          title: 'Sajek Valley — Budget Pack',
          days: [
            { title: 'Day 1 · Dhaka → Khagrachari', activities: ['5:30 AM · Board Shyamoli Bus from Kalyanpur (৳800)', 'Arrive Khagrachari by noon — lunch at local dhaba (৳120)', '3:00 PM · Chander Gari jeep to Baghaihat Gate (shared, ৳600)', 'Check in at budget guesthouse near Ruiilui (৳400–600/night)'] },
            { title: 'Day 2 · Ruiilui → Konglak Sunrise', activities: ['5:00 AM · Hike to Konglak Hill for golden sunrise (free)', '8:00 AM · Breakfast at camp — alu-parota + tea (৳80)', 'Explore Sajek market — buy bamboo crafts & local honey', '4:00 PM · Sunset view at Heli Pad; campfire dinner (৳200)'] },
            { title: 'Day 3 · Return + Budget Wrap', activities: ['9:00 AM · Chander Gari back to Khagrachari (৳600)', 'Final lunch — Khagrachari bamboo chicken (৳150)', '2:00 PM · Shyamoli Bus back to Dhaka', '📊 Estimated total: ৳2,800–৳3,500 per person'] }
          ]
        },
        bn: {
          title: 'সাজেক ভ্যালি — বাজেট প্যাক',
          days: [
            { title: 'দিন ১ · ঢাকা → খাগড়াছড়ি', activities: ['সকাল ৫:৩০ · কল্যাণপুর থেকে শ্যামলী বাস (৳৮০০)', 'দুপুরে খাগড়াছড়ি পৌঁছান — স্থানীয় ধাবায় লাঞ্চ (৳১২০)', 'বিকেল ৩:০০ · বাঘাইহাট গেটে চাঁদের গাড়ি (শেয়ার, ৳৬০০)', 'রুইলুইয়ের কাছে বাজেট গেস্টহাউসে চেক-ইন (৳৪০০–৬০০/রাত)'] },
            { title: 'দিন ২ · রুইলুই → কংলাক সানরাইজ', activities: ['ভোর ৫:০০ · কংলাক পাহাড়ে সানরাইজ দেখতে হাইক (বিনামূল্যে)', 'সকাল ৮:০০ · ক্যাম্পে ব্রেকফাস্ট — আলু-পরোটা ও চা (৳৮০)', 'সাজেক বাজার দেখুন — বাঁশ শিল্প ও মধু কিনুন', 'বিকেল ৪:০০ · হেলিপ্যাড সানসেট; ক্যাম্পফায়ার ডিনার (৳২০০)'] },
            { title: 'দিন ৩ · প্রত্যাবর্তন + বাজেট সারসংক্ষেপ', activities: ['সকাল ৯:০০ · চাঁদের গাড়িতে খাগড়াছড়ি ফেরত (৳৬০০)', 'শেষ লাঞ্চ — খাগড়াছড়ি বাঁশ মুরগি (৳১৫০)', 'দুপুর ২:০০ · শ্যামলী বাসে ঢাকা ফেরত', '📊 আনুমানিক মোট: ৳২,৮০০–৳৩,৫০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Sajek Valley — 3-Day Comfort Trip',
          days: [
            { title: 'Day 1 · Dhaka → Sajek (Comfort Ride)', activities: ['5:00 AM · Private car from Dhaka to Khagrachari (৳3,500 split)', 'Lunch at Khagrachari Pouroshova — bamboo chicken thali', '3:00 PM · Booked Chander Gari convoy to Ruiilui (৳1,200)', 'Check in at Meghla Resort or similar (৳1,500–2,500/night)'] },
            { title: 'Day 2 · Konglak & Valley Trails', activities: ['5:15 AM · Guided sunrise hike to Konglak peak (guide: ৳500)', 'Breakfast at resort — Bengali-Chinese buffet (included)', 'Afternoon trail to Sajek Waterfall (seasonal)', 'Evening · BBQ dinner at resort terrace with valley view'] },
            { title: 'Day 3 · Departure + Khagrachari Sightseeing', activities: ['9:00 AM · Check-out; drive to Alutila Cave & Richhang Waterfall', 'Lunch at Khagrachari town', '2:30 PM · Return car to Dhaka', '📊 Estimated total: ৳6,000–৳9,000 per person (group of 4)'] }
          ]
        },
        bn: {
          title: 'সাজেক ভ্যালি — ৩ দিনের কমফোর্ট ট্রিপ',
          days: [
            { title: 'দিন ১ · ঢাকা → সাজেক (কমফোর্ট রাইড)', activities: ['ভোর ৫:০০ · ঢাকা থেকে প্রাইভেট কার (৳৩,৫০০ ভাগাভাগি)', 'খাগড়াছড়ি পৌরসভায় লাঞ্চ — বাঁশ মুরগির থালি', 'বিকেল ৩:০০ · বুকড চাঁদের গাড়ি কনভয় (৳১,২০০)', 'মেঘলা রিসোর্টে চেক-ইন (৳১,৫০০–২,৫০০/রাত)'] },
            { title: 'দিন ২ · কংলাক ও ভ্যালি ট্রেইল', activities: ['ভোর ৫:১৫ · গাইডেড সানরাইজ হাইক (গাইড: ৳৫০০)', 'রিসোর্টে ব্রেকফাস্ট — বাংলা-চাইনিজ বুফে (অন্তর্ভুক্ত)', 'বিকেলে সাজেক ঝর্ণায় ট্রেইল (মৌসুমী)', 'সন্ধ্যায় · রিসোর্টের টেরেসে BBQ ডিনার'] },
            { title: 'দিন ৩ · প্রস্থান + খাগড়াছড়ি সাইটসিয়িং', activities: ['সকাল ৯:০০ · চেক-আউট; আলুটিলা গুহা ও রিছাং ঝর্ণা', 'খাগড়াছড়ি শহরে লাঞ্চ', 'দুপুর ২:৩০ · ঢাকা ফেরত', '📊 আনুমানিক মোট: ৳৬,০০০–৳৯,০০০ জনপ্রতি (৪ জনের গ্রুপ)'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Sajek Valley — Premium Escape',
          days: [
            { title: 'Day 1 · Dhaka → Sajek (Luxury Transfer)', activities: ['Private AC microbus with driver (full-day: ৳8,000)', 'Stop at Khagrachari — upscale lunch at Sajek View Hotel', 'Private Chander Gari booking for group (৳2,500)', 'Check in at Meghla Premium Cottage — Valley View Suite'] },
            { title: 'Day 2 · Private Guided Exploration', activities: ['Private guide for full-day Konglak & Ruiilui trails (৳1,500)', 'Packed premium lunch with valley vista picnic spread', 'Photography session at golden hour on Konglak ridge', 'Live music & premium BBQ dinner arranged at resort'] },
            { title: 'Day 3 · Alutila Caves + Scenic Return', activities: ['Morning cave expedition at Alutila with guide (৳600)', 'Checkout; farewell Bengali-Chinese brunch at resort', 'AC transfer back to Dhaka with mid-route rest stop', '📊 Estimated total: ৳15,000–৳22,000 per person'] }
          ]
        },
        bn: {
          title: 'সাজেক ভ্যালি — প্রিমিয়াম এস্কেপ',
          days: [
            { title: 'দিন ১ · ঢাকা → সাজেক (লাক্সারি ট্রান্সফার)', activities: ['প্রাইভেট এসি মাইক্রোবাস (পুরো দিন: ৳৮,০০০)', 'খাগড়াছড়ি স্টপ — সাজেক ভিউ হোটেলে আপস্কেল লাঞ্চ', 'গ্রুপের জন্য প্রাইভেট চাঁদের গাড়ি বুকিং (৳২,৫০০)', 'মেঘলা প্রিমিয়াম কটেজে চেক-ইন — ভ্যালি ভিউ সুইট'] },
            { title: 'দিন ২ · প্রাইভেট গাইডেড অন্বেষণ', activities: ['কংলাক ও রুইলুই ট্রেইলের জন্য প্রাইভেট গাইড (৳১,৫০০)', 'ভ্যালি ভিস্তায় পিকনিক স্প্রেড সহ প্রিমিয়াম লাঞ্চ', 'কংলাক রিজে গোল্ডেন আওয়ারে ফটোগ্রাফি সেশন', 'রিসোর্টে লাইভ মিউজিক ও প্রিমিয়াম BBQ ডিনার'] },
            { title: 'দিন ৩ · আলুটিলা গুহা + সুন্দর প্রত্যাবর্তন', activities: ['সকালে গাইড সহ আলুটিলা গুহা অভিযান (৳৬০০)', 'চেক-আউট; রিসোর্টে বিদায়ী বাংলা-চাইনিজ ব্রাঞ্চ', 'মাঝপথে বিশ্রাম স্টপ সহ ঢাকায় এসি ট্রান্সফার', '📊 আনুমানিক মোট: ৳১৫,০০০–৳২২,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    sundarbans: {
      budget: {
        en: {
          title: 'Sundarbans — Budget Eco Tour',
          days: [
            { title: 'Day 1 · Dhaka → Mongla (Bus + Launch)', activities: ['6:00 AM · Bus from Dhaka to Khulna (৳600)', 'Khulna to Mongla by local bus (৳60)', 'Arrange shared boat with other backpackers at Mongla dock', 'Night on boat deck under the stars (৳800–1,200)'] },
            { title: 'Day 2 · Katka & Kochikhali Trails', activities: ['Sunrise boat into the mangrove creek — spot deer & birds', 'Forest trail at Katka Wildlife Sanctuary (permit: ৳150)', 'Simple lunch on boat — rice, daal, fish (৳150)', 'Afternoon · Kochikhali beach and tiger pug mark spotting'] },
            { title: 'Day 3 · Return to Mongla + Khulna', activities: ['Morning mangrove photography cruise', 'Return to Mongla by 12 noon', 'Bus back to Khulna; train to Dhaka (৳350)', '📊 Estimated total: ৳3,500–৳5,000 per person'] }
          ]
        },
        bn: {
          title: 'সুন্দরবন — বাজেট ইকো ট্যুর',
          days: [
            { title: 'দিন ১ · ঢাকা → মংলা (বাস + লঞ্চ)', activities: ['সকাল ৬:০০ · ঢাকা থেকে খুলনা বাস (৳৬০০)', 'লোকাল বাসে খুলনা থেকে মংলা (৳৬০)', 'মংলা ডকে অন্য ব্যাকপ্যাকারদের সাথে শেয়ার বোট ব্যবস্থা', 'রাতে বোটের ডেকে তারার নিচে (৳৮০০–১,২০০)'] },
            { title: 'দিন ২ · কটকা ও কচিখালী ট্রেইল', activities: ['সানরাইজ বোটে ম্যানগ্রোভ খালে — হরিণ ও পাখি দেখুন', 'কটকা বন্যপ্রাণী অভয়ারণ্যে বন ট্রেইল (পারমিট: ৳১৫০)', 'বোটে সরল লাঞ্চ — ভাত, ডাল, মাছ (৳১৫০)', 'বিকেলে কচিখালী বিচ ও বাঘের পায়ের ছাপ অনুসন্ধান'] },
            { title: 'দিন ৩ · মংলায় ফেরত + খুলনা', activities: ['সকালে ম্যানগ্রোভ ফটোগ্রাফি ক্রুজ', 'দুপুর ১২টার মধ্যে মংলায় ফেরত', 'খুলনায় বাস; ঢাকায় ট্রেন (৳৩৫০)', '📊 আনুমানিক মোট: ৳৩,৫০০–৳৫,০০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Sundarbans — 3-Day Comfort Cruise',
          days: [
            { title: 'Day 1 · Khulna → Deep Forest', activities: ['Depart Khulna by private tour boat (includes all meals)', 'Navigate Pashur River into Sundarbans core zone', 'Afternoon · Hiron Point forest walk with armed ranger escort', 'Sunset on deck; bonfire & fish BBQ dinner'] },
            { title: 'Day 2 · Tiger Territory & Birds', activities: ['Dawn wildlife watch at Katka watchtower (best tiger chance)', 'Nature walk — spotted deer, rhesus macaque sightings', 'Kochikhali beach visit — Bay of Bengal waves', 'Return to boat; evening documentary screening on deck'] },
            { title: 'Day 3 · Mangrove Canals + Departure', activities: ['Morning narrow creek boat safari (smallest boats)', 'Birding — kingfisher, sea eagle, stork colonies', 'Return cruise to Mongla/Khulna', '📊 Estimated total: ৳8,000–৳12,000 per person (tour package)'] }
          ]
        },
        bn: {
          title: 'সুন্দরবন — ৩ দিনের কমফোর্ট ক্রুজ',
          days: [
            { title: 'দিন ১ · খুলনা → গভীর বন', activities: ['প্রাইভেট ট্যুর বোটে খুলনা ছাড়ুন (সব মিল অন্তর্ভুক্ত)', 'পশুর নদী দিয়ে সুন্দরবনের কোর জোনে প্রবেশ', 'বিকেলে হিরণ পয়েন্টে সশস্ত্র রেঞ্জার এসকর্টে বন ভ্রমণ', 'ডেকে সানসেট; বনফায়ার ও মাছের BBQ ডিনার'] },
            { title: 'দিন ২ · বাঘের এলাকা ও পাখি', activities: ['ভোরে কটকা ওয়াচটাওয়ারে বন্যপ্রাণী দেখা (বাঘ দেখার সেরা সুযোগ)', 'প্রকৃতি হাঁটা — চিত্রা হরিণ, বানর দেখা', 'কচিখালী বিচ পরিদর্শন — বঙ্গোপসাগরের ঢেউ', 'বোটে ফেরত; সন্ধ্যায় ডেকে ডকুমেন্টারি স্ক্রিনিং'] },
            { title: 'দিন ৩ · ম্যানগ্রোভ খাল + প্রস্থান', activities: ['সকালে সংকীর্ণ খালে বোট সাফারি (ছোট নৌকায়)', 'পাখি দেখা — মাছরাঙা, সমুদ্র ঈগল, সারস কলোনি', 'মংলা/খুলনায় ফেরত ক্রুজ', '📊 আনুমানিক মোট: ৳৮,০০০–৳১২,০০০ জনপ্রতি (ট্যুর প্যাকেজ)'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Sundarbans — Premium Luxury Cruise',
          days: [
            { title: 'Day 1 · Dhaka → Luxury Cruise Vessel', activities: ['Private AC transfer Dhaka → Khulna launch ghat', 'Board a premium cruise vessel (en-suite cabins + sundeck)', 'Welcome dinner by executive chef — fresh Sundarbans seafood', 'Moonrise on the Pashur River with naturalist briefing'] },
            { title: 'Day 2 · VIP Forest Experience', activities: ['Private dawn safari by motorized dinghy into tiger territory', 'Expert naturalist guide — flora, fauna, and ecosystem lecture', 'Gourmet picnic lunch on a forest beach clearing', 'Sundowner cocktails on deck with wildlife silhouettes'] },
            { title: 'Day 3 · Aerial Photography + Return', activities: ['Drone photography session over Sundarbans canopy (permitted)', 'Luxury breakfast: smoked hilsa, fruit platter, coffee', 'Return to Khulna; private AC transfer to Dhaka or Jessore airport', '📊 Estimated total: ৳25,000–৳40,000 per person'] }
          ]
        },
        bn: {
          title: 'সুন্দরবন — প্রিমিয়াম লাক্সারি ক্রুজ',
          days: [
            { title: 'দিন ১ · ঢাকা → লাক্সারি ক্রুজ ভেসেল', activities: ['ঢাকা → খুলনা লঞ্চ ঘাটে প্রাইভেট এসি ট্রান্সফার', 'প্রিমিয়াম ক্রুজ ভেসেলে আরোহণ (এন-স্যুইট কেবিন + সানডেক)', 'এক্সিকিউটিভ শেফের তাজা সুন্দরবনের সামুদ্রিক খাবারে স্বাগত ডিনার', 'প্রকৃতিবিদের ব্রিফিং সহ পশুর নদীতে মুনরাইজ'] },
            { title: 'দিন ২ · ভিআইপি বন অভিজ্ঞতা', activities: ['বাঘের এলাকায় মোটরাইজড ডিঙ্গিতে প্রাইভেট ভোরের সাফারি', 'বিশেষজ্ঞ প্রকৃতিবিদ গাইড — উদ্ভিদ, প্রাণী ও ইকোসিস্টেম বক্তৃতা', 'বন সৈকতের ক্লিয়ারিংয়ে গুরমেট পিকনিক লাঞ্চ', 'বন্যপ্রাণীর সিলুয়েটের সাথে ডেকে সানডাউনার ককটেল'] },
            { title: 'দিন ৩ · এরিয়াল ফটোগ্রাফি + প্রত্যাবর্তন', activities: ['সুন্দরবনের ছাউনির উপর ড্রোন ফটোগ্রাফি সেশন (অনুমোদিত)', 'লাক্সারি ব্রেকফাস্ট: স্মোকড ইলিশ, ফল প্লাটার, কফি', 'খুলনায় ফেরত; ঢাকা বা যশোর এয়ারপোর্টে প্রাইভেট এসি ট্রান্সফার', '📊 আনুমানিক মোট: ৳২৫,০০০–৳৪০,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    sreemangal: {
      budget: {
        en: {
          title: 'Sreemangal — Budget Tea Garden Escape',
          days: [
            { title: 'Day 1 · Dhaka → Sreemangal by Train', activities: ['7:10 AM · Parabat Express from Kamalapur (৳290 shuvalon)', 'Arrive Sreemangal by 1:00 PM — lunch at local restaurant (৳100)', 'Rent a bicycle — explore tea estate roads (৳100/day)', 'Evening · Stay at budget guesthouse (৳350–500/night)'] },
            { title: 'Day 2 · Lawachara + 7-Layer Tea', activities: ['7:00 AM · Lawachara National Park forest walk (entry: ৳30)', 'Spot hoolock gibbons, sunbirds, and green pit vipers', 'Nilkantha Tea Cabin — 7-layer tea experience (৳70)', 'Afternoon · Cycling through Finlay tea estates'] },
            { title: 'Day 3 · Baikka Beel + Return', activities: ['Morning boat ride at Baikka Beel wetland bird sanctuary', 'Lunch at Sreemangal — tea-leaf salad & bamboo rice (৳120)', '2:30 PM · Train back to Dhaka', '📊 Estimated total: ৳1,800–৳2,500 per person'] }
          ]
        },
        bn: {
          title: 'শ্রীমঙ্গল — বাজেট চা বাগান এস্কেপ',
          days: [
            { title: 'দিন ১ · ঢাকা → শ্রীমঙ্গল ট্রেনে', activities: ['সকাল ৭:১০ · কমলাপুর থেকে পারাবত এক্সপ্রেস (৳২৯০ শুভলন)', 'দুপুর ১:০০ টায় শ্রীমঙ্গল পৌঁছান — স্থানীয় রেস্তোরায় লাঞ্চ (৳১০০)', 'সাইকেল ভাড়া — চা বাগানের রাস্তা এক্সপ্লোর (৳১০০/দিন)', 'সন্ধ্যায় বাজেট গেস্টহাউসে থাকুন (৳৩৫০–৫০০/রাত)'] },
            { title: 'দিন ২ · লাউয়াছড়া + ৭-লেয়ার চা', activities: ['সকাল ৭:০০ · লাউয়াছড়া জাতীয় উদ্যানে বন হাঁটা (প্রবেশ: ৳৩০)', 'উলুক, সানবার্ড ও সবুজ পিট ভাইপার দেখুন', 'নীলকণ্ঠ চায়ের কেবিন — ৭-লেয়ার চায়ের অভিজ্ঞতা (৳৭০)', 'বিকেলে ফিনলে চা এস্টেটে সাইক্লিং'] },
            { title: 'দিন ৩ · বাইক্কা বিল + প্রত্যাবর্তন', activities: ['বাইক্কা বিল আর্দ্রভূমি পাখি অভয়ারণ্যে সকালে নৌকা ভ্রমণ', 'শ্রীমঙ্গলে লাঞ্চ — চা-পাতার সালাদ ও বাঁশ ভাত (৳১২০)', 'বিকেল ২:৩০ · ঢাকায় ট্রেন ফেরত', '📊 আনুমানিক মোট: ৳১,৮০০–৳২,৫০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Sreemangal — Comfort Tea Tour (2 Days)',
          days: [
            { title: 'Day 1 · Dhaka → Sreemangal (AC Train)', activities: ['Upaban Express AC seat (৳520) — comfortable 3.5 hr ride', 'CNG pickup to Lawachara Park; guided birding walk (৳600 guide)', 'Lunch at Grand Sultan Resort — regional cuisine', 'Check-in at mid-range eco-cottage; evening tea estate walk'] },
            { title: 'Day 2 · Tea Factory + Baikka Beel + Return', activities: ['8:00 AM · Tea factory visit — processing demo (৳200 entry)', 'Nilkantha 7-layer tea tasting at the original cabin', 'Baikka Beel water bird safari by boat (৳300)', 'Afternoon train back — souvenir tea tins to carry home', '📊 Estimated total: ৳4,500–৳6,500 per person'] }
          ]
        },
        bn: {
          title: 'শ্রীমঙ্গল — কমফোর্ট চা ট্যুর (২ দিন)',
          days: [
            { title: 'দিন ১ · ঢাকা → শ্রীমঙ্গল (এসি ট্রেন)', activities: ['উপবন এক্সপ্রেস এসি সিট (৳৫২০) — আরামদায়ক ৩.৫ ঘণ্টার যাত্রা', 'লাউয়াছড়া পার্কে সিএনজি পিকআপ; গাইডেড বার্ডিং ওয়াক (৳৬০০)', 'গ্র্যান্ড সুলতান রিসোর্টে আঞ্চলিক খাবারে লাঞ্চ', 'মিড-রেঞ্জ ইকো-কটেজে চেক-ইন; সন্ধ্যায় চা বাগান হাঁটা'] },
            { title: 'দিন ২ · চা কারখানা + বাইক্কা বিল + ফেরত', activities: ['সকাল ৮:০০ · চা কারখানা পরিদর্শন — প্রসেসিং ডেমো (৳২০০ প্রবেশ)', 'নীলকণ্ঠের মূল কেবিনে ৭-লেয়ার চা টেস্টিং', 'বোটে বাইক্কা বিল পানি পাখি সাফারি (৳৩০০)', 'বিকেলে ট্রেনে ফেরত — স্যুভেনির চায়ের টিন নিয়ে', '📊 আনুমানিক মোট: ৳৪,৫০০–৳৬,৫০০ জনপ্রতি'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Sreemangal — Luxury Tea Retreat',
          days: [
            { title: 'Day 1 · Arrival & Heritage Tea Experience', activities: ['Private AC car from Dhaka (৳6,000 split 4 ways)', 'Check in at Grand Sultan Resort — pool suite', 'Private plucking session on Finlay estate with tea sommelier', 'Evening · 5-course dinner with local forest mushrooms & organic tea pairing'] },
            { title: 'Day 2 · Exclusive Wildlife & Wellness', activities: ['Private naturalist sunrise walk in Lawachara old-growth forest', 'Hoolock gibbon and hornbill spotting with binoculars provided', 'Spa treatment at resort — aroma tea massage (90 min)', 'Sunset at Hail Haor with private boat & canapes'] },
            { title: 'Day 3 · Tea Auction Showroom + Departure', activities: ['Exclusive access to Sreemangal Tea Auction demo', 'Curated luxury tea gift box assembly (take home)', 'Farewell brunch at resort — hill-view dining', '📊 Estimated total: ৳18,000–৳28,000 per person'] }
          ]
        },
        bn: {
          title: 'শ্রীমঙ্গল — লাক্সারি চা রিট্রিট',
          days: [
            { title: 'দিন ১ · আগমন ও ঐতিহ্যবাহী চা অভিজ্ঞতা', activities: ['ঢাকা থেকে প্রাইভেট এসি কার (৳৬,০০০ ভাগাভাগি ৪ জনে)', 'গ্র্যান্ড সুলতান রিসোর্টে চেক-ইন — পুল স্যুইট', 'চা সোমেলিয়ারের সাথে ফিনলে এস্টেটে প্রাইভেট পাতা তোলার সেশন', 'সন্ধ্যায় · স্থানীয় বন মাশরুম ও অর্গানিক চা পেয়ারিংয়ে ৫-কোর্স ডিনার'] },
            { title: 'দিন ২ · এক্সক্লুসিভ বন্যপ্রাণী ও সুস্থতা', activities: ['লাউয়াছড়ার পুরনো বনে প্রাইভেট প্রকৃতিবিদ সানরাইজ ওয়াক', 'বাইনোকুলার দিয়ে উলুক ও হর্নবিল দেখা', 'রিসোর্টে স্পা ট্রিটমেন্ট — অ্যারোমা টি ম্যাসাজ (৯০ মিনিট)', 'প্রাইভেট বোট ও ক্যানাপে সহ হাইল হাওরে সানসেট'] },
            { title: 'দিন ৩ · চা নিলাম শোরুম + প্রস্থান', activities: ['শ্রীমঙ্গল চা নিলাম ডেমোতে এক্সক্লুসিভ অ্যাক্সেস', 'কিউরেটেড লাক্সারি চা উপহার বাক্স সংকলন (বাড়িতে নিয়ে যান)', 'রিসোর্টে বিদায়ী ব্রাঞ্চ — হিল-ভিউ ডাইনিং', '📊 আনুমানিক মোট: ৳১৮,০০০–৳২৮,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    bandarban: {
      budget: {
        en: {
          title: 'Bandarban Hills — Budget Trek',
          days: [
            { title: 'Day 1 · Dhaka → Bandarban Town', activities: ['7:00 PM · S Alam or Shyamoli bus from Dhaka (৳700)', 'Arrive Bandarban early morning; breakfast at town market (৳80)', 'Chander Gari to Nilgiri (army permit required: ৳50)', 'Stay at basic dorm near Meghla tourist park (৳350)'] },
            { title: 'Day 2 · Nafakhum Waterfall Trek', activities: ['6:00 AM · Engine boat from Remakri Bazar to Nafakhum trailhead', 'Trek through Bom tribal villages — 4 hour hike each way', 'Swim at Nafakhum falls — bring packed lunch (৳150)', 'Return by boat to Remakri; overnight at local homestay (৳400)'] },
            { title: 'Day 3 · Boga Lake + Return', activities: ['Morning · Trek/jeep to Boga Lake crater — stunning vistas', 'Lunch at Boga Lake side — local noodles (৳100)', 'Return Bandarban town; evening bus back to Dhaka', '📊 Estimated total: ৳3,000–৳4,500 per person'] }
          ]
        },
        bn: {
          title: 'বান্দরবান পাহাড় — বাজেট ট্রেক',
          days: [
            { title: 'দিন ১ · ঢাকা → বান্দরবান শহর', activities: ['রাত ৭:০০ · ঢাকা থেকে এস আলম বা শ্যামলী বাস (৳৭০০)', 'ভোরবেলা বান্দরবান পৌঁছান; শহরের বাজারে ব্রেকফাস্ট (৳৮০)', 'নীলগিরিতে চাঁদের গাড়ি (সেনা পারমিট প্রয়োজন: ৳৫০)', 'মেঘলা ট্যুরিস্ট পার্কের কাছে বেসিক ডর্মে থাকুন (৳৩৫০)'] },
            { title: 'দিন ২ · নাফাখুম ঝর্ণা ট্রেক', activities: ['ভোর ৬:০০ · রেমাক্রি বাজার থেকে ইঞ্জিন নৌকায় নাফাখুম ট্রেইলহেড', 'বম উপজাতীয় গ্রামের মধ্য দিয়ে ট্রেক — প্রতি পথে ৪ ঘণ্টার হাইক', 'নাফাখুম ঝর্ণায় সাঁতার — প্যাক্ড লাঞ্চ নিয়ে যান (৳১৫০)', 'নৌকায় রেমাক্রিতে ফেরত; স্থানীয় হোমস্টেতে রাত (৳৪০০)'] },
            { title: 'দিন ৩ · বগা লেক + প্রত্যাবর্তন', activities: ['সকালে বগা লেক ক্র্যাটারে ট্রেক/জিপ — অসাধারণ দৃশ্য', 'বগা লেকের পাশে লাঞ্চ — স্থানীয় নুডলস (৳১০০)', 'বান্দরবান শহরে ফেরত; সন্ধ্যায় বাসে ঢাকা ফেরত', '📊 আনুমানিক মোট: ৳৩,০০০–৳৪,৫০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Bandarban — 3-Day Comfort Trek',
          days: [
            { title: 'Day 1 · Dhaka → Nilgiri (Hilltop Hotel)', activities: ['AC Sleeper bus Dhaka → Bandarban (৳1,000)', 'Hired CNG/jeep to army check post + Nilgiri summit (৳1,500 split)', 'Check-in at Nilgiri Hilltop Resort (army-run; book ahead)', 'Sunset above the clouds — magical golden hour panorama'] },
            { title: 'Day 2 · Nafakhum + Remakri Trail', activities: ['Full-day guided trek — Bandarban agency guide (৳800)', 'Engine boat + hiking combo to Nafakhum Falls (4WD jeep hired)', 'Lunch & swim at Nafakhum; back to Thanchi by sunset', 'Overnight at comfort lodge in Thanchi (৳800–1,000)'] },
            { title: 'Day 3 · Chimbuk Hill + Departure', activities: ['Morning panorama drive to Chimbuk — 2,500 ft elevation', 'Marma breakfast village stop — sticky rice & bamboo dishes', 'Return Bandarban; AC bus to Dhaka afternoon', '📊 Estimated total: ৳7,000–৳10,000 per person'] }
          ]
        },
        bn: {
          title: 'বান্দরবান — ৩ দিনের কমফোর্ট ট্রেক',
          days: [
            { title: 'দিন ১ · ঢাকা → নীলগিরি (হিলটপ হোটেল)', activities: ['এসি স্লিপার বাস ঢাকা → বান্দরবান (৳১,০০০)', 'আর্মি চেক পোস্ট + নীলগিরি সামিটে ভাড়া করা সিএনজি/জিপ (৳১,৫০০ ভাগাভাগি)', 'নীলগিরি হিলটপ রিসোর্টে চেক-ইন (সেনা-পরিচালিত; আগে বুক করুন)', 'মেঘের উপরে সানসেট — জাদুকরী গোল্ডেন আওয়ার প্যানোরামা'] },
            { title: 'দিন ২ · নাফাখুম + রেমাক্রি ট্রেইল', activities: ['সারাদিনের গাইডেড ট্রেক — বান্দরবান এজেন্সি গাইড (৳৮০০)', 'ইঞ্জিন বোট + হাইকিং কম্বো নাফাখুম ঝর্ণায় (৪WD জিপ ভাড়া)', 'নাফাখুমে লাঞ্চ ও সাঁতার; সানসেটের আগে থানচিতে ফেরত', 'থানচিতে কমফোর্ট লজে রাত (৳৮০০–১,০০০)'] },
            { title: 'দিন ৩ · চিম্বুক পাহাড় + প্রস্থান', activities: ['সকালে চিম্বুক পাহাড়ে প্যানোরামা ড্রাইভ — ২,৫০০ ফুট উচ্চতা', 'মারমা ব্রেকফাস্ট গ্রাম স্টপ — চিটালি ভাত ও বাঁশের খাবার', 'বান্দরবান ফেরত; বিকেলে এসি বাসে ঢাকা', '📊 আনুমানিক মোট: ৳৭,০০০–৳১০,০০০ জনপ্রতি'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Bandarban — Premium Hill Retreat',
          days: [
            { title: 'Day 1 · Dhaka → Nilgiri (Helicopter Option)', activities: ['Optional heli charter Dhaka → Bandarban (seasonal; ৳25,000/seat)', 'Private 4WD convoy to Nilgiri summit (৳5,000 split)', 'Check-in at premium resort suite — mountain valley view', 'Private chef dinner with tribal fusion cuisine on the terrace'] },
            { title: 'Day 2 · Exclusive Tribal Cultural Immersion', activities: ['Private guide & 4WD for Bom and Marma village cultural visit', 'Weaving workshop with indigenous artisans (take home fabric)', 'Helicopter sightseeing loop over Keokradong & Boga Lake', 'Gourmet candlelit dinner — hilltop stargazing session'] },
            { title: 'Day 3 · Keokradong Summit Attempt + Departure', activities: ['Dawn hike to Keokradong (4,035 ft) — highest accessible peak', 'Summit breakfast with panoramic BD-Myanmar border views', 'Return by private 4WD; AC transfer or flight to Dhaka', '📊 Estimated total: ৳30,000–৳50,000 per person'] }
          ]
        },
        bn: {
          title: 'বান্দরবান — প্রিমিয়াম হিল রিট্রিট',
          days: [
            { title: 'দিন ১ · ঢাকা → নীলগিরি (হেলিকপ্টার অপশন)', activities: ['ঐচ্ছিক হেলি চার্টার ঢাকা → বান্দরবান (মৌসুমী; ৳২৫,০০০/সিট)', 'নীলগিরি সামিটে প্রাইভেট ৪WD কনভয় (৳৫,০০০ ভাগাভাগি)', 'প্রিমিয়াম রিসোর্ট স্যুইটে চেক-ইন — মাউন্টেন ভ্যালি ভিউ', 'টেরেসে উপজাতীয় ফিউশন কুইজিনে প্রাইভেট শেফ ডিনার'] },
            { title: 'দিন ২ · এক্সক্লুসিভ আদিবাসী সাংস্কৃতিক নিমজ্জন', activities: ['বম ও মারমা গ্রামে সাংস্কৃতিক পরিদর্শনে প্রাইভেট গাইড ও ৪WD', 'আদিবাসী কারিগরদের সাথে বুনন কর্মশালা (কাপড় বাড়িতে নিয়ে যান)', 'কেওক্রাডং ও বগা লেকের উপর হেলিকপ্টার সাইটসিয়িং লুপ', 'গুরমেট ক্যান্ডেলিট ডিনার — হিলটপে স্টারগেজিং সেশন'] },
            { title: 'দিন ৩ · কেওক্রাডং সামিট অ্যাটেম্পট + প্রস্থান', activities: ['কেওক্রাডং (৪,০৩৫ ফুট) — সবচেয়ে সহজলভ্য সর্বোচ্চ চূড়ায় ভোরের হাইক', 'বাংলাদেশ-মিয়ানমার সীমান্তের প্যানোরামিক দৃশ্যে সামিট ব্রেকফাস্ট', 'প্রাইভেট ৪WD-এ ফেরত; ঢাকায় এসি ট্রান্সফার বা ফ্লাইট', '📊 আনুমানিক মোট: ৳৩০,০০০–৳৫০,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    dhaka: {
      budget: {
        en: {
          title: 'Dhaka City — Budget Heritage Tour',
          days: [
            { title: 'Day 1 · Old Dhaka Walkabout', activities: ['8:00 AM · Visit Lalbagh Fort (Mughal-era, entry: ৳30)', '11:00 AM · Walk through Shakharia Bazar & explore Star Mosque (Tara Masjid)', '1:30 PM · Traditional Lunch: Nazira Bazar royal mutton biryani (৳180)', '3:00 PM · Ahsan Manzil Pink Palace & Sadarghat country boat ride (৳150)'] },
            { title: 'Day 2 · University & Cultural Icons', activities: ['9:30 AM · Historical walk around Curzon Hall (Dhaka University campus)', '11:30 AM · Bangladesh National Museum (Shahbagh, entry: ৳40)', 'Lunch at local hotel near TSC — duck khichuri (৳120)', '3:30 PM · Stroll near Ramna Park & Central Shahid Minar'] },
            { title: 'Day 3 · Shopping & Local Chawkbazar Eats', activities: ['10:00 AM · Exploring old bazaars & traditional brass workshops', 'Lunch at Chawkbazar (street food sampler: ৳100)', '3:00 PM · Visit Liberation War Museum (Agargaon, entry: ৳20)', '📊 Estimated base rate: ৳800–৳1,200 per person'] }
          ]
        },
        bn: {
          title: 'ঢাকা সিটি — বাজেট হেরিটেজ ট্যুর',
          days: [
            { title: 'দিন ১ · পুরান ঢাকা হেরিটেজ ওয়াক', activities: ['সকাল ৮:০০ · লালবাগ কেল্লা পরিদর্শন (মোগল আমল, প্রবেশ: ৳৩০)', 'সকাল ১১:০০ · শাঁখারী বাজার পদভ্রমণ ও তারা মসজিদ পরিদর্শন', 'দুপুর ১:৩০ · দুপুরের খাবার: নাজিরা বাজারের ঐতিহ্যবাহী কাচ্চি বিরিয়ানি (৳১৮০)', 'বিকেল ৩:০০ · আহসান মঞ্জিল ও সদরঘাটে খেয়া নৌকা ভ্রমণ (৳১৫০)'] },
            { title: 'দিন ২ · বিশ্ববিদ্যালয় ও সাংস্কৃতিক কেন্দ্র', activities: ['সকাল ৯:৩০ · কার্জন হল প্রাঙ্গণে ঐতিহাসিক ওয়াক', 'সকাল ১১:৩০ · বাংলাদেশ জাতীয় জাদুঘর পরিদর্শন (শাহবাগ, প্রবেশ: ৳৪০)', 'দুপুরে টিএসসির কাছে এসি ও হাঁসের খিচুড়ি (৳১২০)', 'বিকেল ৩:৩০ · রমনা পার্ক ও কেন্দ্রীয় শহীদ মিনার'] },
            { title: 'দিন ৩ · কেনাকাটা ও চকবাজারের খাবার', activities: ['সকাল ১০:০০ · পুরান ঢাকার ঐতিহ্যবাহী শাঁখ ও তামার কর্মশালা পরিদর্শন', 'চকবাজারে দুপুরের খাবার (স্ট্রিট ফুড সাম্পলার: ৳১০০)', 'বিকেল ৩:০০ · মুক্তিযুদ্ধ জাদুঘর পরিদর্শন (আগারগাঁও, প্রবেশ: ৳২০)', '📊 আনুমানিক বেস রেট: ৳৮০০–৳১,২০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Dhaka City — 3-Day Comfort Heritage Tour',
          days: [
            { title: 'Day 1 · Private Mughal Tour', activities: ['9:00 AM · Hired private AC CNG for Old Dhaka explorer (৳1,200/day)', 'Private guided tour of Lalbagh Fort and Armenian Church (guide: ৳400)', 'Gourmet lunch at Al-Razzaque Restaurant (mutton glass, ৳350)', '3:00 PM · Private engine boat cruise on Buriganga River'] },
            { title: 'Day 2 · Art, Architecture & Parliament Tour', activities: ['9:30 AM · Architecture tour of Curzon Hall & Dhaka University', '12:00 PM · Varendra research exhibition at national gallery', 'Lunch at Dhanmondi — upscale traditional Bengali thali (৳400)', '3:30 PM · Parliament (Jatiya Sangsad Bhaban) lakeside walk'] },
            { title: 'Day 3 · Shopping & Heritage Dining', activities: ['10:00 AM · Premium local fabrics shopping at Aarong outlet', '2:00 PM · High tea & local sweet sampling at Banoful', '7:00 PM · Buffet dinner at upscale restaurant (traditional Bengali fusion)', '📊 Estimated base rate: ৳2,000–৳3,000 per person'] }
          ]
        },
        bn: {
          title: 'ঢাকা সিটি — কমফোর্ট হেরিটেজ ট্যুর',
          days: [
            { title: 'দিন ১ · মোগল হেরিটেজ প্রাইভেট ট্যুর', activities: ['সকাল ৯:০০ · পুরান ঢাকা এক্সপ্লোর করতে প্রাইভেট এসি সিএনজি (৳১,২০০/দিন)', 'লালবাগ কেল্লা ও আর্মেনিয়ান চার্চে প্রাইভেট গাইড ট্যুর (গাইড: ৳৪০০)', 'আল-রাজ্জাক রেস্টুরেন্টে ঐতিহ্যবাহী লাঞ্চ (৳৩৫০)', 'বিকেল ৩:০০ · বুড়িগঙ্গা নদীতে ইঞ্জিন বোটে বিশেষ ক্রুজ'] },
            { title: 'দিন ২ · শিল্প, স্থাপত্য ও সংসদ প্রাঙ্গণ', activities: ['সকাল ৯:৩০ · কার্জন হল ও ঢাকা বিশ্ববিদ্যালয়ের স্থাপত্য পরিদর্শন', 'দুপুর ১২:০০ · জাতীয় গ্যালারিতে আর্ট এক্সিবিশন', 'ধানমন্ডিতে লাঞ্চ — চমত্কার বাঙালি ভর্তা-ভাত থালি (৳৪০০)', 'বিকেল ৩:৩০ · জাতীয় সংসদ ভবন লেকের পাড়ে ওয়াক'] },
            { title: 'দিন ৩ · শপিং ও হেরিটেজ ডাইনিং', activities: ['সকাল ১০:০০ · আড়ং আউটলেটে প্রিমিয়াম দেশীয় শপিং', 'দুপুর ২:০০ · ঐতিহ্যবাহী মিষ্টি ও বাকরখানি টেস্টিং', 'সন্ধ্যা ৭:০০ · রাজকীয় বাঙালি ফিউশন বুফে ডিনার (৳১,০০০)', '📊 আনুমানিক বেস রেট: ৳২,০০০–৳৩,০০০ জনপ্রতি'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Dhaka City — Premium Staycation & Tour',
          days: [
            { title: 'Day 1 · 5-Star Stay & Mughal Private Tour', activities: ['Check-in at InterContinental Dhaka (Club Suite)', 'Private AC chauffeur transport for historical ruins tour (৳4,500/day)', 'Historian-led exclusive walk inside Lalbagh and Ahsan Manzil', 'Gourmet dinner at hotel restaurant (premium multi-cuisine)'] },
            { title: 'Day 2 · Heritage Trail & Buriganga Sunset Cruise', activities: ['Private gourmet breakfast buffet at executive lounge', 'Exclusive access & photo permits inside Curzon Hall & Rose Garden', 'Sunset on a chartered premium cruise vessel on Buriganga with live music', 'Premium seafood dinner arranged on the vessel'] },
            { title: 'Day 3 · Luxury Shopping & Rooftop Stargazing', activities: ['Bespoke shopping tour (private boutique and designer silk)', 'Rooftop high-tea at Gulshan-2 overlooking city skyline', 'Spa & wellness treatment at hotel (90 min premium therapy)', '📊 Estimated base rate: ৳6,000–৳9,000 per person'] }
          ]
        },
        bn: {
          title: 'ঢাকা সিটি — লাক্সারি স্টেকেশন ও ট্যুর',
          days: [
            { title: 'দিন ১ · ৫-স্টার স্টেকেশন ও মোগল রাজকীয় ট্যুর', activities: ['ইন্টারকন্টিনেন্টাল ঢাকায় চেক-ইন (ক্লাব সুইট)', 'প্রাইভেট লাক্সারি এসি মাইক্রোবাসে ঐতিহাসিক স্থান পরিদর্শন (৳৪,৫০০/দিন)', 'গবেষকদের বিশেষ সান্নিধ্যে লালবাগ ও আহসান মঞ্জিল হেরিটেজ ওয়াক', 'হোটেলের রাজকীয় মাল্টি-কুইজিন রেস্টুরেন্টে ডিনার'] },
            { title: 'দিন ২ · হেরিটেজ ট্রেইল ও বুড়িগঙ্গা লাক্সারি ক্রুজ', activities: ['এক্সিকিউটিভ লাউঞ্জে প্রাইভেট বুফে ব্রেকফাস্ট', 'রোজ গার্ডেন ও কার্জন হলে বিশেষ ফটো ও ভিডিও পারমিট', 'বুড়িগঙ্গায় প্রাইভেট লাইভ মিউজিক সহ লাক্সারি লঞ্চে সানসেট ক্রুজ', 'ক্রুজ ভেসেলে প্রিমিয়াম সামুদ্রিক খাবারের ডিনার'] },
            { title: 'দিন ৩ · এক্সক্লুসিভ শপিং ও রুফটপ হাই-টি', activities: ['ডিজাইনার বুটিক ও সিল্ক শোরুমগুলোতে পার্সোনাল শপিং গাইড', 'গুলশান-২ এ রুফটপ লাউঞ্জে শহরের দৃশ্য দেখতে দেখতে হাই-টি', 'হোটেলের প্রিমিয়াম স্পা থেরাপি (৯০ মিনিট রিল্যাক্সেশন)', '📊 আনুমানিক বেস রেট: ৳৬,০০০–৳৯,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    paharpur: {
      budget: {
        en: {
          title: 'Paharpur & Mahasthangarh — Budget Archeology Trek',
          days: [
            { title: 'Day 1 · Dhaka → Bogura → Mahasthangarh', activities: ['6:30 AM · Non-AC Bus from Kalyanpur to Bogura (৳450)', 'Arrive Bogura, take local shared CNG to Mahasthangarh (৳50)', 'Explore ancient ruins & Mahasthangarh museum (entry: ৳30)', 'Check in at budget guest house in Bogura town (৳400/night)'] },
            { title: 'Day 2 · Somapura Mahavihara Terracotta Ruins', activities: ['8:00 AM · Local bus to Joypurhat/Paharpur (৳80)', 'Explore Paharpur Somapura Mahavihara UNESCO site (entry: ৳30)', 'Terracotta plaques & central stupa photography session', 'Late lunch: local khichuri & Dinajpur doi (yogurt) (৳120)'] },
            { title: 'Day 3 · Bogura Curd Sampling & Return', activities: ['9:00 AM · Visit Bogura Rajbari ruins (free)', 'Taste famous Bogurar Doi at Asia Sweet (৳100)', '1:00 PM · Bus back to Dhaka (৳450)', '📊 Estimated base rate: ৳2,200–৳3,000 per person'] }
          ]
        },
        bn: {
          title: 'পাহাড়পুর ও মহাস্থানগড় — বাজেট প্রত্নতাত্ত্বিক ট্রেক',
          days: [
            { title: 'দিন ১ · ঢাকা → বগুড়া → মহাস্থানগড়', activities: ['সকাল ৬:৩০ · কল্যাণপুর থেকে বগুড়ার নন-এসি বাস (৳৪৫০)', 'বগুড়া পৌঁছে লোকাল শেয়ার্ড সিএনজিতে মহাস্থানগড় (৳৫০)', 'প্রাচীন ধ্বংসাবশেষ ও মহাস্থানগড় জাদুঘর এক্সপ্লোর (প্রবেশ: ৳৩০)', 'বগুড়া শহরের বাজেট গেস্ট হাউসে চেক-ইন (৳৪০০/রাত)'] },
            { title: 'দিন ২ · সোমপুর মহাবিহার টেরাকোটা ধ্বংসাবশেষ', activities: ['সকাল ৮:০০ · লোকাল বাসে জয়পুরহাট হয়ে পাহাড়পুর (৳৮০)', 'পাহাড়পুর সোমপুর মহাবিহার ইউনেস্কো সাইট পরিদর্শন (প্রবেশ: ৳৩০)', 'বিখ্যাত টেরাকোটা ফলক ও কেন্দ্রীয় স্তূপের ফটোগ্রাফি', 'দুপুরের খাবার: স্থানীয় খিচুড়ি ও দই (৳১২০)'] },
            { title: 'দিন ৩ · বগুড়ার দই ও ঢাকা প্রত্যাবর্তন', activities: ['সকাল ৯:০০ · বগুড়া রাজবাড়ী ধ্বংসাবশেষ পরিদর্শন (বিনামূল্যে)', 'এশিয়া সুইটসে বিখ্যাত বগুড়ার দই টেস্ট (৳১০০)', 'দুপুর ১:০০ · বাসে ঢাকা প্রত্যাবর্তন (৳৪৫০)', '📊 আনুমানিক বেস রেট: ৳২,২০০–৳৩,০০০ জনপ্রতি'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Paharpur Archeology Tour — 3-Day Comfort',
          days: [
            { title: 'Day 1 · Dhaka → Bogura (AC Comfort)', activities: ['7:00 AM · AC Bus to Bogura (৳900) — comfort ride', 'Check in at Hotel Naz Garden or similar (৳2,500/night)', 'Hired CNG to Mahasthangarh ruins & Behula Laxmindar Ghor (৳600)', 'Taste premium Bogura Doi at source (Doi: ৳200)'] },
            { title: 'Day 2 · Somapura Mahavihara UNESCO Guided Tour', activities: ['8:30 AM · Reserved AC car to Paharpur site (৳3,000 split)', 'Official guide tour of the central stupa and museum (guide: ৳500)', 'Photography and landscape walk inside the monastery gardens', 'Traditional lunch at tourist motel near Paharpur (৳300)'] },
            { title: 'Day 3 · Varendra Research Museum & Train Return', activities: ['8:00 AM · Drive to Rajshahi city, Varendra Research Museum (entry: ৳50)', 'Walk along Padma River bank (Lalon Shah Park)', '4:00 PM · Silk City Express AC Train back to Dhaka (৳560)'] }
          ]
        },
        bn: {
          title: 'পাহাড়পুর প্রত্নতত্ত্ব ট্যুর — ৩ দিনের কমফোর্ট',
          days: [
            { title: 'দিন ১ · ঢাকা → বগুড়া (এসি কমফোর্ট)', activities: ['সকাল ৭:০০ · বগুড়ায় এসি বাস (৳৯০০) — আরামদায়ক যাত্রা', 'হোটেল নাজ গার্ডেন বা সমমানের হোটেলে চেক-ইন (৳২,৫০০/রাত)', 'ভাড়া করা সিএনজিতে মহাস্থানগড় ও বেহুলার বাসর ঘর (৳৬০০)', 'উৎস থেকে প্রিমিয়াম বগুড়ার দই টেস্ট (৳২০০)'] },
            { title: 'দিন ২ · সোমপুর মহাবিহার গাইডেড ট্যুর', activities: ['সকাল ৮:৩০ · পাহাড়পুর সাইটে রিজার্ভ এসি কার (৳৩,০০০ ভাগাভাগি)', 'কেন্দ্রীয় স্তূপ ও জাদুঘরে অফিসিয়াল গাইড ট্যুর (গাইড: ৳৫০০)', 'মহাবিহারের ভেতরে সবুজ বাগানে ফটোগ্রাফি ও ওয়াক', 'পাহাড়পুরের কাছে পর্যটন মোটেলে ঐতিহ্যবাহী লাঞ্চ (৳৩০০)'] },
            { title: 'দিন ৩ · বরেন্দ্র জাদুঘর ও ট্রেনে প্রত্যাবর্তন', activities: ['সকাল ৮:০০ · রাজশাহী ড্রাইভ, বরেন্দ্র গবেষণা জাদুঘর পরিদর্শন (৳৫০)', 'পদ্মা নদীর পাড়ে হাঁটা (লালন শাহ পার্ক)', 'বিকেল ৪:০০ · সিল্কসিটি এক্সপ্রেস এসি ট্রেনে ঢাকা ফেরত (৳৫৬০)'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'UNESCO Heritage — Premium Antiquity Tour',
          days: [
            { title: 'Day 1 · Flight to Rajshahi → Bogura Luxury Transfer', activities: ['10:00 AM · Flight Dhaka to Rajshahi (US-Bangla, ৳4,500)', 'Private luxury AC SUV transfer Rajshahi → Bogura (৳5,000)', 'Stay at 4-star Hotel Momo Inn (Executive Suite, ৳8,000/night)', 'Gourmet dinner at hotel restaurant overlooking pool'] },
            { title: 'Day 2 · Archaeologist-Led Somapura Mahavihara Tour', activities: ['Private specialist archaeologist guide for Paharpur ruins (৳2,500)', 'Exclusive photo permits & stupa summit access with ranger escort', 'Catered VIP lunch buffet set up near site gardens', 'Evening · Stargazing from the premium resort lawn'] },
            { title: 'Day 3 · Padma River Yacht Cruise & Silk Shopping', activities: ['Private luxury boat cruise on Padma River (Rajshahi, ৳4,000)', 'VIP shopping at Rajshahi Silk Showrooms (designer silks)', 'Evening flight Saidpur/Rajshahi back to Dhaka', '📊 Estimated base rate: ৳14,000–৳20,000 per person'] }
          ]
        },
        bn: {
          title: 'ইউনেস্কো ওয়ার্ল্ড হেরিটেজ — প্রিমিয়াম প্রত্নতত্ত্ব ট্যুর',
          days: [
            { title: 'দিন ১ · রাজশাহীতে ফ্লাইট → বগুড়ায় লাক্সারি ট্রান্সফার', activities: ['সকাল ১০:০০ · ঢাকা থেকে রাজশাহীতে ফ্লাইট (৳৪,৫০০)', 'প্রাইভেট লাক্সারি এসি SUV-তে রাজশাহী থেকে বগুড়া ট্রান্সফার (৳৫,০০০)', '৪-স্টার হোটেল মোমো ইনে চেক-ইন (এক্সিকিউটিভ সুইট, ৳৮,০০০/রাত)', 'হোটেলের রেস্টুরেন্টে বিশেষ ডিনার'] },
            { title: 'দিন ২ · প্রত্নতত্ত্ববিদের সাথে পাহাড়পুর হেরিটেজ ট্যুর', activities: ['পাহাড়পুর ধ্বংসাবশেষে বিশেষ প্রত্নতত্ত্ববিদ গাইডের সেবা (৳২,৫০০)', 'বিশেষ পারমিট সহ স্তূপের কাছে রেঞ্জার এসকর্টে এক্সক্লুসিভ অ্যাক্সেস', 'গার্ডেনে কিউরেটেড প্রিমিয়াম লাঞ্চ বুফে', 'সন্ধ্যায় · প্রিমিয়াম রিসোর্টের লনে লাইভ গান ও বারবিকিউ'] },
            { title: 'দিন ৩ · পদ্মা নদীতে স্পিডবোট লাক্সারি ক্রুজ ও সিল্ক শপিং', activities: ['পদ্মা নদীতে প্রাইভেট স্পিডবোট ক্রুজ (রাজশাহী, ৳৪,০০০)', 'রাজশাহী সিল্ক শোরুমে এক্সক্লুসিভ সিল্ক শপিং', 'সন্ধ্যায় রাজশাহী থেকে বিমানে ঢাকা প্রত্যাবর্তন', '📊 আনুমানিক বেস রেট: ৳১৪,০০০–৳২০,০০০ জনপ্রতি'] }
          ]
        }
      }
    },
    kuakata: {
      budget: {
        en: {
          title: 'Kuakata — Budget Sun & Sea Beach',
          days: [
            { title: 'Day 1 · Dhaka → Patuakhali Launch Journey', activities: ['8:30 PM · Board triple-deck launch from Sadarghat (Deck seat: ৳350)', 'Sleep under starry skies on launch deck', '6:30 AM · Arrive Patuakhali ghat; local bus to Kuakata (৳120)', 'Check in at budget beach cottage (৳500/night)'] },
            { title: 'Day 2 · Gangamati Forest Sunrise & Red Crabs', activities: ['5:00 AM · Bike taxi to Gangamati beach for sunrise (৳150)', 'Spot colonies of red crabs at Gangamati Char', 'Breakfast at local beach shack — dim-porota & tea (৳50)', 'Sunset at main beach; local fish fry dinner (৳120)'] },
            { title: 'Day 3 · Buddhist Temples & Local Handloom', activities: ['9:00 AM · Walk to Misripara Buddhist Temple (giant Buddha statue)', 'Visit Rakhine handloom cottage workshops', '5:00 PM · Return bus to Patuakhali; board return launch to Dhaka'] }
          ]
        },
        bn: {
          title: 'কুয়াকাটা — বাজেট সূর্য ও সমুদ্র সৈকত',
          days: [
            { title: 'দিন ১ · ঢাকা → পটুয়াখালী লঞ্চ যাত্রা', activities: ['রাত ৮:৩০ · সদরঘাট থেকে ট্রিপল-ডেক লঞ্চ (ডেক টিকিট: ৳৩৫০)', 'লঞ্চের ডেকে তারার নিচে রাত্রিযাপন', 'সকাল ৬:৩০ · পটুয়াখালী পৌঁছানো; লোকাল বাসে কুয়াকাটা (৳১২০)', 'বিচের বাজেট কটেজে চেক-ইন (৳৫০০/রাত)'] },
            { title: 'দিন ২ · গঙ্গামতি বনে সূর্যোদয় ও লাল কাঁকড়া', activities: ['ভোর ৫:০০ · মোটরসাইকেল ট্যাক্সি নিয়ে গঙ্গামতিতে সূর্যোদয় দর্শন (৳১৫০)', 'গঙ্গামতির চরে লাল কাঁকড়ার দল দেখা', 'বিচের দোকানে সকালের নাস্তা — ডিম-পরোটা ও চা (৳৫০)', 'বিচে সূর্যাস্ত দর্শন; রাতে তাজা ভাজা মাছ দিয়ে ডিনার (৳১২০)'] },
            { title: 'দিন ৩ · বৌদ্ধ মন্দির ও রাখাইন তাঁত শিল্প', activities: ['সকাল ৯:০০ · মিশ্রিপাড়া বৌদ্ধ মন্দির (বৃহত্তম বুদ্ধ মূর্তি) পরিদর্শন', 'রাখাইন তাঁত কটেজে গিয়ে ঐতিহ্যবাহী বুনন দেখা', 'বিকেল ৫:০০ · বাসে পটুয়াখালী ফেরত; ফিরতি লঞ্চে আরোহণ'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Kuakata — 3-Day Comfort Coastal Tour',
          days: [
            { title: 'Day 1 · Dhaka → Patuakhali (AC Cabin Launch)', activities: ['8:30 PM · AC Single/Double Cabin on premium launch (৳1,200/cabin)', 'Arrive Patuakhali; reserved CNG to Kuakata resort (৳800 split)', 'Check in at Shikder Resort or similar (৳2,500/night)', 'Afternoon beach stroll; seafood dinner at beachside cafe (৳350)'] },
            { title: 'Day 2 · Fatrar Char Mangrove Forest Cruise', activities: ['8:00 AM · Reserved speedboat cruise to Fatrar Char (forest gate: ৳2,000 split)', 'Walk inside the eastern extensions of Sundarbans forest with guide', 'Picnic lunch on the boat (biryani & coconut water, ৳200)', 'Sunset at Jhabon (Casuarina forest) beach'] },
            { title: 'Day 3 · Sunrise beach & Rakhine Market Shopping', activities: ['5:00 AM · Hired tour motorcycle to Sunrise Point (৳300)', 'Visit Rakhine Market — buy local handloom shawls & dry fish', '3:00 PM · Return transfer to launch ghat; AC Cabin back to Dhaka'] }
          ]
        },
        bn: {
          title: 'কুয়াকাটা — ৩ দিনের কমফোর্ট কোস্টাল ট্যুর',
          days: [
            { title: 'দিন ১ · ঢাকা → পটুয়াখালী (এসি কেবিন লঞ্চ)', activities: ['রাত ৮:৩০ · প্রিমিয়াম লঞ্চে এসি সিঙ্গেল/ডাবল কেবিন বুকিং (৳১,২০০)', 'পটুয়াখালী ঘাট থেকে রিজার্ভ সিএনজিতে কুয়াকাটা রিসোর্ট (৳৮০০)', 'শিকদার রিসোর্টে চেক-ইন (৳২,৫০০/রাত)', 'বিচে ঘোরাঘুরি ও বিচসাইড ক্যাফেতে তাজা সিফুড ডিনার (৳৩৫০)', '📊 আনুমানিক বেস রেট: ৳৩,০০০–৳৪,২০০ জনপ্রতি'] },
            { title: 'দিন ২ · ফাতরার চর ম্যানগ্রোভ বন স্পিডবোট ক্রুজ', activities: ['সকাল ৮:০০ · ফাতরার চরে রিজার্ভ স্পিডবোটে ক্রুজ (৳২,০০০ ভাগাভাগি)', 'গাইডের সাথে সুন্দরবনের পূর্বাঞ্চলীয় ফাতরার বনে ট্রেইল', 'স্পিডবোটে পিকনিক লাঞ্চ (বিরিয়ানি ও ডাব, ৳২০০)', 'ঝাউবন বিচে সূর্যাস্ত ও লাল কাঁকড়া দর্শন'] },
            { title: 'দিন ৩ · সানরাইজ বিচ ও রাখাইন মার্কেট শপিং', activities: ['ভোর ৫:০০ · ভাড়া করা মোটরসাইকেলে সানরাইজ পয়েন্টে ভ্রমণ (৳৩০০)', 'রাখাইন মার্কেটে কেনাকাটা — শাল, বিছানার চাদর ও শুঁটকি', 'বিকেল ৩:০০ · পটুয়াখালী ঘাটে ফেরত; এসি কেবিনে ঢাকা ফিরতি যাত্রা'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Kuakata — Luxury Sunset Beach Retreat',
          days: [
            { title: 'Day 1 · Luxury AC SUV Transfer & 4-Star Stay', activities: ['Private AC luxury SUV from Dhaka via Padma Bridge (৳8,000 split)', 'Check in at premium suite in Shikder Resort & Villas (৳6,500/night)', 'Welcome mocktails, relax at the resort infinity pool', 'Fine-dining seafood platter on the resort terrace (৳1,200)'] },
            { title: 'Day 2 · Private Yacht Cruise & Helipad Stargazing', activities: ['Chartered private yacht cruise to Gangamati & Lebur Char (৳15,000/day)', 'Gourmet lunch prepared on board by personal chef', 'Late afternoon photography session on a secluded beach', 'Evening live music and BBQ steak dinner arranged at helipad'] },
            { title: 'Day 3 · Scenic Helipad Flight & Departure', activities: ['Optional scenic helicopter tour over Kuakata shoreline (৳20,000/run)', 'Spa & massage therapy at resort spa (৳2,500)', 'Farewell buffet lunch; private SUV back to Dhaka via Padma Bridge'] }
          ]
        },
        bn: {
          title: 'কুয়াকাটা — লাক্সারি সানসেট বিচ রিট্রিট',
          days: [
            { title: 'দিন ১ · লাক্সারি এসি SUV ট্রান্সফার ও ৪-স্টার রিসোর্ট', activities: ['পদ্মা সেতু দিয়ে ঢাকা থেকে সরাসরি লাক্সারি এসি SUV (৳৮,০০০ ভাগাভাগি)', 'শিকদার রিসোর্ট অ্যান্ড ভিলাসে প্রিমিয়াম সুইটে চেক-ইন (৳৬,৫০০/রাত)', 'ইনফিনিটি পুলে রিল্যাক্সেশন ও স্বাগত ড্রিংকস', 'রিসোর্টের টেরেসে ফাস্ট-ক্লাস সিফুড প্ল্যাটার ডিনার (৳১,২০০)'] },
            { title: 'দিন ২ · গঙ্গামতি ও লেবুর চরে ইয়ট ক্রুজ ও ডিনার', activities: ['গঙ্গামতি ও লেবুর চরে চ্যাটার্ড প্রাইভেট ইয়ট ক্রুজ (৳১৫,০০০/দিন)', 'ইয়টের ওপর পার্সোনাল শেফের তৈরি গুরমেট লাঞ্চ', 'secluded বিচে গোল্ডেন আওয়ারের প্রফেশনাল ফটোসেশন', 'হেলিপ্যাডে বিশেষ লাইভ মিউজিক ও বারবিকিউ স্টেক ডিনার'] },
            { title: 'দিন ৩ · হেলিকপ্টার সাইটসিয়িং ও ঢাকা প্রত্যাবর্তন', activities: ['ঐচ্ছিক কুয়াকাটা সৈকতের ওপর হেলিকপ্টার সাইটসিয়িং (৳২০,০০০)', 'রিসোর্ট স্পা-তে প্রিমিয়াম বডি মাসাজ (৳২,৫০০)', 'বিদায়ী রাজকীয় লাঞ্চ; প্রাইভেট SUV-তে পদ্মা সেতু হয়ে ঢাকা ফেরত'] }
          ]
        }
      }
    },
    kantajew: {
      budget: {
        en: {
          title: 'Kantajew & Dinajpur — Budget Cultural Tour',
          days: [
            { title: 'Day 1 · Dhaka → Dinajpur Train Journey', activities: ['9:50 AM · Board Ekota Express train from Kamalapur (Shovon: ৳390)', 'Arrive Dinajpur by 6:00 PM — check in at budget hotel near station (৳400)', 'Dinner at local hotel — traditional Dinajpuri beef curry (৳120)'] },
            { title: 'Day 2 · Terracotta Temple & Ancient Ramsagar', activities: ['7:30 AM · Rent local bicycle (৳80/day); ride to Ramsagar Lake park', 'Explore Ramsagar ancient man-made lake and mini zoo (entry: ৳20)', '1:30 PM · Cycle to Kantajew Temple (UNESCO listed terracotta marvel)', 'Sunset photo session at the temple gates; return cycle ride'] },
            { title: 'Day 3 · Nayabad Mosque & Train Return', activities: ['8:30 AM · Ride to historical Nayabad Mosque (Mughal masonry, free)', 'Taste traditional Dinajpuri doi and sweets at station', '1:00 PM · Board return train back to Dhaka (Ekota Express)'] }
          ]
        },
        bn: {
          title: 'কান্তজিউ ও দিনাজপুর — বাজেট সাংস্কৃতিক ট্যুর',
          days: [
            { title: 'দিন ১ · ঢাকা → দিনাজপুর ট্রেন যাত্রা', activities: ['সকাল ৯:৫০ · কমলাপুর থেকে একতা এক্সপ্রেস ট্রেন (শোভরন: ৳৩৯০)', 'সন্ধ্যা ৬:০০ টায় দিনাজপুর পৌঁছানো — স্টেশনের কাছে কটেজে চেক-ইন (৳৪০০)', 'রাতের খাবার: স্থানীয় হোটেলে ঐতিহ্যবাহী কালা ভুনা (৳১২০)'] },
            { title: 'দিন ২ · কান্তজিউ টেরাকোটা মন্দির ও রামসাগর', activities: ['সকাল ৭:৩০ · সাইকেল ভাড়া (৳৮০/দিন); রামসাগর লেক পার্কে রাইড', 'রামসাগর দীঘি ও মিনি চিড়িয়াখানা পরিদর্শন (প্রবেশ: ৳২০)', 'দুপুর ১:৩০ · কান্তজিউ মন্দিরে সাইকেল যাত্রা (বিখ্যাত টেরাকোটা স্থাপত্য)', 'মন্দিরের কারুকাজের ছবি তোলা; সাইকেলে শহরে ফেরত'] },
            { title: 'দিন ৩ · নয়াবাদ মসজিদ ও ঢাকা ফেরত', activities: ['সকাল ৮:৩০ · ঐতিহাসিক নয়াবাদ মসজিদ (মোগল স্থাপত্য, বিনামূল্যে)', 'স্টেশনের কাছে ঐতিহ্যবাহী দিনাজপুরী দই ও মিষ্টি টেস্ট', 'দুপুর ১:০০ · ফিরতি ট্রেনে ঢাকার উদ্দেশ্যে যাত্রা (একতা এক্সপ্রেস)'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Terracotta Wonders — Dinajpur Comfort Trip',
          days: [
            { title: 'Day 1 · Dhaka → Dinajpur (AC Train Snigdha)', activities: ['9:50 AM · AC Snigdha seat on Ekota Express (৳780) — comfortable ride', 'Arrive Dinajpur; reserved CNG to Hotel Diamond or similar (৳2,000/night)', 'Check-in, evening walk around Dinajpur Rajbari ruins', 'Traditional dinner at town center (traditional thali, ৳300)'] },
            { title: 'Day 2 · Guided Kantajew & Ramsagar VIP Tour', activities: ['8:30 AM · Hired reserved CNG for day trip (৳800)', 'Guided tour of Kantajew Temple with local historian (guide: ৳400)', 'Learn about Ramayana/Mahabharata terracotta panel carvings', 'Lunch at Ramsagar tourist motel; walk in the national park'] },
            { title: 'Day 3 · Traditional Rice Market & Departure', activities: ['9:00 AM · Visit Dinajpur rice mills — buy premium Kataribhog rice', 'Sample local special dessert: Dinajpur Chomchom', '1:00 PM · Board return AC Train to Dhaka'] }
          ]
        },
        bn: {
          title: 'টেরাকোটা বিস্ময় — দিনাজপুর কমফোর্ট ট্রিপ',
          days: [
            { title: 'দিন ১ · ঢাকা → দিনাজপুর (এসি ট্রেন স্নিগ্ধা)', activities: ['সকাল ৯:৫০ · একতা এক্সপ্রেসে এসি স্নিগ্ধা সিট (৳৭৮০) — আরামদায়ক ভ্রমণ', 'দিনাজপুর পৌঁছে ডায়মন্ড হোটেলে চেক-ইন (৳২,০০০/রাত)', 'বিকেলে দিনাজপুর রাজবাড়ী ধ্বংসাবশেষ ঘুরে দেখা', 'শহরের বিখ্যাত রেস্টুরেন্টে ঐতিহ্যবাহী পোলাও ও হাঁসের মাংস (৳৩০০)'] },
            { title: 'দিন ২ · গাইড সহ কান্তজিউ ও রামসাগর ভিআইপি ট্যুর', activities: ['সকাল ৮:৩০ · সারাদিনের জন্য রিজার্ভ সিএনজি ভাড়া (৳৮০০)', 'স্থানীয় ইতিহাসবিদের সাথে কান্তজিউ মন্দিরের বিশেষ ট্যুর (গাইড: ৳৪০০)', 'টেরাকোটার দেয়ালে খোদাই করা রামায়ণ-মহাভারতের কাহিনীর বিবরণ শোনা', 'রামসাগর পর্যটন মোটেলে লাঞ্চ; জাতীয় উদ্যান পরিদর্শন'] },
            { title: 'দিন ৩ · দিনাজপুরের চালের বাজার ও প্রস্থান', activities: ['সকাল ৯:০০ · দিনাজপুরের ধানের চালের বাজার পরিদর্শন — কাটারিভোগ চাল কেনা', 'দিনাজপুরের বিখ্যাত মিষ্টি ও চমচম টেস্টিং', 'দুপুর ১:০০ · ফিরতি এসি ট্রেনে ঢাকার উদ্দেশ্যে রওয়ানা'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Royal Terracotta — Dinajpur Heritage Retreat',
          days: [
            { title: 'Day 1 · Saidpur Flight & Luxury Resort Stay', activities: ['11:00 AM · Flight Dhaka to Saidpur (Novoair, ৳4,500)', 'Private luxury AC SUV Saidpur to Dinajpur palace resort (৳4,000)', 'Stay at heritage royal suite; pool side tea tasting', 'Traditional 5-course Dinajpur Zamindari dinner (৳1,500)'] },
            { title: 'Day 2 · Archaeologist VIP Kantajew Tour & Ramsagar Picnic', activities: ['Private archaeologist guide for Kantajew Temple detailed study (৳2,500)', 'Terracotta preservation demonstration by department of archaeology', 'Gourmet picnic lunch spread at Ramsagar Lake VIP cottage', 'Sunset photography and drone session near Dhepa River'] },
            { title: 'Day 3 · Litchi/Mango Orchard VIP Tour & Return', activities: ['Morning private tour of premium local fruit orchards (seasonal)', 'Souvenir Kataribhog rice & Litchi gift box assembly', 'Farewell brunch at resort; private AC transfer to Saidpur airport for flight'] }
          ]
        },
        bn: {
          title: 'রয়্যাল টেরাকোটা — দিনাজপুর হেরিটেজ রিট্রিট',
          days: [
            { title: 'দিন ১ · সৈয়দপুরে ফ্লাইট ও লাক্সারি রিসোর্ট স্টে', activities: ['সকাল ১১:০০ · ঢাকা থেকে সৈয়দপুরে ফ্লাইট (৳৪,৫০০)', 'সৈয়দপুর থেকে দিনাজপুরের হেরিটেজ রাজপ্রাসাদ রিসোর্টে লাক্সারি SUV (৳৪,০০০)', 'ঐতিহ্যবাহী রয়্যাল সুইটে চেক-ইন; পুল সাইডে চায়ের আসর', 'রিসোর্টে রাজকীয় ৫-কোর্স দিনাজপুরী ডিনার (৳১,৫০০)'] },
            { title: 'দিন ২ · প্রত্নতত্ত্ববিদ গাইড সহ কান্তজিউ ও রামসাগরে পিকনিক', activities: ['কান্তজিউ মন্দিরের নিখুঁত বিবরণীর জন্য প্রত্নতত্ত্ববিদ গাইড (৳২,৫০০)', 'প্রত্নতত্ত্ব বিভাগের কর্মকর্তাদের সাথে টেরাকোটা সংস্কার প্রদর্শনী', 'রামসাগর লেকের ভিআইপি রেস্ট হাউসে গুরমেট পিকনিক লাঞ্চ', 'ঢেপা নদীর পাড়ে সানসেট ড্রোন ও প্রফেশনাল ফটোসেশন'] },
            { title: 'দিন ৩ · লিচু/আম বাগান ভিআইপি ট্যুর ও প্রত্যাবর্তন', activities: ['সকালে দিনাজপুরের বিখ্যাত লিচু/আম বাগান পরিদর্শন (মৌসুমী)', 'সরণী হিসেবে প্রিমিয়াম কাটারিভোগ চাল ও লিচুর উপহার সামগ্রী সংগ্রহ', 'রিসোর্টে রাজকীয় ব্রাঞ্চ; বিমানে ঢাকা ফিরতে সৈয়দপুর এয়ারপোর্টে ট্রান্সফার'] }
          ]
        }
      }
    },
    birishiri: {
      budget: {
        en: {
          title: 'Birishiri Clay Hills — Budget Backpacker Trek',
          days: [
            { title: 'Day 1 · Dhaka → Jharia → Durgapur', activities: ['7:30 AM · Jharia local train from Kamalapur (৳120)', 'Arrive Jharia by noon; local shared auto to Durgapur (৳80)', 'Cross the Someshwari River on shared boat (৳20)', 'Stay at budget Garo tribal homestay in Durgapur (৳350/night)'] },
            { title: 'Day 2 · Pink Ceramic Hills & Blue Lake Trek', activities: ['7:00 AM · Rent local rickshaw for clay hills trail (৳250/day)', 'Trek to China Clay Hills (pinkish soil formation) & blue water lake', 'Hike up to Ranikhong Church overlooking Indian border hills', 'Lunch: simple tribal meal — bamboo shoot chicken & rice (৳100)'] },
            { title: 'Day 3 · Garo Museum & Mymensingh Return', activities: ['9:00 AM · Visit Birishiri Garo Cultural Academy (museum, free)', 'Buy indigenous handloom fabrics from local Garo women weavers', '2:00 PM · Local auto to Jharia; board train back to Dhaka'] }
          ]
        },
        bn: {
          title: 'বিরিশিরি চীনামাটির পাহাড় — বাজেট ব্যাকপ্যাকার ট্রেক',
          days: [
            { title: 'দিন ১ · ঢাকা → জারিয়া → দুর্গাপুর', activities: ['সকাল ৭:৩০ · ঢাকা থেকে জারিয়াগামী লোকাল ট্রেন (৳১২০)', 'দুপুরে জারিয়া পৌঁছে শেয়ারড অটোতে সুসং দুর্গাপুর (৳৮০)', 'শেয়ারড নৌকায় স্বচ্ছ পানির সোমেশ্বরী নদী পারাপার (৳২০)', 'দুর্গাপুরে গারো উপজাতীয় হোমস্টেতে চেক-ইন (৳৩৫০/রাত)'] },
            { title: 'দিন ২ · গোলাপী চীনামাটির পাহাড় ও নীল হ্রদ ট্রেক', activities: ['সকাল ৭:০০ · মাটির পাহাড় ও ট্রেইলে যেতে লোকাল রিকশা ভাড়া (৳২৫০/দিন)', 'চীনামাটির পাহাড় ও নীল পানির লেকে চমৎকার ট্র্যাকিং সেশন', 'ভারতীয় সীমান্ত সংলগ্ন পাহাড়ের চূড়ায় রানীখং চার্চে হাইক', 'লাঞ্চ: উপজাতীয় ঐতিহ্যবাহী বাঁশ মুরগি ও ভাত (৳১০০)'] },
            { title: 'দিন ৩ · গারো একাডেমি ও ঢাকা প্রত্যাবর্তন', activities: ['সকাল ৯:০০ · বিরিশিরি ক্ষুদ্র নৃ-গোষ্ঠী কালচারাল একাডেমি পরিদর্শন', 'গারো নারীদের বোনা ঐতিহ্যবাহী পোশাক ও শাল কেনাকাটা', 'দুপুর ২:০০ · অটোতে জারিয়া স্টেশন; ট্রেনে ঢাকা ফিরতি যাত্রা'] }
          ]
        }
      },
      mid: {
        en: {
          title: 'Birishiri Clay Hills — 3-Day Comfort Trek',
          days: [
            { title: 'Day 1 · Dhaka → Durgapur (Private CNG/Car)', activities: ['8:00 AM · Hired private CNG/micro from Dhaka (৳3,000 split)', 'Arrive Durgapur; check in at YWCA Guest House (৳1,500/night)', 'Walk along Someshwari dry riverbed; scenic evening tea', 'Dinner: local river fish curry and bhorta thali (৳250)'] },
            { title: 'Day 2 · China Clay Lake & Boat Safari', activities: ['8:30 AM · Reserved engine boat on Someshwari River (৳1,500 split)', 'Visit pink clay hills, white clay formations & blue-green lake', 'Guide walk around Ranikhong historical missionary hill (guide: ৳300)', 'Lunch at YWCA canteen — local organic vegetables and chicken'] },
            { title: 'Day 3 · Garo Cultural Trail & Return', activities: ['9:30 AM · Cultural tour of Garo villages — study lifestyle & weavers', 'Visit BGB check post at border trail (Bijoypur)', '3:00 PM · Return transfer back to Dhaka'] }
          ]
        },
        bn: {
          title: 'বিরিশিরি চীনামাটির পাহাড় — ৩ দিনের কমফোর্ট ট্রেক',
          days: [
            { title: 'দিন ১ · ঢাকা → দুর্গাপুর (প্রাইভেট কার/সিএনজি)', activities: ['সকাল ৮:০০ · ঢাকা থেকে সরাসরি রিজার্ভ সিএনজি/মাইক্রো (৳৩,০০০ ভাগাভাগি)', 'দুর্গাপুর পৌঁছে ওয়াইডব্লিউসিএ (YWCA) গেস্ট হাউসে চেক-ইন (৳১,৫০০/রাত)', 'বিকেলে বালুময় সোমেশ্বরী নদীর চরে ওয়াক ও সূর্যাস্ত দর্শন', 'রাতের খাবার: নদীর তাজা মাছ ও বিভিন্ন পদের ভর্তা (৳২৫০)'] },
            { title: 'দিন ২ · চীনামাটির লেক ও ইঞ্জিন বোট সাফারি', activities: ['সকাল ৮:৩০ · সোমেশ্বরী নদীতে রিজার্ভ ইঞ্জিন বোট সফর (৳১,৫০০)', 'সাদা ও গোলাপী মাটির পাহাড় এবং নয়নাভিরাম নীল জলের লেক ভ্রমণ', 'ঐতিহাসিক রানীখং মিশনারী পাহাড়ে গাইডেড ট্রেইল ওয়াক (গাইড: ৳৩০০)', 'YWCA ক্যান্টিনে দুপুরের খাবার — অর্গানিক শাকসবজি ও দেশী মুরগি'] },
            { title: 'দিন ৩ · গারো কালচারাল ট্রেইল ও প্রত্যাবর্তন', activities: ['সকাল ৯:৩০ · গারো আদিবাসী গ্রামে তাঁতি ও লাইফস্টাইল দেখতে বিশেষ ট্রেইল', 'বিজয়পুরে বাংলাদেশ সীমান্ত ও বিজিবি চেকপোস্ট পরিদর্শন', 'বিকেল ৩:০০ · প্রাইভেট গাড়িতে ঢাকার উদ্দেশ্যে যাত্রা'] }
          ]
        }
      },
      premium: {
        en: {
          title: 'Scenic Birishiri — Premium Nature Escape',
          days: [
            { title: 'Day 1 · Private AC Microbus & Premium Eco Resort', activities: ['9:00 AM · Pick-up in private AC Microbus from Dhaka (৳8,000)', 'Arrive Durgapur; check in at premium riverfront cottage resort', 'Welcome tribal juice, relax at the private river deck', 'Premium barbecue dinner with indigenous local spices (৳1,000)'] },
            { title: 'Day 2 · Private SUV Clay Hills Tour & Someshwari Cruise', activities: ['Private 4WD SUV hire for off-road clay hills exploration (৳4,000)', 'Chartered premium boat cruise on Someshwari River with refreshments', 'Scenic picnic lunch at China Clay Lake view deck', 'VIP Garo Cultural Academy visit & custom dance showcase (৳3,000)'] },
            { title: 'Day 3 · Border Viewpoint & Luxury Return Transfer', activities: ['Morning scenic walk at Bijoypur border hills with security guide', 'Check-out; gift box of Garo handloom and organic honey', 'Return AC transfer to Dhaka with luxury mid-route lunch'] }
          ]
        },
        bn: {
          title: 'অনিন্দ্য বিরিশিরি — প্রিমিয়াম নেচার এস্কেপ',
          days: [
            { title: 'দিন ১ · প্রাইভেট এসি মাইক্রোবাস ও রিভারভিউ রিসোর্ট', activities: ['সকাল ৯:০০ · ঢাকা থেকে লাক্সারি এসি মাইক্রোবাসে সরাসরি যাত্রা (৳৮,০০০)', 'দুর্গাপুরে প্রিমিয়াম রিভারফ্রন্ট ইকো-রিসোর্টে চেক-ইন', 'স্বাগত উপজাতীয় জুস ও বিকেলের চায়ের আসর', 'রিসোর্টের টেরেসে আদিবাসী রেসিপিতে স্পেশাল বারবিকিউ ডিনার (৳১,০০০)'] },
            { title: 'দিন ২ · ৪WD জিপে চীনামাটির পাহাড় ও সোমেশ্বরী ক্রুজ', activities: ['চীনামাটির পাহাড়ে অফ-রোড রাইডের জন্য ৪WD জিপ (৳৪,০০০)', 'সোমেশ্বরী নদীতে প্রিমিয়াম রিফ্রেশমেন্ট ও স্ন্যাক্স সহ বোট ক্রুজ', 'চীনামাটির নীল লেকের ভিউ ডেক এ চমৎকার দুপুরের লাঞ্চ', 'ক্ষুদ্র নৃ-গোষ্ঠী একাডেমিতে বিশেষ গারো নৃত্য পরিবেশনা (৳৩,০০০)'] },
            { title: 'দিন ৩ · সীমান্ত ভিউপয়েন্ট ও ঢাকা প্রত্যাবর্তন', activities: ['সকালে নিরাপত্তা গাইডের সাথে বিজয়পুর সীমান্ত পাহাড় ভ্রমণ', 'চেক-আউট; সরণী হিসেবে গারো তাঁত ও বুনন সামগ্রী সংগ্রহ', 'লাক্সারি এসি মাইক্রোবাসে ঢাকা প্রত্যাবর্তন (মাঝপথে চমৎকার লাঞ্চ)'] }
          ]
        }
      }
    }
  };

  // Budget budget labels for the meta line
  const budgetLabels = {
    en: { budget: 'Budget / Backpacker', mid: 'Mid-range / Comfort', premium: 'Premium / Luxury' },
    bn: { budget: 'বাজেট / ব্যাকপ্যাকার', mid: 'মিড-রেঞ্জ / কমফোর্ট', premium: 'প্রিমিয়াম / লাক্সারি' }
  };

  const groupLabels = {
    en: { solo: 'Solo', couple: 'Couple', small: 'Small Group', large: 'Large Group' },
    bn: { solo: 'একা', couple: 'কাপল', small: 'ছোট গ্রুপ', large: 'বড় গ্রুপ' }
  };

  // Typewriter engine — renders HTML DOM nodes char-by-char
  let typewriterTimer = null;

  function runTypewriter(container, days) {
    if (typewriterTimer) clearInterval(typewriterTimer);
    container.innerHTML = '';

    // Build all DOM nodes first (hidden), then reveal char-by-char per text node
    const allChars = [];

    days.forEach(day => {
      const dayDiv = document.createElement('div');
      dayDiv.className = 'itinerary-day';
      container.appendChild(dayDiv);

      const titleEl = document.createElement('div');
      titleEl.className = 'itinerary-day-title';
      dayDiv.appendChild(titleEl);

      const ul = document.createElement('ul');
      ul.className = 'itinerary-activities';
      dayDiv.appendChild(ul);

      // Queue title chars
      day.title.split('').forEach(ch => allChars.push({ el: titleEl, ch }));
      allChars.push({ el: null, ch: null, newline: true }); // spacing pause

      day.activities.forEach(act => {
        const li = document.createElement('li');
        ul.appendChild(li);
        act.split('').forEach(ch => allChars.push({ el: li, ch }));
        allChars.push({ el: null, ch: null, newline: true });
      });
    });

    // Add blinking cursor to container
    const cursor = document.createElement('span');
    cursor.className = 'planner-typewriter-cursor';
    container.appendChild(cursor);

    let i = 0;
    const speed = 8; // ms per char

    typewriterTimer = setInterval(() => {
      if (i >= allChars.length) {
        clearInterval(typewriterTimer);
        cursor.remove();
        return;
      }
      const item = allChars[i];
      if (item.el) {
        item.el.textContent += item.ch;
        // Keep scrolled to bottom
        container.scrollTop = container.scrollHeight;
      }
      i++;
    }, speed);
  }

  const generateBtn = document.getElementById('generate-plan-btn');
  const plannerIdle = document.getElementById('planner-idle');
  const plannerResult = document.getElementById('planner-result');
  const plannerTitle = document.getElementById('planner-title');
  const plannerMeta  = document.getElementById('planner-meta');
  const plannerTypewriter = document.getElementById('planner-typewriter');

  const destBaseRates = {
    sajek: { budget: [3000, 4000], mid: [7000, 9500], premium: [16000, 22000] },
    sundarbans: { budget: [4000, 5500], mid: [9000, 13000], premium: [26000, 42000] },
    sreemangal: { budget: [2000, 2800], mid: [5000, 7000], premium: [19000, 29000] },
    bandarban: { budget: [3200, 4800], mid: [7500, 11000], premium: [32000, 52000] },
    dhaka: { budget: [800, 1200], mid: [2000, 3000], premium: [6000, 9000] },
    paharpur: { budget: [2200, 3000], mid: [5500, 7500], premium: [14000, 20000] },
    kuakata: { budget: [3000, 4200], mid: [7000, 10000], premium: [18000, 26000] },
    kantajew: { budget: [2400, 3200], mid: [6000, 8000], premium: [15000, 22000] },
    birishiri: { budget: [1800, 2600], mid: [4500, 6000], premium: [12000, 18000] }
  };

  const groupConfig = {
    solo: { count: 1, mult: 1.4 },
    couple: { count: 2, mult: 1.0 },
    small: { count: 4, mult: 0.85 },
    large: { count: 8, mult: 0.75 }
  };

  if (generateBtn) {
    generateBtn.addEventListener('click', () => {
      const dest   = document.getElementById('planner-destination').value;
      const group  = document.getElementById('planner-group').value;
      const budget = document.getElementById('planner-budget').value;

      // Fetch data — use budget as primary axis; group just affects meta label
      const destData = itineraryData[dest];
      if (!destData) return;
      const budgetData = destData[budget] || destData['mid'];
      const plan = budgetData[currentLang] || budgetData['en'];

      // Show loading state briefly
      generateBtn.classList.add('loading');
      generateBtn.querySelector('span').textContent =
        currentLang === 'bn' ? 'তৈরি হচ্ছে...' : 'Generating...';

      setTimeout(() => {
        generateBtn.classList.remove('loading');
        generateBtn.querySelector('span').textContent =
          currentLang === 'bn' ? 'ইটিনেরারি তৈরি করুন' : 'Generate Itinerary';

        // Dynamic budget calculation based on realistic cost structures
        const base = destBaseRates[dest]?.[budget] || [2000, 3000];
        const cfg = groupConfig[group] || { count: 4, mult: 0.85 };
        const minPerPerson = Math.round(base[0] * cfg.mult);
        const maxPerPerson = Math.round(base[1] * cfg.mult);
        const minTotal = minPerPerson * cfg.count;
        const maxTotal = maxPerPerson * cfg.count;

        let budgetText = '';
        if (currentLang === 'en') {
          if (group === 'solo') {
            budgetText = `Total: ৳${minTotal.toLocaleString()} - ৳${maxTotal.toLocaleString()}`;
          } else {
            budgetText = `Total: ৳${minTotal.toLocaleString()} - ৳${maxTotal.toLocaleString()} (৳${minPerPerson.toLocaleString()} - ৳${maxPerPerson.toLocaleString()}/person)`;
          }
        } else {
          if (group === 'solo') {
            budgetText = `মোট: ৳${toBengaliNumbers(minTotal.toLocaleString())} - ৳${toBengaliNumbers(maxTotal.toLocaleString())}`;
          } else {
            budgetText = `মোট: ৳${toBengaliNumbers(minTotal.toLocaleString())} - ৳${toBengaliNumbers(maxTotal.toLocaleString())} (৳${toBengaliNumbers(minPerPerson.toLocaleString())} - ৳${toBengaliNumbers(maxPerPerson.toLocaleString())}/জন)`;
          }
        }

        // Update header
        plannerTitle.textContent = plan.title;
        const gLabel = groupLabels[currentLang][group];
        const bLabel = budgetLabels[currentLang][budget];
        plannerMeta.textContent = `${gLabel} · ${bLabel} · ${budgetText}`;

        // Switch visibility
        plannerIdle.style.display = 'none';
        plannerResult.style.display = 'flex';

        // Run typewriter
        runTypewriter(plannerTypewriter, plan.days);
      }, 900);
    });
  }

  // ===========================================================================
  // 13. EXPLORER XP CHALLENGE TRACKER
  // ===========================================================================

  let totalXP = 0;

  const xpTierThresholds = [
    { key: 'unverified', minXP: 0,   maxXP: 49,  icon: 'fa-user-xmark',  class: '',              nameEn: 'Unverified',      nameBn: 'আনভেরিফাইড' },
    { key: 'explorer',   minXP: 50,  maxXP: 149, icon: 'fa-compass',      class: 'tier-explorer', nameEn: 'Explorer',        nameBn: 'এক্সপ্লোরার' },
    { key: 'trusted',    minXP: 150, maxXP: 299, icon: 'fa-shield-check',  class: 'tier-trusted',  nameEn: 'Trusted Explorer',nameBn: 'ট্রাস্টেড এক্সপ্লোরার' },
    { key: 'pioneer',    minXP: 300, maxXP: 999, icon: 'fa-award',         class: 'tier-pioneer',  nameEn: 'Pioneer',         nameBn: 'পায়োনিয়ার' }
  ];

  const milestoneMap = {
    'milestone-explorer': 50,
    'milestone-trusted': 150,
    'milestone-pioneer': 300
  };

  function getCurrentTier(xp) {
    let tier = xpTierThresholds[0];
    xpTierThresholds.forEach(t => { if (xp >= t.minXP) tier = t; });
    return tier;
  }

  function updateXPUI() {
    const tier = getCurrentTier(totalXP);
    const nextTier = xpTierThresholds.find(t => t.minXP > totalXP);

    // Badge icon and tier name
    const iconEl = document.getElementById('xp-tier-icon');
    const nameEl = document.getElementById('xp-tier-name');
    if (iconEl && nameEl) {
      iconEl.className = `xp-tier-icon ${tier.class}`;
      iconEl.innerHTML = `<i class="fa-solid ${tier.icon}"></i>`;
      nameEl.textContent = currentLang === 'bn' ? tier.nameBn : tier.nameEn;
    }

    // XP bar
    const barFill  = document.getElementById('xp-bar-fill');
    const barValue = document.getElementById('xp-bar-value');
    const nextLabel = document.getElementById('xp-next-label');

    if (nextTier) {
      const rangeStart = tier.minXP;
      const rangeEnd   = nextTier.minXP;
      const pct = Math.min(100, ((totalXP - rangeStart) / (rangeEnd - rangeStart)) * 100);
      if (barFill) barFill.style.width = pct + '%';
      if (barValue) {
        const xpStr    = currentLang === 'bn' ? toBengaliNumbers(totalXP) : totalXP;
        const maxStr   = currentLang === 'bn' ? toBengaliNumbers(nextTier.minXP) : nextTier.minXP;
        barValue.textContent = `${xpStr} / ${maxStr} XP`;
      }
      if (nextLabel) {
        const nextName = currentLang === 'bn' ? nextTier.nameBn : nextTier.nameEn;
        const needed   = nextTier.minXP - totalXP;
        const neededStr= currentLang === 'bn' ? toBengaliNumbers(needed) : needed;
        nextLabel.textContent = currentLang === 'bn'
          ? `${nextName} টায়ার আনলক করতে আরও ${neededStr} XP দরকার!`
          : `${neededStr} more XP to unlock ${nextName} tier!`;
      }
    } else {
      if (barFill) barFill.style.width = '100%';
      if (barValue) barValue.textContent = currentLang === 'bn' ? `${toBengaliNumbers(totalXP)} XP` : `${totalXP} XP`;
      if (nextLabel) nextLabel.textContent = currentLang === 'bn' ? '🎉 সর্বোচ্চ পায়োনিয়ার টায়ার অর্জিত!' : '🎉 Max Pioneer tier achieved!';
    }

    // Milestones
    Object.entries(milestoneMap).forEach(([id, threshold]) => {
      const el = document.getElementById(id);
      if (el) {
        if (totalXP >= threshold) {
          el.classList.add('unlocked');
          el.querySelector('i').className = 'fa-solid fa-check';
        } else {
          el.classList.remove('unlocked');
          el.querySelector('i').className = 'fa-solid fa-lock';
        }
      }
    });
  }

  // Wire up challenge checkboxes
  const challengeItems = document.querySelectorAll('.challenge-item');
  challengeItems.forEach(item => {
    const checkbox = item.querySelector('.challenge-checkbox');
    const xpReward = parseInt(item.getAttribute('data-xp')) || 0;

    if (!checkbox) return;

    checkbox.addEventListener('change', () => {
      const prevTier = getCurrentTier(totalXP).key;

      if (checkbox.checked) {
        totalXP += xpReward;
        item.classList.add('completed');
      } else {
        totalXP = Math.max(0, totalXP - xpReward);
        item.classList.remove('completed');
      }

      updateXPUI();

      // Level-up flash animation
      const newTier = getCurrentTier(totalXP).key;
      if (newTier !== prevTier) {
        const iconEl = document.getElementById('xp-tier-icon');
        if (iconEl) {
          iconEl.classList.remove('levelup-flash');
          void iconEl.offsetWidth; // reflow to restart animation
          iconEl.classList.add('levelup-flash');
          setTimeout(() => iconEl.classList.remove('levelup-flash'), 800);
        }
      }
    });
  });

  // Reset button
  const xpResetBtn = document.getElementById('xp-reset-btn');
  if (xpResetBtn) {
    xpResetBtn.addEventListener('click', () => {
      totalXP = 0;
      challengeItems.forEach(item => {
        item.classList.remove('completed');
        const cb = item.querySelector('.challenge-checkbox');
        if (cb) cb.checked = false;
      });
      updateXPUI();
    });
  }

  // Initialize XP UI
  updateXPUI();

  // ===========================================================================
  // 14. GUIDE MARKETPLACE FILTER
  // ===========================================================================

  const filterBtns = document.querySelectorAll('.mkt-filter-btn');
  const guideCards = document.querySelectorAll('.guide-card');

  filterBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      filterBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      const filter = btn.getAttribute('data-filter');

      guideCards.forEach(card => {
        const tags = (card.getAttribute('data-tags') || '').split(' ');
        if (filter === 'all' || tags.includes(filter)) {
          card.classList.remove('hidden');
        } else {
          card.classList.add('hidden');
        }
      });
    });
  });

  // ===========================================================================
  // 15. EXTEND LANGUAGE TOGGLE — translate new select options & dynamic fields
  // ===========================================================================

  // Extend existing lang-toggle to also translate select option text
  const origLangToggle = document.getElementById('lang-toggle');
  if (origLangToggle) {
    // Wrap click to also translate selects & xp UI
    origLangToggle.addEventListener('click', () => {
      // Translate planner select options
      document.querySelectorAll('.planner-select option[data-en]').forEach(opt => {
        opt.textContent = currentLang === 'bn' ? opt.getAttribute('data-bn') : opt.getAttribute('data-en');
      });
      // Re-render xp bar text with new lang
      updateXPUI();
      // Re-render marketplace filter button text
      filterBtns.forEach(btn => {
        const span = btn.querySelector('.lang-text');
        if (span) {
          span.textContent = currentLang === 'bn' ? span.getAttribute('data-bn') : span.getAttribute('data-en');
        }
      });
      // Re-translate challenge items
      document.querySelectorAll('.challenge-category-label[data-en], .challenge-name[data-en], .challenge-desc[data-en]').forEach(el => {
        el.textContent = currentLang === 'bn' ? el.getAttribute('data-bn') : el.getAttribute('data-en');
      });
    });
  }

  // Also update nav to include new section links
  const navLinks = document.querySelector('.nav-links');
  if (navLinks && !document.getElementById('nav-link-planner')) {
    const links = [
      { id: 'nav-link-planner',     href: '#ai-planner',   en: 'AI Planner', bn: 'এআই প্ল্যানার' },
      { id: 'nav-link-challenges',  href: '#xp-challenges', en: 'Challenges', bn: 'চ্যালেঞ্জ' },
      { id: 'nav-link-marketplace', href: '#marketplace',   en: 'Marketplace', bn: 'মার্কেটপ্লেস' }
    ];
    links.forEach(link => {
      const a = document.createElement('a');
      a.id = link.id;
      a.href = link.href;
      a.className = 'lang-text';
      a.setAttribute('data-en', link.en);
      a.setAttribute('data-bn', link.bn);
      a.textContent = link.en;
      navLinks.appendChild(a);
    });
  }

});

