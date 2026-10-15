#!/usr/bin/env python3
"""يفحص مصادر الأخبار ويرسل إشعارًا عاجلًا إلى تطبيق أخبارك عبر خدمة الإشعارات المجانية.

يعمل على خدمة الجدولة المجانية في جيت هب، فلا يحتاج جهازك ولا أي مصاريف.
القاعدة: لا يُرسل إشعار إلا لخبر عاجل تؤكده عدة مصادر مختلفة (أو يحمل كلمة "عاجل")،
وبذلك لا يصلك إشعار مزعج لكل خبر.
"""
import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

try:
    from zoneinfo import ZoneInfo
    CAIRO = ZoneInfo("Africa/Cairo")
except Exception:  # pragma: no cover
    CAIRO = timezone(timedelta(hours=3))

# المصادر المراقبة (الاسم، الرابط)
FEEDS = [
    ("بي بي سي عربي", "https://feeds.bbci.co.uk/arabic/rss.xml"),
    ("العربية", "https://www.alarabiya.net/feed/rss2/ar.xml"),
    ("الجزيرة", "https://www.aljazeera.net/aljazeerarss/a7c186be-1baa-4bd4-9d80-a84db769f779/73d0e1b4-532f-45ef-b135-bfdff8b8cab9"),
    ("سكاي نيوز عربية", "https://www.skynewsarabia.com/web/rss"),
    ("اليوم السابع", "https://www.youm7.com/rss/SectionRss?SectionID=65"),
    ("الشروق", "https://www.shorouknews.com/egypt/rss"),
    ("القاهرة ٢٤", "https://www.cairo24.com/rss.aspx"),
]

WINDOW_MIN = int(os.environ.get("WINDOW_MIN", "45"))      # عمر الخبر المقبول بالدقائق
MIN_SOURCES = int(os.environ.get("MIN_SOURCES", "2"))     # عدد المصادر المطلوب لتأكيد الخبر
MAX_PER_RUN = int(os.environ.get("MAX_PER_RUN", "3"))     # أقصى عدد إشعارات في التشغيلة
KEEP_HOURS = 12                                            # مدة تذكّر الأخبار المرسلة
STATE_PATH = os.environ.get("STATE", "state/seen.json")

URGENT_RE = re.compile(
    r"عاجل|حرب|قصف|غارة|غارات|هجوم|هجمات|زلزال|هزة|إعصار|اعصار|عاصفة|فيضان|فيضانات|سيول|"
    r"حريق|حرائق|كارثة|انفجار|انفجارات|مقتل|ضحايا|بركان|تسونامي|اشتباك|اشتباكات|صاروخ|صواريخ|"
    r"مسيرة|مسيّرة|اغتيال|انهيار|غرق|تحطم|إخلاء|طوارئ"
)


def norm(s):
    s = re.sub(r"[ً-ْـ]", "", s.lower())
    s = re.sub(r"[إأآ]", "ا", s)
    s = s.replace("ى", "ي").replace("ة", "ه")
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    return re.sub(r"\s+", " ", s).strip()


def tokens(title):
    return {w for w in norm(title).split(" ") if len(w) > 2}


def same_story(a, b):
    n = len(a & b)
    u = len(a | b)
    if u == 0:
        return False
    r = n / u
    return (r > 0.55 and n >= 2) or (r > 0.38 and n >= 4)


def parse_date(text):
    """يحوّل تاريخ الخبر إلى توقيت عالمي؛ الذي بلا منطقة زمنية نعتبره بتوقيت القاهرة."""
    text = (text or "").strip()
    if not text:
        return None
    d = None
    try:
        d = parsedate_to_datetime(text)
    except Exception:
        pass
    if d is None:
        for fmt in ("%m/%d/%Y %I:%M:%S %p", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
            try:
                d = datetime.strptime(text, fmt)
                break
            except ValueError:
                continue
    if d is None:
        try:
            d = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except Exception:
            return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=CAIRO)
    return d.astimezone(timezone.utc)


