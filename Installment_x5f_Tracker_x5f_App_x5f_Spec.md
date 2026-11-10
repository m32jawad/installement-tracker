# Installment Tracker - Mobile Application
## Detailed Product Specification & Feature Description

**Version:** 1.0 - MVP + Phase 2 Roadmap
**Date:** 10 November 2026
**Platform:** Mobile App (Android First, iOS Later) - Flutter / React Native Recommended
**Target User:** Small shop owner / individual seller who sells mobile phones (and other items) on installments
**Language Support:** English + Urdu (Roman Urdu option) - Phase 1: English UI with Urdu labels where needed

---

## 1. The Problem We Are Solving

Right now the seller keeps records in notebooks, WhatsApp chats, or memory. That causes:
- Forgetting who has to pay this month
- Not knowing who skipped, who is late, who is fully paid
- No proof of how much advance was paid, how much is pending
- No record of security documents (cheque, ID card, etc.)
- No monthly overview

**This app fixes all of that in one place.**

> One line summary: Add Customer -> Add Sale (Item + Price + Advance + Monthly Installment) -> App auto-creates installment schedule -> Collect payment each month -> See who is Due, Late, Skipped, or Paid.

---

## 2. Core User Flow (How The Seller Will Use It Daily)

### 2.1 Morning Routine - 2 Minutes
1. Open app -> Dashboard shows **Today's Due** and **This Month's Due**
2. See list: Customer A - Rs. 5,000 - Due 10 Oct
3. Tap customer -> Tap **Collect Payment** -> Enter amount, select Cash / Bank / JazzCash / Easypaisa / Cheque -> Save
4. Done. Receipt auto-saved.

### 2.2 New Sale Flow - 3 Minutes
1. Tap **+ New Sale**
2. Select existing Customer OR Add New Customer
3. Add Item: e.g. iPhone 13, Samsung A54, etc. + Description + Photos
4. Enter Total Price, Advance Payment, Monthly Installment Amount, Start Date, Total Months / Number of Installments
5. Add Security: Photo of CNIC, Cheque, Agreement Paper
6. Tap Save -> App auto-generates full installment schedule

### 2.3 End of Month Routine
1. Go to **Reports** -> See: Total Collected This Month, Total Pending, Total Overdue
2. See **Skipped / Late Customers** list
3. Send WhatsApp reminder in 1 tap

---

## 3. Detailed Features

## 3.1 Dashboard (Home Screen)

This is the first screen after opening the app. It must answer in 5 seconds: **"Who owes me money right now?"**

**Top Cards:**
- **Total To Collect This Month:** Rs. XX,XXX (sum of all installments due this month)
- **Collected This Month:** Rs. XX,XXX
- **Pending / Overdue:** Rs. XX,XXX
- **Total Outstanding (All Customers):** Rs. XXX,XXX

**Sections on Dashboard:**

1. **Due Today**
   - Customer Name, Item Name, Amount, Due Date
   - Buttons: [Collect] [Remind] [Mark Skipped]

2. **Due This Week (Next 7 Days)**
   - Same list, sorted by date

3. **Overdue / Late**
   - Red badge, shows days late: "12 days late"
   - Customer A - Rs. 5,000 - Was due 10 Oct

4. **Due This Month Calendar View**
   - Mini calendar with dots on due dates
   - Tap a date to see who is due that day

5. **Recent Payments**
   - Last 5-10 payments: "Customer A paid Rs. 5,000 via Cash on 10 Oct 2026"

6. **Quick Actions (Floating + Button)**
   - + Add Customer
   - + Add Sale
   - + Collect Payment
   - + Add Expense (Phase 2)

**Filters on Dashboard:**
- Filter by: All / Due Today / Overdue / This Month / Next Month
- Search by Customer Name / Phone / Item

---

## 3.2 Customers Management

### Add Customer
Fields:
- **Full Name*** (e.g. Customer A)
- **Phone Number*** (with WhatsApp button)
- **Alternate Phone** (optional)
- **CNIC Number** (optional, but recommended)
- **Address** (Home / Shop address)
- **Photo** (optional - take photo or from gallery)
- **Notes** (e.g. "Works at shop in main bazaar, reliable")
- **Guarantor Name + Phone** (optional - if someone else guarantees)

