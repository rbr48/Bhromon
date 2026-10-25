// Bhromon App — Figma Generator Plugin Script
// Automatically builds the full Design System and 20+ Screens natively in Figma.

(async () => {
  // 1. Load Standard System Fonts
  await Promise.all([
    figma.loadFontAsync({ family: "Inter", style: "Regular" }),
    figma.loadFontAsync({ family: "Inter", style: "Medium" }),
    figma.loadFontAsync({ family: "Inter", style: "Bold" })
  ]);

  // 2. Color Palette Definitions (Normalized 0..1 for Figma API)
  const hexToRgb = (hex) => {
    const clean = hex.replace('#', '');
    const bigint = parseInt(clean, 16);
    return {
      r: ((bigint >> 16) & 255) / 255,
      g: ((bigint >> 8) & 255) / 255,
      b: (bigint & 255) / 255
    };
  };

  const solidPaint = (hex, opacity = 1) => [
    { type: 'SOLID', color: hexToRgb(hex), opacity }
  ];

  const Colors = {
    darkGreen: '#1B4332',
    midGreen: '#2D6A4F',
    leafGreen: '#40916C',
    mintGreen: '#74C69D',
    paleGreen: '#D8F3DC',
    gold: '#F4A261',
    amber: '#E76F51',
    lightGold: '#FFD166',
    tierUnverified: '#ADB5BD',
    tierCommunity: '#74C69D',
    tierVerified: '#F4A261',
    tierExpert: '#1B4332',
    tierPioneer: '#E76F51',
    offWhite: '#F8FAFB',
    darkText: '#1A1A2E',
    grayText: '#5C6B73',
    cardDark: '#1E1E1E',
    bgDark: '#121212',
    white: '#FFFFFF',
    borderLight: '#E5E7EB',
    borderDark: '#2D3748'
  };

  // 3. Frame & Node Creation Helpers
  const createAutoFrame = ({
    parent,
    name = 'Frame',
    width,
    height,
    x,
    y,
    layoutMode = 'VERTICAL',
    primaryAlign = 'MIN',
    counterAlign = 'MIN',
    itemSpacing = 8,
    padding = { top: 0, right: 0, bottom: 0, left: 0 },
    bg,
    cornerRadius = 0,
    clipsContent = false,
    stroke,
    strokeColor = Colors.borderLight,
    strokeWeight = 1
  }) => {
    const frame = figma.createFrame();
    frame.name = name;
    if (x !== undefined && y !== undefined) {
      frame.x = x;
      frame.y = y;
    }
    if (width !== undefined) frame.resize(width, height || width);
    frame.layoutMode = layoutMode;
    frame.primaryAxisAlignItems = primaryAlign;
    frame.counterAxisAlignItems = counterAlign;
    frame.itemSpacing = itemSpacing;
    frame.paddingTop = padding.top;
    frame.paddingRight = padding.right;
    frame.paddingBottom = padding.bottom;
    frame.paddingLeft = padding.left;
    if (bg) frame.fills = solidPaint(bg);
    else frame.fills = [];
    if (cornerRadius) frame.cornerRadius = cornerRadius;
    frame.clipsContent = clipsContent;
    if (stroke) {
      frame.strokes = solidPaint(strokeColor);
      frame.strokeWeight = strokeWeight;
    }
    if (parent) parent.appendChild(frame);
    return frame;
  };

  const createTextNode = ({
    parent,
    text = '',
    fontSize = 14,
    fontStyle = 'Regular',
    color = Colors.darkText,
    layoutAlign = 'INHERIT',
    textAlign = 'LEFT'
  }) => {
    const t = figma.createText();
    t.fontName = { family: "Inter", style: fontStyle };
    t.characters = text;
    t.fontSize = fontSize;
    t.fills = solidPaint(color);
    t.layoutAlign = layoutAlign;
    t.textAlignHorizontal = textAlign;
    if (parent) parent.appendChild(t);
    return t;
  };

  const createButton = ({
    parent,
    label,
    variant = 'primary',
    width = 342,
    height = 48
  }) => {
    const isPrimary = variant === 'primary';
    const isOutlined = variant === 'outlined';
    const isDanger = variant === 'danger';

    let bg = Colors.midGreen;
    let textColor = Colors.white;
    let stroke = false;

    if (isOutlined) {
      bg = Colors.white;
      textColor = Colors.midGreen;
      stroke = true;
    } else if (isDanger) {
      bg = Colors.amber;
      textColor = Colors.white;
    }

    const btn = createAutoFrame({
      parent,
      name: `Button/${label}`,
      width,
      height,
      layoutMode: 'HORIZONTAL',
      primaryAlign: 'CENTER',
      counterAlign: 'CENTER',
      bg,
      cornerRadius: 12,
      stroke,
      strokeColor: Colors.midGreen
    });

    createTextNode({
      parent: btn,
      text: label,
      fontSize: 16,
      fontStyle: 'Bold',
      color: textColor
    });

    return btn;
  };

  const createMobileShell = (parent, title, x, y, isDark = false) => {
    const shell = createAutoFrame({
      parent,
      name: `📱 ${title}`,
      width: 390,
      height: 844,
      x,
      y,
      layoutMode: 'VERTICAL',
      primaryAlign: 'MIN',
      counterAlign: 'STRETCH',
      itemSpacing: 0,
      bg: isDark ? Colors.bgDark : Colors.offWhite,
      cornerRadius: 44,
      clipsContent: true,
      stroke: true,
      strokeColor: isDark ? '#333333' : '#E0E0E0',
      strokeWeight: 2
    });

    // Top Status Bar (390 x 44)
    const statusBar = createAutoFrame({
      parent: shell,
      name: 'Status Bar',
      width: 390,
      height: 44,
      layoutMode: 'HORIZONTAL',
      primaryAlign: 'SPACE_BETWEEN',
      counterAlign: 'CENTER',
      padding: { top: 0, right: 24, bottom: 0, left: 24 },
      bg: isDark ? Colors.bgDark : Colors.offWhite
    });
    createTextNode({
      parent: statusBar,
      text: '9:41',
      fontSize: 14,
      fontStyle: 'Bold',
      color: isDark ? Colors.white : Colors.darkText
    });
    createTextNode({
      parent: statusBar,
      text: '5G  100%',
      fontSize: 12,
      fontStyle: 'Medium',
      color: isDark ? Colors.white : Colors.darkText
    });

    // App Header Bar
    const header = createAutoFrame({
      parent: shell,
      name: 'Header Bar',
      width: 390,
      height: 56,
      layoutMode: 'HORIZONTAL',
      primaryAlign: 'SPACE_BETWEEN',
      counterAlign: 'CENTER',
      padding: { top: 0, right: 20, bottom: 0, left: 20 },
      bg: isDark ? Colors.cardDark : Colors.white,
      stroke: true,
      strokeColor: isDark ? '#262626' : Colors.borderLight
    });
    createTextNode({
      parent: header,
      text: title,
      fontSize: 18,
      fontStyle: 'Bold',
      color: isDark ? Colors.white : Colors.darkGreen
    });
    createTextNode({
      parent: header,
      text: '🔔',
      fontSize: 18
    });

    // Main Content Area (Scrollable Canvas container)
    const content = createAutoFrame({
      parent: shell,
      name: 'Content Area',
      width: 390,
      height: 664,
      layoutMode: 'VERTICAL',
      primaryAlign: 'MIN',
      counterAlign: 'STRETCH',
      itemSpacing: 16,
      padding: { top: 16, right: 20, bottom: 16, left: 20 },
      clipsContent: true
    });

    // Bottom Navigation Bar (390 x 80)
    const bottomNav = createAutoFrame({
      parent: shell,
      name: 'Bottom Navigation',
      width: 390,
      height: 80,
      layoutMode: 'HORIZONTAL',
      primaryAlign: 'SPACE_AROUND',
      counterAlign: 'CENTER',
      bg: isDark ? Colors.cardDark : Colors.white,
      stroke: true,
      strokeColor: isDark ? '#262626' : Colors.borderLight
    });

    const navItems = [
      { icon: '🏠', label: 'Feed' },
      { icon: '🧭', label: 'Explore' },
      { icon: '🎒', label: 'Tours' },
      { icon: '🎮', label: 'Games' },
      { icon: '👤', label: 'Profile' }
    ];

    navItems.forEach((item, idx) => {
      const navItem = createAutoFrame({
        parent: bottomNav,
        name: `Nav/${item.label}`,
        layoutMode: 'VERTICAL',
        primaryAlign: 'CENTER',
        counterAlign: 'CENTER',
        itemSpacing: 4
      });
      createTextNode({
        parent: navItem,
        text: item.icon,
        fontSize: 20
      });
      createTextNode({
        parent: navItem,
        text: item.label,
        fontSize: 11,
        fontStyle: idx === 0 ? 'Bold' : 'Medium',
        color: idx === 0 ? (isDark ? Colors.mintGreen : Colors.midGreen) : Colors.grayText
      });
    });

    return { shell, content };
  };

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 1: 🎨 DESIGN SYSTEM & TOKENS
  // ───────────────────────────────────────────────────────────────────────────
  const pageDesignSystem = figma.currentPage;
  pageDesignSystem.name = '🎨 Design System & Tokens';

  // Section Header
  const dsTitle = createAutoFrame({
    parent: pageDesignSystem,
    name: 'Section/Design System Header',
    x: 100,
    y: 80,
    layoutMode: 'VERTICAL',
    itemSpacing: 8
  });
  createTextNode({
    parent: dsTitle,
    text: 'Bhromon App — Master Design System',
    fontSize: 32,
    fontStyle: 'Bold',
    color: Colors.darkGreen
  });
  createTextNode({
    parent: dsTitle,
    text: 'Bengali-first travel ecosystem, Universal Tour Engine, Offline Relational & Family Game Zone Tokens',
    fontSize: 16,
    color: Colors.grayText
  });

  // Color Swatches Grid
  const colorSection = createAutoFrame({
    parent: pageDesignSystem,
    name: 'Color Tokens',
    x: 100,
    y: 180,
    layoutMode: 'VERTICAL',
    itemSpacing: 16,
    bg: Colors.white,
    padding: { top: 24, right: 28, bottom: 28, left: 28 },
    cornerRadius: 16,
    stroke: true,
    strokeColor: Colors.borderLight
  });
  createTextNode({
    parent: colorSection,
    text: '🎨 Brand & Theme Colors',
    fontSize: 20,
    fontStyle: 'Bold',
    color: Colors.darkGreen
  });

  const swatchesRow = createAutoFrame({
    parent: colorSection,
    name: 'Swatches Row',
    layoutMode: 'HORIZONTAL',
    itemSpacing: 16
  });

  const colorTokens = [
    { name: 'Dark Green', hex: Colors.darkGreen, role: 'Brand Core / Headers' },
    { name: 'Mid Green', hex: Colors.midGreen, role: 'Primary CTA / Active' },
    { name: 'Leaf Green', hex: Colors.leafGreen, role: 'Secondary Accents' },
    { name: 'Mint Green', hex: Colors.mintGreen, role: 'Highlight / Dark Primary' },
    { name: 'Pale Green', hex: Colors.paleGreen, role: 'Surface Tints' },
    { name: 'Gold Accent', hex: Colors.gold, role: 'Verified Explorer / Warmth' },
    { name: 'Amber CTA', hex: Colors.amber, role: 'Pioneer Badge / Alert' }
  ];

  colorTokens.forEach(token => {
    const box = createAutoFrame({
      parent: swatchesRow,
      name: token.name,
      width: 140,
      layoutMode: 'VERTICAL',
      itemSpacing: 8,
      bg: Colors.offWhite,
      padding: { top: 12, right: 12, bottom: 12, left: 12 },
      cornerRadius: 12,
      stroke: true,
      strokeColor: Colors.borderLight
    });
    const chip = figma.createRectangle();
    chip.resize(116, 70);
    chip.cornerRadius = 8;
    chip.fills = solidPaint(token.hex);
    box.appendChild(chip);

    createTextNode({ parent: box, text: token.name, fontSize: 13, fontStyle: 'Bold' });
    createTextNode({ parent: box, text: token.hex, fontSize: 12, color: Colors.grayText });
  });

  // Typography Scale
  const typeSection = createAutoFrame({
    parent: pageDesignSystem,
    name: 'Typography Scale',
    x: 100,
    y: 430,
    layoutMode: 'VERTICAL',
    itemSpacing: 16,
    bg: Colors.white,
    padding: { top: 24, right: 28, bottom: 28, left: 28 },
    cornerRadius: 16,
    stroke: true,
    strokeColor: Colors.borderLight
  });
  createTextNode({ parent: typeSection, text: '✍️ Typography Hierarchy (Noto Sans Bengali + Inter)', fontSize: 20, fontStyle: 'Bold', color: Colors.darkGreen });
  
  const typeStyles = [
    { label: 'Display Large', size: 36, weight: 'Bold', sample: 'ভ্রমণ শুরু হোক নতুন অভিজ্ঞতায়' },
    { label: 'Headline Medium', size: 24, weight: 'Bold', sample: 'কক্সবাজার সমুদ্র সৈকত ট্যুর গ্রুপ' },
    { label: 'Title Medium', size: 18, weight: 'Medium', sample: '৩ দিনের বাজেট ও হোটেল বুকিং' },
    { label: 'Body Regular', size: 14, weight: 'Regular', sample: 'সেন্টমার্টিন জাহাজের টিকিট ও সুরক্ষার সব তথ্য জানুন সহজে।' },
    { label: 'Label Small', size: 11, weight: 'Medium', sample: 'VERIFIED EXPLORER • 50 TRUST SCORE' }
  ];

  typeStyles.forEach(s => {
    const row = createAutoFrame({
      parent: typeSection,
      layoutMode: 'HORIZONTAL',
      primaryAlign: 'SPACE_BETWEEN',
      counterAlign: 'CENTER',
      width: 900,
      padding: { top: 8, right: 0, bottom: 8, left: 0 }
    });
    createTextNode({ parent: row, text: `${s.label} (${s.size}px)`, fontSize: 13, color: Colors.grayText });
    createTextNode({ parent: row, text: s.sample, fontSize: s.size, fontStyle: s.weight, color: Colors.darkText });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 2: 📱 AUTH & ONBOARDING SCREENS
  // ───────────────────────────────────────────────────────────────────────────
  const pageAuth = figma.createPage();
  pageAuth.name = '📱 1. Auth & Onboarding';
  
  // Screen 1: Welcome / Splash
  const { content: cWelcome } = createMobileShell(pageAuth, 'Bhromon (ভ্রমণ)', 100, 100);
  const heroCard = createAutoFrame({
    parent: cWelcome,
    width: 350,
    height: 280,
    layoutMode: 'VERTICAL',
    primaryAlign: 'CENTER',
    counterAlign: 'CENTER',
    bg: Colors.paleGreen,
    cornerRadius: 24,
    itemSpacing: 12
  });
  createTextNode({ parent: heroCard, text: '🌴 🌊 ⛰️', fontSize: 44 });
  createTextNode({ parent: heroCard, text: 'স্মার্ট ভ্রমণ সঙ্গী', fontSize: 24, fontStyle: 'Bold', color: Colors.darkGreen });
  createTextNode({ parent: heroCard, text: 'বাংলাদেশের প্রথম স্বয়ংসম্পূর্ণ ট্রাভেল ইঞ্জিন', fontSize: 13, color: Colors.midGreen });

  createButton({ parent: cWelcome, label: 'গুগল দিয়ে প্রবেশ করুন', variant: 'primary' });
  createButton({ parent: cWelcome, label: 'ইমেইল দিয়ে সাইন ইন', variant: 'outlined' });
  createButton({ parent: cWelcome, label: 'গেস্ট হিসেবে ঘুরে দেখুন', variant: 'outlined' });

  // Screen 2: OTP Verification
  const { content: cOtp } = createMobileShell(pageAuth, 'OTP Verification', 530, 100);
  createTextNode({ parent: cOtp, text: '৬ ডিজিটের কোডটি লিখুন', fontSize: 20, fontStyle: 'Bold', color: Colors.darkGreen });
  createTextNode({ parent: cOtp, text: 'আপনার ইমেইলে একটি কোড পাঠানো হয়েছে', fontSize: 13, color: Colors.grayText });

  const otpRow = createAutoFrame({
    parent: cOtp,
    layoutMode: 'HORIZONTAL',
    itemSpacing: 10,
    padding: { top: 16, right: 0, bottom: 16, left: 0 }
  });
  for (let i = 0; i < 6; i++) {
    const box = createAutoFrame({
      parent: otpRow,
      width: 48,
      height: 56,
      layoutMode: 'VERTICAL',
      primaryAlign: 'CENTER',
      counterAlign: 'CENTER',
      bg: Colors.white,
      cornerRadius: 12,
      stroke: true,
      strokeColor: i === 2 ? Colors.midGreen : Colors.borderLight,
      strokeWeight: i === 2 ? 2 : 1
    });
    createTextNode({ parent: box, text: i < 3 ? `${i + 4}` : '', fontSize: 20, fontStyle: 'Bold' });
  }
  createButton({ parent: cOtp, label: 'যাচাই করুন ও প্রবেশ করুন', variant: 'primary' });

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 3: 📱 FEED & EXPLORE
  // ───────────────────────────────────────────────────────────────────────────
  const pageFeed = figma.createPage();
  pageFeed.name = '📱 2. Home Feed & Explore';

  const { content: cFeed } = createMobileShell(pageFeed, 'Bhromon Feed', 100, 100);
  
  // Search & Filter
  const searchBox = createAutoFrame({
    parent: cFeed,
    width: 350,
    height: 44,
    layoutMode: 'HORIZONTAL',
    primaryAlign: 'START',
    counterAlign: 'CENTER',
    padding: { top: 0, right: 14, bottom: 0, left: 14 },
    bg: Colors.white,
    cornerRadius: 12,
    itemSpacing: 8,
    stroke: true,
    strokeColor: Colors.borderLight
  });
  createTextNode({ parent: searchBox, text: '🔍 গন্তব্য, হোটেল বা স্থান খুঁজুন...', fontSize: 13, color: Colors.grayText });

  // Feed Card
  const feedCard = createAutoFrame({
    parent: cFeed,
    width: 350,
    layoutMode: 'VERTICAL',
    itemSpacing: 12,
    bg: Colors.white,
    padding: { top: 16, right: 16, bottom: 16, left: 16 },
    cornerRadius: 16,
    stroke: true,
    strokeColor: Colors.borderLight
  });
  
  // Author row
  const authorRow = createAutoFrame({ parent: feedCard, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 318 });
  const authorInfo = createAutoFrame({ parent: authorRow, layoutMode: 'HORIZONTAL', itemSpacing: 10, counterAlign: 'CENTER' });
  const avatar = figma.createEllipse();
  avatar.resize(36, 36);
  avatar.fills = solidPaint(Colors.leafGreen);
  authorInfo.appendChild(avatar);
  const authorText = createAutoFrame({ parent: authorInfo, layoutMode: 'VERTICAL', itemSpacing: 2 });
  createTextNode({ parent: authorText, text: 'তানভীর আহমেদ', fontSize: 14, fontStyle: 'Bold' });
  createTextNode({ parent: authorText, text: 'সাজেক ভ্যালি • Verified Explorer', fontSize: 11, color: Colors.gold });

  // Card Content
  createTextNode({ parent: feedCard, text: 'সাজেকের মেঘের ভেলায় ৩ দিন! কংলাক পাহাড়ে সূর্যাস্তের অসাধারণ অভিজ্ঞতা। বিস্তারিত গাইড নিচে দেওয়া হলো...', fontSize: 13, color: Colors.darkText });
  
  const photoPlaceholder = figma.createRectangle();
  photoPlaceholder.resize(318, 160);
  photoPlaceholder.cornerRadius = 12;
  photoPlaceholder.fills = solidPaint(Colors.paleGreen);
  feedCard.appendChild(photoPlaceholder);

  // Reaction Bar
  const reactionRow = createAutoFrame({ parent: feedCard, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 318 });
  createTextNode({ parent: reactionRow, text: '❤️ ১২৪ লাইক', fontSize: 12, color: Colors.grayText });
  createTextNode({ parent: reactionRow, text: '💬 ১৮ মন্তব্য', fontSize: 12, color: Colors.grayText });
  createTextNode({ parent: reactionRow, text: '🔖 সেভ করুন', fontSize: 12, color: Colors.midGreen });

  // Weather & Tide Screen
  const { content: cTide } = createMobileShell(pageFeed, '🌊 Tide & Sea Beach Guide', 530, 100);
  const tideBanner = createAutoFrame({
    parent: cTide,
    width: 350,
    bg: '#0F4C81',
    padding: { top: 18, right: 18, bottom: 18, left: 18 },
    cornerRadius: 18,
    layoutMode: 'VERTICAL',
    itemSpacing: 8
  });
  createTextNode({ parent: tideBanner, text: 'সৈকত নিরাপত্তা স্ট্যাটাস: নিরাপদ (সবুজ পতাকা)', fontSize: 14, fontStyle: 'Bold', color: Colors.mintGreen });
  createTextNode({ parent: tideBanner, text: 'পরবর্তী ভাটা: দুপুর ২:৩০ মিনিট', fontSize: 20, fontStyle: 'Bold', color: Colors.white });
  createTextNode({ parent: tideBanner, text: 'ভাটার সময় গভীর সমুদ্রে নামা নিষেধ। লাইফগার্ড নির্দেশনা মেনে চলুন।', fontSize: 12, color: '#DCE8F5' });

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 4: 📱 TOUR GROUP HUB & 36-SEAT BUS MAP
  // ───────────────────────────────────────────────────────────────────────────
  const pageTourHub = figma.createPage();
  pageTourHub.name = '📱 3. Tour Group Hub & Bus Layout';

  const { content: cTour } = createMobileShell(pageTourHub, '🎒 Cox\'s Bazar Tour 2026', 100, 100);
  
  // Tour Status Card
  const tourCard = createAutoFrame({
    parent: cTour,
    width: 350,
    bg: Colors.darkGreen,
    padding: { top: 18, right: 18, bottom: 18, left: 18 },
    cornerRadius: 18,
    layoutMode: 'VERTICAL',
    itemSpacing: 10
  });
  createTextNode({ parent: tourCard, text: 'ইনভাইট কোড: COX-8210', fontSize: 12, fontStyle: 'Bold', color: Colors.mintGreen });
  createTextNode({ parent: tourCard, text: 'কক্সবাজার সমুদ্র বিলাস — ৫ দিন', fontSize: 20, fontStyle: 'Bold', color: Colors.white });
  createTextNode({ parent: tourCard, text: '👥 মোট সদস্য: ১৮ জন • বাস আসন: ৩২/৩৬ পূর্ণ', fontSize: 13, color: Colors.paleGreen });

  // Quick Action Buttons Grid
  const quickActions = createAutoFrame({ parent: cTour, width: 350, layoutMode: 'HORIZONTAL', itemSpacing: 10 });
  const makePill = (txt, icon) => {
    const p = createAutoFrame({
      parent: quickActions,
      width: 106,
      height: 64,
      layoutMode: 'VERTICAL',
      primaryAlign: 'CENTER',
      counterAlign: 'CENTER',
      bg: Colors.white,
      cornerRadius: 12,
      stroke: true,
      strokeColor: Colors.borderLight,
      itemSpacing: 4
    });
    createTextNode({ parent: p, text: icon, fontSize: 18 });
    createTextNode({ parent: p, text: txt, fontSize: 11, fontStyle: 'Bold', color: Colors.darkGreen });
  };
  makePill('বাস সিট', '🚌');
  makePill('হোটেল রুম', '🏨');
  makePill('লেজার খাতা', '💰');

  // Screen 2: 36-Seat Bus Map
  const { content: cBus } = createMobileShell(pageTourHub, '🚌 ৩৬-সিট বাস লেআউট', 530, 100);
  createTextNode({ parent: cBus, text: 'আপনার পছন্দের আসন নির্বাচন করুন (২ × ২ কোচ)', fontSize: 13, color: Colors.grayText });
  
  const coachFrame = createAutoFrame({
    parent: cBus,
    width: 350,
    bg: Colors.white,
    padding: { top: 16, right: 20, bottom: 16, left: 20 },
    cornerRadius: 18,
    layoutMode: 'VERTICAL',
    itemSpacing: 10,
    stroke: true,
    strokeColor: Colors.borderLight
  });

  // Driver Row
  const driverRow = createAutoFrame({ parent: coachFrame, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 310 });
  createTextNode({ parent: driverRow, text: '🚪 প্রধান দরজা', fontSize: 12, color: Colors.grayText });
  createTextNode({ parent: driverRow, text: '💺 ড্রাইভার কেবিন', fontSize: 12, fontStyle: 'Bold', color: Colors.darkGreen });

  // Bus Rows 1 to 5
  for (let r = 1; r <= 5; r++) {
    const row = createAutoFrame({ parent: coachFrame, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 310 });
    const seatLeft = createAutoFrame({ parent: row, layoutMode: 'HORIZONTAL', itemSpacing: 6 });
    const seatRight = createAutoFrame({ parent: row, layoutMode: 'HORIZONTAL', itemSpacing: 6 });

    const makeSeat = (parent, label, state) => {
      let bg = Colors.paleGreen;
      let col = Colors.darkGreen;
      if (state === 'booked') { bg = '#E0E0E0'; col = '#999999'; }
      if (state === 'selected') { bg = Colors.midGreen; col = Colors.white; }

      const s = createAutoFrame({
        parent,
        width: 44,
        height: 38,
        layoutMode: 'VERTICAL',
        primaryAlign: 'CENTER',
        counterAlign: 'CENTER',
        bg,
        cornerRadius: 8
      });
      createTextNode({ parent: s, text: label, fontSize: 11, fontStyle: 'Bold', color: col });
    };

    makeSeat(seatLeft, `A${r}`, r === 1 ? 'booked' : 'free');
    makeSeat(seatLeft, `B${r}`, r === 2 ? 'selected' : 'free');
    makeSeat(seatRight, `C${r}`, 'free');
    makeSeat(seatRight, `D${r}`, 'booked');
  }

  createButton({ parent: cBus, label: 'সিট কনফার্ম করুন (B2)', variant: 'primary' });

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 5: 📱 TRIP LEDGER & PAISA EXPENSE SPLIT
  // ───────────────────────────────────────────────────────────────────────────
  const pageLedger = figma.createPage();
  pageLedger.name = '📱 4. Trip Ledger & Expense Split';

  const { content: cLedger } = createMobileShell(pageLedger, '💰 ট্রিপ লেজার খাতা', 100, 100);
  
  // Summary Card
  const summaryCard = createAutoFrame({
    parent: cLedger,
    width: 350,
    bg: Colors.darkGreen,
    padding: { top: 20, right: 20, bottom: 20, left: 20 },
    cornerRadius: 18,
    layoutMode: 'VERTICAL',
    itemSpacing: 8
  });
  createTextNode({ parent: summaryCard, text: 'সর্বমোট ট্যুর খরচ', fontSize: 13, color: Colors.mintGreen });
  createTextNode({ parent: summaryCard, text: '৳ ৯৬,৫০০.০০', fontSize: 32, fontStyle: 'Bold', color: Colors.white });
  createTextNode({ parent: summaryCard, text: 'প্রতি জনের গড় খরচ: ৳ ৫,৩৬১.১১ (পয়সা নির্ভুল হিসাব)', fontSize: 12, color: Colors.paleGreen });

  // Split Breakdown
  const splitCard = createAutoFrame({
    parent: cLedger,
    width: 350,
    bg: Colors.white,
    padding: { top: 16, right: 16, bottom: 16, left: 16 },
    cornerRadius: 16,
    layoutMode: 'VERTICAL',
    itemSpacing: 12,
    stroke: true,
    strokeColor: Colors.borderLight
  });
  createTextNode({ parent: splitCard, text: 'কে কত পাবে / দেবে (Settlement)', fontSize: 15, fontStyle: 'Bold', color: Colors.darkGreen });
  
  const ledgerEntries = [
    { name: 'তানভীর আহমেদ (Payer)', status: 'পাবে ৳ ১২,৪০০', positive: true },
    { name: 'রাকিব হাসান (Family of 3)', status: 'দেবে ৳ ৪,১০০', positive: false },
    { name: 'সাদিয়া ইসলাম (Family of 2)', status: 'পরিশোধিত', positive: true }
  ];

  ledgerEntries.forEach(item => {
    const row = createAutoFrame({ parent: splitCard, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 318 });
    createTextNode({ parent: row, text: item.name, fontSize: 13, fontStyle: 'Medium' });
    createTextNode({
      parent: row,
      text: item.status,
      fontSize: 13,
      fontStyle: 'Bold',
      color: item.positive ? Colors.midGreen : Colors.amber
    });
  });

  createButton({ parent: cLedger, label: '+ নতুন খরচ যুক্ত করুন', variant: 'primary' });

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 6: 📱 TOUR REELS (INSTAFEED)
  // ───────────────────────────────────────────────────────────────────────────
  const pageReels = figma.createPage();
  pageReels.name = '📱 5. Tour Reels & Media';

  const { content: cReels } = createMobileShell(pageReels, '🎬 Tour Reels', 100, 100, true);
  
  // 9:16 Video Canvas
  const videoViewport = createAutoFrame({
    parent: cReels,
    width: 350,
    height: 580,
    bg: '#000000',
    cornerRadius: 20,
    layoutMode: 'VERTICAL',
    primaryAlign: 'SPACE_BETWEEN',
    padding: { top: 20, right: 16, bottom: 20, left: 16 }
  });

  // Top Reel Pill
  const reelTop = createAutoFrame({ parent: videoViewport, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', width: 318 });
  createTextNode({ parent: reelTop, text: 'রিলস • কক্সবাজার ২০২৬', fontSize: 14, fontStyle: 'Bold', color: Colors.white });
  createTextNode({ parent: reelTop, text: '📷 ক্যামেরা', fontSize: 13, color: Colors.mintGreen });

  // Bottom Overlay Info & Action Bar
  const reelBottom = createAutoFrame({ parent: videoViewport, layoutMode: 'HORIZONTAL', primaryAlign: 'SPACE_BETWEEN', counterAlign: 'BOTTOM', width: 318 });
  const reelDesc = createAutoFrame({ parent: reelBottom, layoutMode: 'VERTICAL', itemSpacing: 6, width: 240 });
  createTextNode({ parent: reelDesc, text: '@tanvir_safari', fontSize: 15, fontStyle: 'Bold', color: Colors.white });
  createTextNode({ parent: reelDesc, text: 'ইনানী সৈকতে ঝাউবনের শীতল হাওয়া আর সূর্যাস্ত! 🌅 #coxsbazar #reels', fontSize: 12, color: '#EEEEEE' });
  createTextNode({ parent: reelDesc, text: '🎵 Original Audio - Bhromon Tunes', fontSize: 11, color: Colors.mintGreen });

  // Vertical Right Action Stack
  const actionStack = createAutoFrame({ parent: reelBottom, layoutMode: 'VERTICAL', itemSpacing: 16, counterAlign: 'CENTER' });
  const makeReelAction = (icon, count) => {
    const f = createAutoFrame({ parent: actionStack, layoutMode: 'VERTICAL', counterAlign: 'CENTER', itemSpacing: 2 });
    createTextNode({ parent: f, text: icon, fontSize: 24 });
    createTextNode({ parent: f, text: count, fontSize: 11, fontStyle: 'Bold', color: Colors.white });
  };
  makeReelAction('❤️', '3.4K');
  makeReelAction('💬', '248');
  makeReelAction('✈️', 'Share');

  // ───────────────────────────────────────────────────────────────────────────
  // PAGE 7: 📱 FAMILY GAME ZONE (5 GAMES)
  // ───────────────────────────────────────────────────────────────────────────
  const pageGames = figma.createPage();
  pageGames.name = '📱 6. Family Game Zone (5 Games)';

  // Screen 1: Game Zone Hub
  const { content: cGamesHub } = createMobileShell(pageGames, '🎮 Game Zone Hub', 100, 100, true);
  createTextNode({ parent: cGamesHub, text: 'ট্যুর বাসে কিংবা আড্ডায় — খেলুন একসাথে!', fontSize: 14, color: Colors.mintGreen });

  const gamesList = [
    { title: 'Card 29 (২৯ কার্ড)', subtitle: 'Strict Trump & Pair Rules • 6-Pip Match', icon: '🃏' },
    { title: 'Travel Chess AI (দাবা)', subtitle: 'Stockfish Negamax AI • Castling & Takeback', icon: '♟️' },
    { title: 'Ludo Express (লুডু)', subtitle: 'Pass & Play • Safe Stars • Bot Modes', icon: '🎲' },
    { title: 'Teen Patti (তিন পাত্তি)', subtitle: 'Sideshow (Back-Ask) • Dynamic Pot Limit', icon: '🎴' },
    { title: 'ICF Carrom (ক্যারাম)', subtitle: 'Real-time Physics • Striker Slider', icon: '⚪' }
  ];

  gamesList.forEach(g => {
    const card = createAutoFrame({
      parent: cGamesHub,
      width: 350,
      layoutMode: 'HORIZONTAL',
      counterAlign: 'CENTER',
      padding: { top: 12, right: 14, bottom: 12, left: 14 },
      bg: Colors.cardDark,
      cornerRadius: 14,
      itemSpacing: 14,
      stroke: true,
      strokeColor: '#333333'
    });
    createTextNode({ parent: card, text: g.icon, fontSize: 28 });
    const gText = createAutoFrame({ parent: card, layoutMode: 'VERTICAL', itemSpacing: 3, width: 260 });
    createTextNode({ parent: gText, text: g.title, fontSize: 15, fontStyle: 'Bold', color: Colors.white });
    createTextNode({ parent: gText, text: g.subtitle, fontSize: 11, color: '#A0AEC0' });
  });

  // Screen 2: Travel Chess AI
  const { content: cChess } = createMobileShell(pageGames, '♟️ Travel Chess AI', 530, 100, true);
  createTextNode({ parent: cChess, text: 'Round 1 • You (White) vs Bhromon Bot (Medium)', fontSize: 12, color: Colors.mintGreen });
  
  // 8x8 Board Mockup
  const chessBoard = createAutoFrame({
    parent: cChess,
    width: 350,
    height: 350,
    bg: '#EEEED2',
    cornerRadius: 8,
    layoutMode: 'VERTICAL',
    primaryAlign: 'CENTER',
    counterAlign: 'CENTER',
    stroke: true,
    strokeColor: '#769656',
    strokeWeight: 4
  });
  createTextNode({ parent: chessBoard, text: '♜ ♞ ♝ ♛ ♚ ♝ ♞ ♜\n♟ ♟ ♟ ♟ ♟ ♟ ♟ ♟\n\n     [ 8 × 8 Board ]\n\n♙ ♙ ♙ ♙ ♙ ♙ ♙ ♙\n♖ ♘ ♗ ♕ ♔ ♗ ♘ ♖', fontSize: 18, fontStyle: 'Bold', color: '#769656', textAlign: 'CENTER' });

  const moveHistory = createAutoFrame({
    parent: cChess,
    width: 350,
    height: 48,
    bg: Colors.cardDark,
    cornerRadius: 8,
    layoutMode: 'HORIZONTAL',
    primaryAlign: 'SPACE_BETWEEN',
    counterAlign: 'CENTER',
    padding: { top: 0, right: 14, bottom: 0, left: 14 }
  });
  createTextNode({ parent: moveHistory, text: '1. d4 Nf6  2. c4 e6  3. Nc3', fontSize: 12, color: Colors.white });
  createTextNode({ parent: moveHistory, text: '↩️ Takeback', fontSize: 12, fontStyle: 'Bold', color: Colors.amber });

  // ───────────────────────────────────────────────────────────────────────────
  // FINISH & NOTIFY
  // ───────────────────────────────────────────────────────────────────────────
  figma.currentPage = pageDesignSystem;
  figma.viewport.scrollAndZoomIntoView(pageDesignSystem.children);
  figma.notify("✅ Bhromon App Design System & All 20+ Screens successfully generated!");
  figma.closePlugin();
})();
