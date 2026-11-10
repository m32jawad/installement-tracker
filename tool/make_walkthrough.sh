#!/usr/bin/env bash
# Builds the walkthrough MP4 from the screens rendered by test/screenshots_test.dart.
#   SCREENSHOTS_DIR=build/screens flutter test test/screenshots_test.dart
#   tool/make_walkthrough.sh build/screens build/walkthrough.mp4
set -euo pipefail
SRC=${1:-build/screens}; OUT=${2:-build/walkthrough.mp4}
FONT=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf
FONT2=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf
WORK=$(mktemp -d)
caption() {
  case "$1" in
    01_*) echo "First launch|Shop name, optional PIN, and demo data. No account, no internet needed." ;;
    02_*) echo "Dashboard|Who owes money right now: this month's total, collected, overdue, outstanding." ;;
    03_*) echo "Overdue and this week|Late customers show in red with days late. One tap to Collect, Remind or Skip." ;;
    04_*) echo "Month calendar|Dots mark due dates (red = overdue). Recent payments below." ;;
    05_*) echo "WhatsApp reminder|Pre-filled message opens in WhatsApp. SMS and Call are one tap too." ;;
    06_*) echo "All sales|Progress bar, status, and next due for every installment plan." ;;
    07_*) echo "Sale detail|Auto schedule with consistent colours: Paid, Skipped, Overdue, Pending, Partial." ;;
    08_*) echo "Collect payment|Full, partial or extra. Cash, Bank, JazzCash, Easypaisa, Cheque." ;;
    09_*) echo "Customers|Search by name, phone or CNIC. Badge: Good, Late, Skipped, Completed." ;;
    10_*) echo "Customer detail|Totals, next due, Call / WhatsApp, all sales and full payment history." ;;
    11_*) echo "Payment ledger|Filter by date range and method. Tap any payment to edit (audit logged)." ;;
    12_*) echo "Monthly report|Collected vs expected vs missed, by method. Export as PDF." ;;
    13_*) echo "Overall report|All-time totals, private profit, best payers, most late, top items." ;;
    14_*) echo "New sale wizard|Customer, item, plan, security photos, review. Schedule built for you." ;;
    15_*) echo "Settings|PIN, payment methods, backup and restore, Excel export, diagnostics." ;;
    16_*) echo "PIN lock|Asked on open and after 45 s in the background." ;;
    *) echo "Installment Tracker|" ;;
  esac
}
i=0
for f in "$SRC"/*.png; do
  name=$(basename "$f"); c=$(caption "$name"); title=${c%%|*}; body=${c#*|}
  printf '%s' "$title" > "$WORK/t$i.txt"
  printf '%s' "$body" | fold -s -w 34 > "$WORK/b$i.txt"
  ffmpeg -loglevel error -y -loop 1 -t 5 -i "$f" -filter_complex "\
color=c=0xF4F6F5:s=1600x900:d=5[bg];\
[0]scale=-1:840,format=rgba[ph];\
[bg][ph]overlay=x=150:y=30[v1];\
[v1]drawbox=x=620:y=300:w=12:h=300:color=0x0F7A55:t=fill,\
drawtext=fontfile=$FONT:textfile=$WORK/t$i.txt:x=660:y=310:fontsize=54:fontcolor=0x0F7A55,\
drawtext=fontfile=$FONT2:textfile=$WORK/b$i.txt:x=660:y=400:fontsize=36:fontcolor=0x222222:line_spacing=14,\
drawtext=fontfile=$FONT2:text='Installment Tracker  -  Android MVP':x=660:y=840:fontsize=24:fontcolor=0x888888,\
fade=t=in:st=0:d=0.35,fade=t=out:st=4.65:d=0.35,format=yuv420p" \
    -r 30 -c:v libx264 -preset veryfast -crf 22 "$WORK/s$i.mp4"
  echo "file '$WORK/s$i.mp4'" >> "$WORK/list.txt"
  i=$((i+1))
done
ffmpeg -loglevel error -y -f concat -safe 0 -i "$WORK/list.txt" -c copy -movflags +faststart "$OUT"
rm -rf "$WORK"
echo "$OUT"