### Customer List
- Search + Alphabetical list
- Each customer card shows:
  - Name, Phone, Photo
  - Active Sales: 1
  - Total Pending: Rs. 25,000
  - Status Badge: **Good / Late / Skipped / Completed**

### Customer Detail Page (Tap a Customer)
- Profile info + Edit button
- **All Sales** for that customer (Current + Past)
- **Full Payment History** - Timeline view:
  ```
  10 Sep 2026 - Advance Paid - Rs. 20,000 - Cash
  10 Oct 2026 - Installment 1 - Rs. 5,000 - Bank Transfer - Paid
  10 Nov 2026 - Installment 2 - Rs. 5,000 - Skipped
  ```
- **Summary for this customer:**
  - Total Purchase Value
  - Total Paid
  - Total Pending / Due
  - Next Due Date + Amount
- **Actions:**
  - Call / WhatsApp Customer
  - Add New Sale for this customer
  - Collect Payment
  - Edit / Delete Customer (with confirmation)

---

## 3.3 Items / Products Management

Seller can pre-add items or add on-the-fly during sale.

### Add Item
- **Item Name***: e.g. iPhone 13 128GB, Samsung Galaxy A54, Vivo Y22, Infinix Hot 40
- **Category:** Mobile Phone / Tablet / Laptop / Other (custom)
- **Brand:** Apple / Samsung / Vivo / Oppo / Infinix / etc.
- **Model / Variant:** Color, Storage (128GB), RAM
- **IMEI / Serial Number** (very important for phones)
- **Description:** Condition, accessories included (charger, box, etc.)
- **Purchase Cost** (what seller bought it for - private, for profit calculation)
- **Selling Price** (default price for this item)
- **Photos:** Multiple photos of actual item
- **Stock Status:** Available / Sold / Reserved

### Item List
- Grid or list view with photo, name, price, status
- Filter: Available / Sold / All
- Tap to view details + history: "Sold to Customer A on 10 Sep 2026"

---

## 3.4 Sales / Installment Plans (The Heart of App)

This is where a sale is created.

### Create New Sale

**Step 1 - Select Customer**
- Search existing customer OR Create New

**Step 2 - Select Item**
- Search existing item OR Add New Item (with photos, IMEI, description)

**Step 3 - Payment Plan Details**
- **Total Sale Price***: e.g. Rs. 80,000
- **Advance / Down Payment***: e.g. Rs. 20,000 (paid on sale date)
- **Remaining Amount:** Auto-calculated = Total - Advance = Rs. 60,000
- **Monthly Installment Amount***: e.g. Rs. 5,000
- **Number of Installments:** Auto-calculated OR manual - e.g. 12 months (60,000 / 5,000)
- **Installment Frequency:** Monthly (default) / Weekly / Bi-weekly / Custom
- **First Installment Due Date***: e.g. 10 Oct 2026
- **Sale Date***: e.g. 10 Sep 2026
- **Payment Method for Advance:** Cash / Bank Transfer / JazzCash / Easypaisa / Cheque / Other
- **Notes / Description:** e.g. "Customer promised to pay before 10th every month"

**Step 4 - Security / Guarantee Documents**
- **Security Type:** (Multi-select)
  - [ ] CNIC Copy (Front + Back photo)
  - [ ] Cheque (Photo of cheque + Cheque Number + Bank Name + Date)
  - [ ] Guarantor CNIC
  - [ ] Signed Agreement / Stamp Paper (Photo)
  - [ ] Other Document (Photo + Note)
- For each: Add Photo (Camera / Gallery) + Small Note
- **Important:** These photos are stored securely and only visible inside app.

**Step 5 - Review & Save**
- Show summary: Customer, Item, Total, Advance, Monthly, Total Months, End Date
- Tap **Create Sale** -> App auto-creates installment schedule

### Example - Real Case You Gave

