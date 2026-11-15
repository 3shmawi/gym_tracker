# Google Play: App content answers (إعداد تطبيقك)

What to choose in **Play Console → Policy and programs → App content**
(«محتوى التطبيق») and **Store settings**, for Azm. These forms have no
public API (Google Play Developer API v3, checked 2026-11-15: only Data
safety and the contact details can be set by API), so they are filled by
hand, once, and again only when the app changes in a way a form asks about.

Worked out from the code, `store/privacy_forms.md` and the website on
2026-11-15. When the app starts collecting something new, adds ads, sign-in
or payments, update this file, `store/privacy_forms.md` and the forms.

## 1. Privacy policy (سياسة الخصوصية)
- URL: `https://azmm.pages.dev/privacy`

## 2. App access (تفاصيل تسجيل الدخول)
- Choose **"All or some functionality in my app is restricted"**
  («بعض الوظائف مقيّدة»): everything works without an account, but joining a
  gym needs an invite code from a gym's captain.
- Add one instruction set:
  - Name: `Join a gym (optional)`
  - Username / password: leave empty; in **Any other information** write:
    `No account is needed: on the first screen tap "Train on my own", then
    "Pick a ready plan". To try gym features, tap "I have a code. Type it here" and enter
    the invite code below.` then the code.
  - **The code:** create a test gym in the captain dashboard
    (`https://azmm-dash.pages.dev`), add a trainee and copy the code. A code
    works once, so make a new one for each review, and keep the test gym.
- If you'd rather not keep a test gym, choose **"All functionality is
  available without special access"**: gym features are optional. Google can
  reject later if a reviewer reaches the code screen, so the code is safer.

## 3. Ads (الإعلانات)
- **Does your app contain ads?** **No** («لا، لا يحتوي تطبيقي على إعلانات»).
- Advertising ID (if Play asks): **No**. The app uses no ad SDK; check the
  merged manifest once (`android.permission.AD_ID` must not be in it).

## 4. Content rating (تقييم المحتوى)
- Email: the developer email (`mohager.dev@gmail.com`).
- Category: **All other app types** («جميع أنواع التطبيقات الأخرى»).
- Answer **No** to every content question: violence, fear, sexuality,
  gambling, language, controlled substances, crude humour.
- Interactive elements:
  - Users can interact or exchange content: **No** (no chat or posts; a
    captain sees their own gym's members' training, which is the service).
  - Shares the user's location: **No**.
  - Digital purchases: **No**.
  - Unrestricted internet access: **No** (how-to videos are YouTube videos
    the app or the gym picked, not a browser).
- Expected result: everyone / PEGI 3 / IARC 3+.

## 5. Target audience (الجمهور المستهدف)
- Age groups: **18 and over** (owner's choice to confirm; 13–17 can be added
  later, under-13 would bring the Families policy).
- Appeals to children: **No**.

## 6. Data safety (أمان البيانات)
Use the answers in `store/privacy_forms.md` → "Google Play: Data safety"
(data types table). Points that changed since that table was written:
- **Fitness info** is also collected for solo members who turn **backup**
  on (optional), not only for gym members.
- **Email address** is also collected for backup sign-in (optional).
- Data deletion: **Yes**, in the app (Profile → Delete account) and at
  `https://azmm.pages.dev/delete-account`.
- Do the two dashboard checks at the end of that section first (PostHog
  "Discard client IP data", Sentry "Prevent storing of IP addresses").
- Data safety can later be uploaded by API from a CSV in Google's own
  template (Play Console → Data safety → Export to CSV gives the template).

## 7. Government apps (التطبيقات الحكومية)
- **No**, it isn't made by or for a government.

## 8. Financial features (الميزات المالية)
- **"My app doesn't provide any financial features"**.

## 9. Health (صحة)
- Health features: **Activity and fitness** only (workout logging, rep
  counting). Not a medical device, no health records, no disease
  management.

## 10. App category and contact details (اختيار فئة التطبيق وتقديم تفاصيل الاتصال)
- App or game: **App**. Category: **Health & Fitness** («الصحة واللياقة البدنية»).
- Tags: Fitness, Workout tracker, Gym (the closest ones Play offers).
- Email: `mohager.dev@gmail.com` (already public on the website).
- Website: `https://azmm.pages.dev`.
- Phone: optional, leave empty.

## 11. Store listing
Done from the repo: `store/android/` → Actions → **Store listing**.