def fetch(name, url):
    out = []
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (akhbarak-push)"})
        raw = urllib.request.urlopen(req, timeout=15).read()
        root = ET.fromstring(raw)
    except Exception as e:
        print(f"تعذر تحميل {name}: {e}", file=sys.stderr)
        return out
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        link = (it.findtext("link") or "").strip()
        when = parse_date(it.findtext("pubDate") or it.findtext("{http://purl.org/dc/elements/1.1/}date"))
        if title and when:
            out.append({"src": name, "title": title, "link": link, "time": when})
    return out


def load_state():
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f), True
    except Exception:
        return {"sent": []}, False


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH) or ".", exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)


def pick_alerts(items, state, now):
    """يعيد الأخبار العاجلة الجديدة المؤكدة (قائمة من {title, link, sources})."""
    lim = now - timedelta(minutes=WINDOW_MIN)
    recent = [i for i in items if i["time"] >= lim and URGENT_RE.search(i["title"])]
    recent.sort(key=lambda i: i["time"])

    clusters = []  # كل عنصر: {tok, items}
    for it in recent:
        tk = tokens(it["title"])
        for c in clusters:
            if same_story(tk, c["tok"]):
                c["items"].append(it)
                c["tok"] |= tk
                break
        else:
            clusters.append({"tok": set(tk), "items": [it]})

    cutoff = (now - timedelta(hours=KEEP_HOURS)).timestamp()
    state["sent"] = [s for s in state.get("sent", []) if s["ts"] >= cutoff]
    sent_tokens = [set(s["tok"]) for s in state["sent"]]

    alerts = []
    for c in clusters:
        srcs = {i["src"] for i in c["items"]}
        breaking = any("عاجل" in i["title"] for i in c["items"])
        if len(srcs) < MIN_SOURCES and not breaking:
            continue
        if any(same_story(c["tok"], t) for t in sent_tokens):
            continue
        first = c["items"][0]
        alerts.append({"title": first["title"], "link": first["link"], "sources": sorted(srcs), "tok": c["tok"]})
    return alerts[-MAX_PER_RUN:]


def access_token(info):
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    creds = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    creds.refresh(Request())
    return creds.token


def send(info, title, body, link):
    import requests

    msg = {
        "message": {
            "topic": "urgent",
            "notification": {"title": title, "body": body},
            "data": {"link": link or ""},
            "android": {"priority": "HIGH", "ttl": "3600s"},
        }
    }
    r = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send",
        headers={"Authorization": f"Bearer {access_token(info)}"},
        json=msg,
        timeout=20,
    )
    print("FCM", r.status_code, r.text[:200])
    r.raise_for_status()


def main():
    dry = os.environ.get("DRY_RUN") == "1"
    raw = os.environ.get("FCM_SERVICE_ACCOUNT", "")
    if not raw and not dry:
        print("لم يُضبط السر FCM_SERVICE_ACCOUNT", file=sys.stderr)
        return 1
    info = json.loads(raw) if raw else {}

    if os.environ.get("TEST_ONLY") == "1":
        send(info, "اختبار أخبارك", "إذا وصلك هذا الإشعار فالإعداد سليم", "")
        return 0

    now = datetime.now(timezone.utc)
    items = []
    for name, url in FEEDS:
        items.extend(fetch(name, url))
    print(f"عدد الأخبار المحمّلة: {len(items)}")

    state, existed = load_state()
    alerts = pick_alerts(items, state, now)
    print(f"أخبار عاجلة جديدة: {len(alerts)}")

    for a in alerts:
        # التشغيلة الأولى تسجّل الأخبار الحالية فقط حتى لا يصلك سيل إشعارات قديمة
        if existed and not dry:
            try:
                send(info, "عاجل", a["title"], a["link"])
            except Exception as e:
                print("فشل الإرسال:", e, file=sys.stderr)
                continue
        elif dry:
            print("[تجربة] عاجل:", a["title"], a["sources"])
        state["sent"].append({"ts": now.timestamp(), "tok": sorted(a["tok"])})
        time.sleep(1)

    save_state(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