> **Customer A** purchased **Mobile Phone ABC** on **10 Sep 2026**
> - Total Price: Rs. 80,000
> - Advance Paid: Rs. 20,000 on 10 Sep 2026 (Cash)
> - Monthly Installment: Rs. 5,000
> - Schedule auto-generated:
>   - 10 Oct 2026 - Installment 1 - Rs. 5,000 - Pending
>   - 10 Nov 2026 - Installment 2 - Rs. 5,000 - Pending
>   - 10 Dec 2026 - Installment 3 - Rs. 5,000 - Pending
>   - ... until 10 Sep 2027 - Installment 12 - Rs. 5,000 - Pending
> - Total Pending after advance: Rs. 60,000

### Sale Detail Page
- Header: Customer Name + Item Name + Photo
- **Progress Bar:** Paid 25% - Rs. 20,000 / Rs. 80,000
- **Summary Cards:**
  - Total Price: Rs. 80,000
  - Paid So Far: Rs. 25,000 (Advance + 1 installment)
  - Remaining / Pending: Rs. 55,000
  - Next Due: 10 Nov 2026 - Rs. 5,000
  - Status: Active / Completed / Overdue
- **Installment Schedule Timeline:**
  - Each row: Installment #, Due Date, Amount, Status, Payment Method, Paid Date
  - Status Colors:
    - 🟢 Green = Paid
    - 🟡 Yellow = Due Soon / Pending
    - 🔴 Red = Overdue / Late
    - ⚫ Grey = Skipped
    - 🔵 Blue = Partially Paid
- **Security Documents Section:** Thumbnails, tap to view full image
- **Actions:** Edit Sale | Collect Payment | Mark Installment Skipped | Add Note | Delete Sale

---

## 3.5 Payments & Installment Collection

### Collect Payment Flow
From Dashboard, Customer Detail, or Sale Detail -> Tap **Collect Payment**

Fields:
- **Sale:** Auto-selected (if from sale page)
- **Installment:** Which installment? (e.g. Installment 2 - Due 10 Nov)
- **Amount Paid***: e.g. Rs. 5,000 (can be full, partial, or extra)
- **Payment Date***: Defaults to Today, can change to past date
- **Payment Method***:
  - Cash
  - Bank Transfer (Bank Name + Transaction ID optional)
  - JazzCash
  - Easypaisa
  - Cheque (Cheque Number)
  - Other
- **Receipt / Proof Photo:** Optional - photo of bank slip / cheque
- **Note:** e.g. "Paid late, promised to pay next on time"

**Logic:**
- If Amount = Full Installment -> Mark as **Paid**
- If Amount < Installment -> Mark as **Partially Paid** + Remaining shows as still due
- If Amount > Installment -> Ask: "Apply extra to next installment?" Yes / Keep as advance
- Auto-update: Paid So Far, Pending, Next Due Date

### Edit Payment
- Tap any payment in history -> Edit Amount, Date, Method, Note
- App recalculates totals automatically
- Show "Edited" tag + history of edits (audit log)

### Mark As Skipped
- Tap installment -> **Mark as Skipped**
- Reason (optional): "Customer said will pay next month double" / "Out of city" / "No response"
- Skipped installments stay in timeline in Grey, and next due remains visible
- Seller can later **Un-skip** and collect it

### Mark As Late / Overdue
- Automatic: If Due Date passes and status is still Pending -> Auto becomes **Overdue**
- Show "X days late" badge

### Payment History / Ledger
- Global list of all payments: Search by customer, date, method
- Filter by: Date Range, Method, Status
- Each entry: Date, Customer, Item, Amount, Method, Installment #

---

## 3.6 Reminders & Notifications

- **In-App Reminders:** Dashboard highlights Due Today / Tomorrow / Overdue
- **Push Notifications (Phase 1.5):**
  - Morning 9 AM: "3 customers due today - Rs. 15,000"
  - Day before due: "Customer A due tomorrow"
  - On due date: "Customer A due today"
- **WhatsApp Reminder (1-Tap):**
  - Template: "Assalam-o-Alaikum [Name], your installment of Rs. 5,000 for [Item] is due on [Date]. Please pay on time. Thank you - [Shop Name]"
  - Opens WhatsApp with pre-filled message, seller just taps Send
