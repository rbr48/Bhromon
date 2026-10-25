# Bhromon App — Figma Design System & Screens Generator

এই ফোল্ডারে সম্পূর্ণ **Bhromon (ভ্রমণ)** প্রজেক্টের ডিজাইন সিস্টেম, কালার ও টাইপোগ্রাফি টোকেন এবং ২০টিরও বেশি প্রধান স্ক্রিনের স্বয়ংক্রিয় Figma জেনারেটর তৈরি করে রাখা হয়েছে।

---

## 📂 ফাইল পরিচিতি (File Structure)

- **`plugin/manifest.json`** & **`plugin/code.js`**: অফিশিয়াল Figma Plugin স্ক্রিপ্ট যা Figma ক্যানভাসে স্বয়ংক্রিয়ভাবে পুরো প্রজেক্টের সব পেজ ও ফ্রেম তৈরি করে দেয়।
- **`tokens.json`**: W3C ও Tokens Studio স্ট্যান্ডার্ড ডিজাইন টোকেন (Figma Variables-এর জন্য)।
- **`bhromon_figma_preview.html`**: সম্পূর্ণ ভিজ্যুয়াল মকআপ ও স্ক্রিন প্রিভিউ (ব্রাউজারে ডাবল ক্লিক করলেই ওপেন হবে)।

---

## 🚀 ৩ ক্লিকে সম্পূর্ণ Figma ফাইল তৈরি করার নিয়ম (1-Click Generation)

Figma-র স্বত্বাধিকারী ফরম্যাট (`.fig`) সরাসরি বাইনারি কোড দিয়ে বানালে ক্র্যাশ/করাপ্ট হতে পারে। তাই Figma-র অফিশিয়াল প্লাগইন API দিয়ে ১ ক্লিকে পুরো ফাইলটি তৈরি করার স্বয়ংক্রিয় প্লাগইন দেওয়া হয়েছে:

### ধাপ ১: Figma ওপেন করুন
1. ব্রাউজারে বা ডেস্কটপ অ্যাপে [Figma](https://www.figma.com) ওপেন করুন।
2. একটি নতুন ব্ল্যাঙ্ক ডিজাইন ফাইল তৈরি করুন (**+ Design file**)।

### ধাপ ২: প্লাগইনটি ইম্পোর্ট করুন
1. উপরের বাম পাশের Figma মেনু আইকনে ক্লিক করুন।
2. **Plugins** -> **Development** -> **Import plugin from manifest...** সিলেক্ট করুন।
3. আপনার লোকাল প্রজেক্ট থেকে এই ফাইলটি সিলেক্ট করুন:  
   `e:\Projects\Bhromon\figma\plugin\manifest.json`

### ধাপ ৩: রান (Run) করুন
1. প্লাগইনের পাশে **Run** বাটনে ক্লিক করুন।
2. **মাত্র ২ সেকেন্ডের মধ্যে Figma-তে স্বয়ংক্রিয়ভাবে তৈরি হয়ে যাবে:**
   - **Page 1: 🎨 Design System & Tokens** (Forest Green, Mint, Gold, Trust Tier ব্যাজ ও টাইপোগ্রাফি)
   - **Page 2: 📱 Auth & Onboarding** (Welcome Hero, OTP Verification Screen)
   - **Page 3: 📱 Home Feed & Explore** (Smart Feed Card, Sea Beach & Tide Safety Guide)
   - **Page 4: 📱 Tour Group Hub & Bus Map** (Tour Hub, ৩৬-সিট বাস কোচ লেআউট ও সিট বুকিং)
   - **Page 5: 📱 Trip Ledger & Expense Split** (পয়সা নির্ভুল হিসাব, কে কত পাবে/দেবে সেটেলমেন্ট)
   - **Page 6: 📱 Tour Reels & Media** (৯:১৬ রিলস ভিডিও প্লেয়ার, কম্প্রেশন স্টুডিও)
   - **Page 7: 📱 Family Game Zone** (২৯ কার্ড, দাবা AI, লুডু এক্সপ্রেস, তিন পাত্তি, ক্যারাম)
   - **Page 8: 📱 Map & Offline Vault** (ম্যাপ ক্লাস্টার ও এনক্রিপ্টেড অফলাইন ভল্ট)

### ধাপ ৪: Native `.fig` ফাইল হিসেবে সেভ করুন
- ক্যানভাস তৈরি হয়ে গেলে Figma-র মেনু থেকে **File -> Save local copy...**-এ ক্লিক করলেই আপনার কম্পিউটারে মূল `.fig` ফাইলটি ডাউনলোড হয়ে যাবে।

---

## 🌐 ব্রাউজারে সরাসরি প্রিভিউ দেখতে:
ফাইল ম্যানেজারে গিয়ে [bhromon_figma_preview.html](file:///e:/Projects/Bhromon/figma/bhromon_figma_preview.html) ফাইলটি যেকোনো ব্রাউজারে ডাবল ক্লিক করে ওপেন করুন।