- **SMS Reminder:** Optional if WhatsApp not available
- **Call Reminder:** Tap phone icon to call directly

---

## 3.7 Reports & Insights

### Monthly Report
- Month Selector (Oct 2026, Nov 2026...)
- **Collected:** Rs. XX,XXX (with breakdown by Cash / Bank / JazzCash)
- **Expected:** Rs. XX,XXX
- **Pending / Missed:** Rs. XX,XXX
- **List:** Who paid, who skipped, who is overdue

### Overall Reports
- **Total Business Overview:**
  - Total Sales (All Time)
  - Total Collected
  - Total Outstanding / Pending
  - Total Profit (Selling Price - Purchase Cost) - Private
- **Customer-wise Report:** Who is best payer, who is most late
- **Item-wise Report:** Which phones sell most on installments

### Export
- Export Monthly Report as PDF
- Export Customer Ledger as PDF / Excel
- Share via WhatsApp / Email

---

## 3.8 Search, Filter & Sorting

Global Search Bar on every list:
- Search by: Customer Name, Phone, CNIC, Item Name, IMEI
- Filters:
  - Status: Paid / Pending / Overdue / Skipped / Completed
  - Date Range: This Week / This Month / Custom
  - Payment Method: Cash / Bank / etc.
- Sort by: Due Date (Nearest First) / Amount (High to Low) / Name A-Z

---

## 3.9 Security Documents & Attachments

Dedicated secure section per Sale:
- View all attached images in gallery
- Add / Delete photos (with confirmation)
- Types supported:
  - CNIC Front / Back
  - Cheque Photo
  - Agreement / Stamp Paper
  - Customer Photo with Item
  - Any other proof
- Each photo has: Date Added, Note, Type
- **Privacy:** Photos are stored locally + encrypted backup (if cloud sync enabled). No one else can see without app PIN.

---

## 3.10 Settings & App Security

- **App Lock:** PIN / Fingerprint / Face ID to open app
- **Profile:** Shop Name, Owner Name, Phone, Address (appears on receipts/messages)
- **Backup & Restore:** Auto-backup to Google Drive / Local backup (Export .db file)
- **Data Export:** Export All Data as Excel / CSV
- **Payment Methods:** Customize list (Add "Raast", "Bank Al Habib", etc.)
- **Installment Settings:** Default Due Day (e.g. 10th), Default Reminder Days Before
- **Language:** English / Urdu
- **Currency:** PKR (Rs.) default, can change
- **Theme:** Light / Dark
- **Delete Data:** Clear all / Reset app (with warning)

---

## 4. Data Model (For Developer)

### Tables / Collections

**1. customers**
- id, name, phone, alt_phone, cnic, address, photo_url, guarantor_name, guarantor_phone, notes, created_at, updated_at

**2. items**
- id, name, category, brand, model, imei, description, purchase_cost, selling_price, photos[], status (available/sold), created_at

**3. sales**
- id, customer_id, item_id, sale_date, total_price, advance_amount, advance_method, advance_date, monthly_amount, total_installments, frequency, first_due_date, status (active/completed/cancelled), notes, created_at

**4. installments**
- id, sale_id, installment_number, due_date, amount, paid_amount, status (pending/paid/partial/skipped/overdue), paid_date, payment_method, note, created_at

**5. payments**
- id, sale_id, installment_id, customer_id, amount, payment_date, method, transaction_id, receipt_photo, note, created_by, created_at, edited_at

**6. security_documents**
- id, sale_id, type (cnic/cheque/agreement/other), photo_url, note, cheque_number, bank_name, created_at

**7. users / settings**
- shop_name, owner_name, phone, pin, language, currency, backup_enabled

---

## 5. Screens List (App Map)

1. Splash Screen
2. PIN Lock / Login
3. Dashboard / Home
4. Customers List
5. Add / Edit Customer
6. Customer Detail
7. Items List
8. Add / Edit Item
9. Item Detail
10. Sales List (All Installment Plans)
11. Create New Sale (3-Step Wizard)
12. Sale Detail + Installment Timeline
13. Collect Payment (Bottom Sheet / Modal)
14. Payment History / Ledger
15. Reports
16. Security Documents Gallery
17. Reminders / Due List
18. Settings
19. Backup / Export

**Navigation:** Bottom Tab Bar: [Home] [Customers] [Sales] [Payments] [Reports] + Center Floating [+] Button

---

## 6. Design Guidelines

- **Style:** Clean, simple, big buttons - made for shop owner, not tech expert
- **Colors:**
  - Primary: Deep Green (#0F7A55) - Money / Trust
  - Accent: Gold / Orange for Due
  - Danger: Red for Overdue
  - Success: Green for Paid
  - Background: Light Grey / White, Dark Mode supported
- **Font:** Large, readable - Urdu + English support
- **Cards:** Rounded, shadow, easy to tap
- **Status Colors Must Be Consistent Everywhere:** Same green/red/yellow/grey across app
- **Offline First:** App must work without internet. Sync when online.

---

## 7. Tech Recommendations

- **Framework:** Flutter (Best for Android + iOS with one codebase) - Alternative: React Native
- **Local DB:** SQLite / Hive / Isar (Offline first)
- **Cloud Sync (Phase 2):** Firebase Firestore + Firebase Storage for photos
- **Backup:** Google Drive API / Local File Export
- **Notifications:** Firebase Cloud Messaging + Local Notifications
- **WhatsApp:** WhatsApp Deep Link (wa.me) - No API needed for MVP
- **PDF Export:** pdf package / printing
- **Auth:** Local PIN + Biometric (No email login needed for MVP)

---

## 8. MVP vs Phase 2

### MVP (Version 1.0) - Must Have
- [x] Add/Edit Customers
- [x] Add/Edit Items
- [x] Create Sale with Advance + Monthly Installments
- [x] Auto Installment Schedule
- [x] Collect Payment (Cash/Bank/JazzCash/Easypaisa)
- [x] Edit Payment
- [x] Mark Skipped / Overdue auto
- [x] Dashboard - Due Today / This Month / Overdue
- [x] Customer Detail + Sale Detail
- [x] Security Documents Photos (CNIC, Cheque)
- [x] Search & Filters
- [x] PIN Lock
- [x] Offline Working
- [x] Basic Reports + PDF Export

### Phase 2 (Version 1.5 - 2.0)
- [ ] Push Notifications + Auto Reminders
- [ ] WhatsApp Auto Reminder Templates
- [ ] Cloud Sync + Multi-device
- [ ] Multi-user / Staff login (Owner + Employee)
- [ ] Expense Tracking + Profit Report
- [ ] Late Fee / Penalty Calculation
- [ ] Receipt Printing (Bluetooth Printer)
- [ ] Customer App View (Customer can see own due via link)
- [ ] Urdu Full Translation
- [ ] EMI Calculator Widget

---

## 9. Example Scenarios For Testing

**Scenario 1:** Customer A buys phone, pays advance, pays 2 installments, skips 3rd, pays 4th double - App should show Skipped for 3rd, Paid for others, Pending correctly recalculated.

**Scenario 2:** Customer pays partial - Installment Rs. 5,000, pays Rs. 3,000 - App shows Partially Paid, Remaining Rs. 2,000 still due.

**Scenario 3:** Customer pays early - Due 10 Nov, pays 5 Nov - App marks Paid, Next Due still 10 Dec.

**Scenario 4:** Seller edits a payment amount - Totals update everywhere instantly.

**Scenario 5:** Seller adds cheque photo - Photo appears in Sale Detail under Security Documents.

---

## 10. What To Tell Developer

> "Build me an offline-first mobile app for installment tracking. Main user is a mobile phone seller in Pakistan. He needs to add customers, add phones/items, create installment sales with advance + monthly amount, auto-generate schedule, collect payments with cash/bank methods, mark skipped, attach CNIC/cheque photos, and see dashboard of who is due today/this month/overdue. Keep UI very simple, big buttons, Urdu-friendly, PIN lock, and PDF export for reports."

---

**End of Specification**
